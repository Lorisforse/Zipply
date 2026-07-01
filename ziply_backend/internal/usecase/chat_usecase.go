package usecase

import (
	"context"
	"strings"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// ChatRepository definisce i metodi richiesti per la persistenza di sessioni
// e messaggi di chat, lato utente (UT.10) e lato operatore (OP.08).
type ChatRepository interface {
	GetOpenSession(ctx context.Context, userID string) (*domain.ChatSession, error)
	CreateSession(ctx context.Context, userID string) (*domain.ChatSession, error)
	SetEscalated(ctx context.Context, sessionID string) error
	AddMessage(ctx context.Context, msg *domain.ChatMessage) error
	GetMessages(ctx context.Context, sessionID string) ([]domain.ChatMessage, error)
	GetSession(ctx context.Context, sessionID, userID string) (*domain.ChatSession, error)
	GetSessionByID(ctx context.Context, sessionID string) (*domain.ChatSession, error)
	ListForOperator(ctx context.Context) ([]domain.OperatorChatSession, error)
	CloseSession(ctx context.Context, sessionID string) error
}

// ChatUsecase gestisce la logica di sessione, risposta bot ed escalation.
type ChatUsecase struct {
	repo ChatRepository
}

// NewChatUsecase crea un nuovo ChatUsecase.
func NewChatUsecase(repo ChatRepository) *ChatUsecase {
	return &ChatUsecase{repo: repo}
}

// GetOrCreateSession restituisce la sessione aperta dell'utente o ne crea una nuova.
func (u *ChatUsecase) GetOrCreateSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	session, err := u.repo.GetOpenSession(ctx, userID)
	if err != nil {
		return nil, err
	}
	if session != nil {
		return session, nil
	}
	return u.repo.CreateSession(ctx, userID)
}

// SendMessage salva il messaggio dell'utente e, finché la sessione è gestita
// dal bot, genera la risposta automatica scalando eventualmente a operatore.
// Una volta che la sessione è passata a operatore, il bot non risponde più: il
// messaggio viene solo persistito e resta in carico all'operatore umano.
func (u *ChatUsecase) SendMessage(ctx context.Context, sessionID, userID, body string) ([]domain.ChatMessage, error) {
	session, err := u.repo.GetSession(ctx, sessionID, userID)
	if err != nil {
		return nil, err
	}

	userMsg := &domain.ChatMessage{
		SessionID: sessionID,
		Sender:    "utente",
		Text:      body,
	}
	if err := u.repo.AddMessage(ctx, userMsg); err != nil {
		return nil, err
	}

	// Sessione già scalata: nessuna risposta del bot, parola all'operatore.
	if session.Status != domain.ChatStatusBot {
		return []domain.ChatMessage{*userMsg}, nil
	}

	replyText, escalate := botReply(body)

	if escalate {
		_ = u.repo.SetEscalated(ctx, sessionID)
	}

	botMsg := &domain.ChatMessage{
		SessionID: sessionID,
		Sender:    "bot",
		Text:      replyText,
	}
	if err := u.repo.AddMessage(ctx, botMsg); err != nil {
		return nil, err
	}

	return []domain.ChatMessage{*userMsg, *botMsg}, nil
}

// GetMessages restituisce tutti i messaggi di una sessione.
func (u *ChatUsecase) GetMessages(ctx context.Context, sessionID, userID string) ([]domain.ChatMessage, *domain.ChatSession, error) {
	session, err := u.repo.GetSession(ctx, sessionID, userID)
	if err != nil {
		return nil, nil, err
	}
	msgs, err := u.repo.GetMessages(ctx, sessionID)
	if err != nil {
		return nil, nil, err
	}
	return msgs, session, nil
}

// botReply restituisce la risposta del bot e se occorre fare escalation.
func botReply(message string) (string, bool) {
	msg := strings.ToLower(message)

	switch {
	case containsAny(msg, "prenotazione", "prenoto", "annullo", "cancello", "booking"):
		return "Per gestire le tue prenotazioni vai nel menu → Storico corse. Per annullare una prenotazione attiva usa il pulsante nella schermata della mappa.", false
	case containsAny(msg, "tariffa", "costo", "prezzo", "quanto", "pagamento", "pago"):
		return "Le tariffe Ziply: sblocco 0,50€ + 0,25€/min. Puoi risparmiare con un abbonamento mensile. Vai su Menu → Abbonamenti per i dettagli.", false
	case containsAny(msg, "problema", "non funziona", "guasto", "rotto", "malfunzionamento"):
		return "Puoi segnalare un guasto direttamente dalla schermata del mezzo durante la corsa, usando il pulsante 'Segnala problema'.", false
	case containsAny(msg, "abbonamento", "piano", "mensile"):
		return "Gli abbonamenti Ziply sono disponibili per tipologia di mezzo. Vai su Menu → Abbonamenti per visualizzare e attivare un piano.", false
	case containsAny(msg, "operatore", "umano", "persona", "aiuto", "supporto"):
		return "Ti metto subito in contatto con un operatore. Attendi qualche minuto.", true
	default:
		return "Non ho capito la tua richiesta. Ti connetto con un operatore che potrà aiutarti.", true
	}
}

func containsAny(s string, keywords ...string) bool {
	for _, k := range keywords {
		if strings.Contains(s, k) {
			return true
		}
	}
	return false
}

// ListOperatorSessions restituisce le chat scalate a operatore per la console
// di supporto (OP.08), piu' recenti prima in base all'ultimo messaggio.
func (u *ChatUsecase) ListOperatorSessions(ctx context.Context) ([]domain.OperatorChatSession, error) {
	return u.repo.ListForOperator(ctx)
}

// GetOperatorMessages restituisce lo storico messaggi di una sessione per la
// console operatore (OP.08), senza vincolo di appartenenza utente.
func (u *ChatUsecase) GetOperatorMessages(ctx context.Context, sessionID string) ([]domain.ChatMessage, *domain.ChatSession, error) {
	session, err := u.repo.GetSessionByID(ctx, sessionID)
	if err != nil {
		return nil, nil, err
	}
	msgs, err := u.repo.GetMessages(ctx, sessionID)
	if err != nil {
		return nil, nil, err
	}
	return msgs, session, nil
}

// SendOperatorMessage salva un messaggio inviato dall'operatore (OP.08). Non
// e' possibile scrivere in una sessione gia' chiusa.
func (u *ChatUsecase) SendOperatorMessage(ctx context.Context, sessionID, text string) (*domain.ChatMessage, error) {
	session, err := u.repo.GetSessionByID(ctx, sessionID)
	if err != nil {
		return nil, err
	}
	if session.Status == domain.ChatStatusChiusa {
		return nil, domain.ErrChatSessionClosed
	}

	msg := &domain.ChatMessage{
		SessionID: sessionID,
		Sender:    "operatore",
		Text:      text,
	}
	if err := u.repo.AddMessage(ctx, msg); err != nil {
		return nil, err
	}
	return msg, nil
}

// CloseSession chiude una sessione di chat (OP.08): l'utente, se scrive di
// nuovo, aprira' una nuova sessione partendo dal bot.
func (u *ChatUsecase) CloseSession(ctx context.Context, sessionID string) error {
	if _, err := u.repo.GetSessionByID(ctx, sessionID); err != nil {
		return err
	}
	return u.repo.CloseSession(ctx, sessionID)
}
