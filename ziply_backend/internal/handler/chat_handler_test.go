package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockChatRepo implementa usecase.ChatRepository per i test HTTP della
// console operatore (OP.08 / #850450).
type mockChatRepo struct {
	sessions       map[string]*domain.ChatSession
	operatorList   []domain.OperatorChatSession
	messages       map[string][]domain.ChatMessage
	closeErr       error
	closedID       string
	sentOperatorID string
}

func (m *mockChatRepo) GetOpenSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	return nil, nil
}

func (m *mockChatRepo) CreateSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	return nil, nil
}

func (m *mockChatRepo) SetEscalated(ctx context.Context, sessionID string) error { return nil }

func (m *mockChatRepo) AddMessage(ctx context.Context, msg *domain.ChatMessage) error {
	msg.ID = "msg-test-id"
	msg.SentAt = time.Now()
	m.messages[msg.SessionID] = append(m.messages[msg.SessionID], *msg)
	m.sentOperatorID = msg.SessionID
	return nil
}

func (m *mockChatRepo) GetMessages(ctx context.Context, sessionID string) ([]domain.ChatMessage, error) {
	return m.messages[sessionID], nil
}

func (m *mockChatRepo) GetSession(ctx context.Context, sessionID, userID string) (*domain.ChatSession, error) {
	return nil, domain.ErrChatSessionNotFound
}

func (m *mockChatRepo) GetSessionByID(ctx context.Context, sessionID string) (*domain.ChatSession, error) {
	s, ok := m.sessions[sessionID]
	if !ok {
		return nil, domain.ErrChatSessionNotFound
	}
	return s, nil
}

func (m *mockChatRepo) ListForOperator(ctx context.Context) ([]domain.OperatorChatSession, error) {
	return m.operatorList, nil
}

func (m *mockChatRepo) CloseSession(ctx context.Context, sessionID string) error {
	if m.closeErr != nil {
		return m.closeErr
	}
	m.closedID = sessionID
	return nil
}

func newChatMux(repo *mockChatRepo) *http.ServeMux {
	uc := usecase.NewChatUsecase(repo)
	h := handler.NewChatHandler(uc)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /operator/chat/sessions", h.ListOperatorSessions)
	mux.HandleFunc("GET /operator/chat/sessions/{id}/messages", h.GetOperatorMessages)
	mux.HandleFunc("POST /operator/chat/sessions/{id}/messages", h.SendOperatorMessage)
	mux.HandleFunc("PATCH /operator/chat/sessions/{id}/close", h.CloseSession)
	return mux
}

func TestListOperatorSessions_OK(t *testing.T) {
	repo := &mockChatRepo{
		operatorList: []domain.OperatorChatSession{
			{ID: "sess1", UserName: "Mario Rossi", Status: domain.ChatStatusOperatore},
		},
	}
	mux := newChatMux(repo)

	req := httptest.NewRequest("GET", "/operator/chat/sessions", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	var got []domain.OperatorChatSession
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("risposta non decodificabile: %v", err)
	}
	if len(got) != 1 || got[0].UserName != "Mario Rossi" {
		t.Fatalf("attesa 1 sessione di Mario Rossi, got %+v", got)
	}
}

func TestSendOperatorMessage_OK(t *testing.T) {
	repo := &mockChatRepo{
		sessions: map[string]*domain.ChatSession{
			"sess1": {ID: "sess1", Status: domain.ChatStatusOperatore},
		},
		messages: map[string][]domain.ChatMessage{},
	}
	mux := newChatMux(repo)

	body := strings.NewReader(`{"body":"Come posso aiutarti?"}`)
	req := httptest.NewRequest("POST", "/operator/chat/sessions/sess1/messages", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d: %s", rr.Code, rr.Body.String())
	}
	if repo.sentOperatorID != "sess1" {
		t.Errorf("messaggio non propagato al repository per la sessione sess1")
	}
}

func TestSendOperatorMessage_ClosedSessionReturnsConflict(t *testing.T) {
	repo := &mockChatRepo{
		sessions: map[string]*domain.ChatSession{
			"sess1": {ID: "sess1", Status: domain.ChatStatusChiusa},
		},
		messages: map[string][]domain.ChatMessage{},
	}
	mux := newChatMux(repo)

	body := strings.NewReader(`{"body":"ciao"}`)
	req := httptest.NewRequest("POST", "/operator/chat/sessions/sess1/messages", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusConflict {
		t.Fatalf("expected status 409, got %d", rr.Code)
	}
}

func TestSendOperatorMessage_SessionNotFound(t *testing.T) {
	repo := &mockChatRepo{sessions: map[string]*domain.ChatSession{}, messages: map[string][]domain.ChatMessage{}}
	mux := newChatMux(repo)

	body := strings.NewReader(`{"body":"ciao"}`)
	req := httptest.NewRequest("POST", "/operator/chat/sessions/inesistente/messages", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rr.Code)
	}
}

func TestGetOperatorMessages_OK(t *testing.T) {
	repo := &mockChatRepo{
		sessions: map[string]*domain.ChatSession{
			"sess1": {ID: "sess1", Status: domain.ChatStatusOperatore},
		},
		messages: map[string][]domain.ChatMessage{
			"sess1": {{ID: "m1", SessionID: "sess1", Sender: "utente", Text: "aiuto"}},
		},
	}
	mux := newChatMux(repo)

	req := httptest.NewRequest("GET", "/operator/chat/sessions/sess1/messages", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	var got map[string]any
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("risposta non decodificabile: %v", err)
	}
	msgs, _ := got["messages"].([]any)
	if len(msgs) != 1 {
		t.Fatalf("attesi 1 messaggio, got %+v", got)
	}
}

func TestCloseSession_OK(t *testing.T) {
	repo := &mockChatRepo{
		sessions: map[string]*domain.ChatSession{
			"sess1": {ID: "sess1", Status: domain.ChatStatusOperatore},
		},
	}
	mux := newChatMux(repo)

	req := httptest.NewRequest("PATCH", "/operator/chat/sessions/sess1/close", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	if repo.closedID != "sess1" {
		t.Errorf("chiusura non propagata al repository per sess1")
	}
}

func TestCloseSession_NotFound(t *testing.T) {
	repo := &mockChatRepo{sessions: map[string]*domain.ChatSession{}}
	mux := newChatMux(repo)

	req := httptest.NewRequest("PATCH", "/operator/chat/sessions/inesistente/close", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rr.Code)
	}
}
