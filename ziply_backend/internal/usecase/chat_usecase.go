package usecase

import (
	"context"
	"strings"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/repository"
)

// ChatUsecase gestisce la logica di sessione, risposta bot ed escalation.
type ChatUsecase struct {
	repo *repository.ChatRepository
}

// NewChatUsecase crea un nuovo ChatUsecase.
func NewChatUsecase(repo *repository.ChatRepository) *ChatUsecase {
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

// SendMessage salva il messaggio dell'utente, genera la risposta del bot
// ed eventualmente scala la sessione a operatore.
func (u *ChatUsecase) SendMessage(ctx context.Context, sessionID, userID, body string) ([]domain.ChatMessage, error) {
	if _, err := u.repo.GetSession(ctx, sessionID, userID); err != nil {
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
