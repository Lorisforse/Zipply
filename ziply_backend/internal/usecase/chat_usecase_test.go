package usecase_test

import (
	"context"
	"errors"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockChatRepository implementa usecase.ChatRepository in memoria, protetta
// da mutex per riprodurre l'accesso concorrente di piu' utenti/operatori
// (OP.08 / test #850452).
type mockChatRepository struct {
	mu       sync.Mutex
	sessions map[string]*domain.ChatSession
	messages map[string][]domain.ChatMessage
	nextID   int
}

func newMockChatRepository() *mockChatRepository {
	return &mockChatRepository{
		sessions: map[string]*domain.ChatSession{},
		messages: map[string][]domain.ChatMessage{},
	}
}

func (m *mockChatRepository) genID(prefix string) string {
	m.nextID++
	return prefix + "-" + time.Now().Format("150405.000000000") + "-" + string(rune('a'+m.nextID%26))
}

func (m *mockChatRepository) GetOpenSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, s := range m.sessions {
		if s.UserID == userID && s.Status != domain.ChatStatusChiusa {
			return s, nil
		}
	}
	return nil, nil
}

func (m *mockChatRepository) CreateSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s := &domain.ChatSession{
		ID:        m.genID("sess"),
		UserID:    userID,
		Status:    domain.ChatStatusBot,
		CreatedAt: time.Now(),
	}
	m.sessions[s.ID] = s
	return s, nil
}

func (m *mockChatRepository) SetEscalated(ctx context.Context, sessionID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[sessionID]
	if !ok {
		return domain.ErrChatSessionNotFound
	}
	s.Status = domain.ChatStatusOperatore
	return nil
}

func (m *mockChatRepository) AddMessage(ctx context.Context, msg *domain.ChatMessage) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.sessions[msg.SessionID]; !ok {
		return domain.ErrChatSessionNotFound
	}
	msg.ID = m.genID("msg")
	msg.SentAt = time.Now()
	m.messages[msg.SessionID] = append(m.messages[msg.SessionID], *msg)
	return nil
}

func (m *mockChatRepository) GetMessages(ctx context.Context, sessionID string) ([]domain.ChatMessage, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]domain.ChatMessage, len(m.messages[sessionID]))
	copy(out, m.messages[sessionID])
	return out, nil
}

func (m *mockChatRepository) GetSession(ctx context.Context, sessionID, userID string) (*domain.ChatSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[sessionID]
	if !ok || s.UserID != userID {
		return nil, domain.ErrChatSessionNotFound
	}
	return s, nil
}

func (m *mockChatRepository) GetSessionByID(ctx context.Context, sessionID string) (*domain.ChatSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[sessionID]
	if !ok {
		return nil, domain.ErrChatSessionNotFound
	}
	return s, nil
}

func (m *mockChatRepository) ListForOperator(ctx context.Context) ([]domain.OperatorChatSession, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]domain.OperatorChatSession, 0)
	for _, s := range m.sessions {
		if s.Status != domain.ChatStatusOperatore {
			continue
		}
		msgs := m.messages[s.ID]
		var last domain.ChatMessage
		if len(msgs) > 0 {
			last = msgs[len(msgs)-1]
		}
		out = append(out, domain.OperatorChatSession{
			ID:              s.ID,
			UserID:          s.UserID,
			Status:          s.Status,
			CreatedAt:       s.CreatedAt,
			LastMessage:     last.Text,
			LastMessageAt:   last.SentAt,
			LastMessageFrom: last.Sender,
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].LastMessageAt.After(out[j].LastMessageAt) })
	return out, nil
}

func (m *mockChatRepository) CloseSession(ctx context.Context, sessionID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[sessionID]
	if !ok {
		return domain.ErrChatSessionNotFound
	}
	s.Status = domain.ChatStatusChiusa
	return nil
}

// ── GetOrCreateSession ───────────────────────────────────────────────────────

func TestGetOrCreateSession_CreatesNewWhenNoneOpen(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	session, err := uc.GetOrCreateSession(context.Background(), "user1")
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if session.UserID != "user1" || session.Status != domain.ChatStatusBot {
		t.Fatalf("sessione inattesa: %+v", session)
	}
}

func TestGetOrCreateSession_ReusesOpenSession(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	first, _ := uc.GetOrCreateSession(context.Background(), "user1")
	second, err := uc.GetOrCreateSession(context.Background(), "user1")
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if second.ID != first.ID {
		t.Fatalf("attesa riutilizzo sessione %q, ottenuta %q", first.ID, second.ID)
	}
}

// ── SendMessage (bot + escalation) ──────────────────────────────────────────

func TestSendMessage_BotRepliesWithoutEscalation(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)
	session, _ := uc.GetOrCreateSession(context.Background(), "user1")

	msgs, err := uc.SendMessage(context.Background(), session.ID, "user1", "quanto costa la tariffa?")
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if len(msgs) != 2 || msgs[0].Sender != "utente" || msgs[1].Sender != "bot" {
		t.Fatalf("messaggi inattesi: %+v", msgs)
	}

	updated, _ := repo.GetSessionByID(context.Background(), session.ID)
	if updated.Status != domain.ChatStatusBot {
		t.Fatalf("non doveva scalare a operatore, stato: %q", updated.Status)
	}
}

func TestSendMessage_EscalatesWhenBotDoesNotUnderstand(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)
	session, _ := uc.GetOrCreateSession(context.Background(), "user1")

	if _, err := uc.SendMessage(context.Background(), session.ID, "user1", "voglio parlare con un operatore"); err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}

	updated, _ := repo.GetSessionByID(context.Background(), session.ID)
	if updated.Status != domain.ChatStatusOperatore {
		t.Fatalf("attesa escalation a operatore, stato: %q", updated.Status)
	}
}

func TestSendMessage_SessionNotFound(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	if _, err := uc.SendMessage(context.Background(), "sconosciuta", "user1", "ciao"); !errors.Is(err, domain.ErrChatSessionNotFound) {
		t.Fatalf("attesto ErrChatSessionNotFound, ottenuto %v", err)
	}
}

// ── Console operatore (OP.08) ───────────────────────────────────────────────

func TestListOperatorSessions_OnlyEscalated(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	botSession, _ := uc.GetOrCreateSession(context.Background(), "user1")
	uc.SendMessage(context.Background(), botSession.ID, "user1", "quanto costa?")

	escalated, _ := uc.GetOrCreateSession(context.Background(), "user2")
	uc.SendMessage(context.Background(), escalated.ID, "user2", "voglio un operatore")

	sessions, err := uc.ListOperatorSessions(context.Background())
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if len(sessions) != 1 || sessions[0].ID != escalated.ID {
		t.Fatalf("attesa solo la sessione scalata %q, ottenuto %+v", escalated.ID, sessions)
	}
}

func TestSendOperatorMessage_OK(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)
	session, _ := uc.GetOrCreateSession(context.Background(), "user1")
	uc.SendMessage(context.Background(), session.ID, "user1", "voglio un operatore")

	msg, err := uc.SendOperatorMessage(context.Background(), session.ID, "Ciao, come posso aiutarti?")
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if msg.Sender != "operatore" || msg.Text != "Ciao, come posso aiutarti?" {
		t.Fatalf("messaggio inatteso: %+v", msg)
	}
}

func TestSendOperatorMessage_SessionNotFound(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	if _, err := uc.SendOperatorMessage(context.Background(), "sconosciuta", "ciao"); !errors.Is(err, domain.ErrChatSessionNotFound) {
		t.Fatalf("attesto ErrChatSessionNotFound, ottenuto %v", err)
	}
}

func TestSendOperatorMessage_ClosedSession(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)
	session, _ := uc.GetOrCreateSession(context.Background(), "user1")
	uc.SendMessage(context.Background(), session.ID, "user1", "voglio un operatore")
	if err := uc.CloseSession(context.Background(), session.ID); err != nil {
		t.Fatalf("errore chiusura inatteso: %v", err)
	}

	if _, err := uc.SendOperatorMessage(context.Background(), session.ID, "ciao"); !errors.Is(err, domain.ErrChatSessionClosed) {
		t.Fatalf("attesto ErrChatSessionClosed, ottenuto %v", err)
	}
}

func TestCloseSession_NotFound(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	if err := uc.CloseSession(context.Background(), "sconosciuta"); !errors.Is(err, domain.ErrChatSessionNotFound) {
		t.Fatalf("attesto ErrChatSessionNotFound, ottenuto %v", err)
	}
}

func TestGetOperatorMessages_ReturnsHistoryRegardlessOfUser(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)
	session, _ := uc.GetOrCreateSession(context.Background(), "user1")
	uc.SendMessage(context.Background(), session.ID, "user1", "voglio un operatore")
	uc.SendOperatorMessage(context.Background(), session.ID, "Dimmi pure")

	msgs, gotSession, err := uc.GetOperatorMessages(context.Background(), session.ID)
	if err != nil {
		t.Fatalf("errore inatteso: %v", err)
	}
	if gotSession.ID != session.ID {
		t.Fatalf("sessione inattesa: %+v", gotSession)
	}
	if len(msgs) != 3 { // utente + bot + operatore
		t.Fatalf("attesi 3 messaggi nello storico, ottenuti %d", len(msgs))
	}
}

// ── Concorrenza: invio contemporaneo da piu' utenti (#850452) ──────────────

func TestSendMessage_ConcurrentFromMultipleUsers(t *testing.T) {
	repo := newMockChatRepository()
	uc := usecase.NewChatUsecase(repo)

	const users = 20
	sessionIDs := make([]string, users)
	for i := 0; i < users; i++ {
		s, err := uc.GetOrCreateSession(context.Background(), sessionUserID(i))
		if err != nil {
			t.Fatalf("errore creazione sessione %d: %v", i, err)
		}
		sessionIDs[i] = s.ID
	}

	var wg sync.WaitGroup
	for i := 0; i < users; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, err := uc.SendMessage(context.Background(), sessionIDs[i], sessionUserID(i), "ho un problema con la prenotazione")
			if err != nil {
				t.Errorf("invio concorrente fallito per utente %d: %v", i, err)
			}
		}(i)
	}
	wg.Wait()

	for i := 0; i < users; i++ {
		msgs, err := repo.GetMessages(context.Background(), sessionIDs[i])
		if err != nil {
			t.Fatalf("errore lettura storico: %v", err)
		}
		if len(msgs) != 2 {
			t.Fatalf("attesi 2 messaggi (utente+bot) per la sessione %d, ottenuti %d", i, len(msgs))
		}
	}
}

func sessionUserID(i int) string {
	return "user-" + string(rune('A'+i%26)) + "-" + string(rune('0'+i/26))
}
