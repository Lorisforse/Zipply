package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// ChatHandler gestisce le richieste HTTP per la chat di assistenza.
type ChatHandler struct {
	usecase *usecase.ChatUsecase
}

// NewChatHandler crea un nuovo ChatHandler.
func NewChatHandler(usecase *usecase.ChatUsecase) *ChatHandler {
	return &ChatHandler{usecase: usecase}
}

// GetOrCreateSession gestisce POST /chat/sessions
func (h *ChatHandler) GetOrCreateSession(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	session, err := h.usecase.GetOrCreateSession(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, session)
}

// SendMessage gestisce POST /chat/sessions/{id}/messages
func (h *ChatHandler) SendMessage(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	sessionID := r.PathValue("id")
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID sessione mancante"})
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Body == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "messaggio mancante"})
		return
	}

	msgs, err := h.usecase.SendMessage(r.Context(), sessionID, userID, req.Body)
	if err != nil {
		if errors.Is(err, domain.ErrChatSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "sessione non trovata"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, msgs)
}

// GetMessages gestisce GET /chat/sessions/{id}/messages
func (h *ChatHandler) GetMessages(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	sessionID := r.PathValue("id")
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID sessione mancante"})
		return
	}

	msgs, session, err := h.usecase.GetMessages(r.Context(), sessionID, userID)
	if err != nil {
		if errors.Is(err, domain.ErrChatSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "sessione non trovata"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"session":  session,
		"messages": msgs,
	})
}

// ListOperatorSessions gestisce GET /operator/chat/sessions: elenco delle chat
// scalate a operatore per la console di supporto (OP.08).
func (h *ChatHandler) ListOperatorSessions(w http.ResponseWriter, r *http.Request) {
	sessions, err := h.usecase.ListOperatorSessions(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}
	writeJSON(w, http.StatusOK, sessions)
}

// GetOperatorMessages gestisce GET /operator/chat/sessions/{id}/messages
// (OP.08): storico completo di una sessione, senza vincolo utente.
func (h *ChatHandler) GetOperatorMessages(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID sessione mancante"})
		return
	}

	msgs, session, err := h.usecase.GetOperatorMessages(r.Context(), sessionID)
	if err != nil {
		if errors.Is(err, domain.ErrChatSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "sessione non trovata"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"session":  session,
		"messages": msgs,
	})
}

// SendOperatorMessage gestisce POST /operator/chat/sessions/{id}/messages
// (OP.08): l'operatore risponde in una sessione scalata.
func (h *ChatHandler) SendOperatorMessage(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID sessione mancante"})
		return
	}

	var req struct {
		Body string `json:"body"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Body == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "messaggio mancante"})
		return
	}

	msg, err := h.usecase.SendOperatorMessage(r.Context(), sessionID, req.Body)
	if err != nil {
		if errors.Is(err, domain.ErrChatSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "sessione non trovata"})
			return
		}
		if errors.Is(err, domain.ErrChatSessionClosed) {
			writeJSON(w, http.StatusConflict, map[string]string{"error": "sessione chiusa"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusCreated, msg)
}

// CloseSession gestisce PATCH /operator/chat/sessions/{id}/close (OP.08):
// l'operatore chiude la sessione di supporto.
func (h *ChatHandler) CloseSession(w http.ResponseWriter, r *http.Request) {
	sessionID := r.PathValue("id")
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID sessione mancante"})
		return
	}

	if err := h.usecase.CloseSession(r.Context(), sessionID); err != nil {
		if errors.Is(err, domain.ErrChatSessionNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "sessione non trovata"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "chiusa"})
}
