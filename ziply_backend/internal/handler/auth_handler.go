// Package handler exposes the HTTP layer of the authentication API.
package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// AuthHandler handles the /auth/* HTTP endpoints.
type AuthHandler struct {
	auth *usecase.AuthUsecase
}

// NewAuthHandler creates an AuthHandler backed by the given usecase.
func NewAuthHandler(auth *usecase.AuthUsecase) *AuthHandler {
	return &AuthHandler{auth: auth}
}

// registerRequest mirrors the JSON body of POST /auth/register.
type registerRequest struct {
	Nome     string `json:"nome"`
	Cognome  string `json:"cognome"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

// loginRequest mirrors the JSON body of POST /auth/login.
type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// authResponse is the success payload shared by register and login.
type authResponse struct {
	Token string       `json:"token"`
	User  *domain.User `json:"user"`
}

// Register handles POST /auth/register.
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error":   "Dati non validi",
			"details": "body JSON malformato",
		})
		return
	}

	user, token, err := h.auth.Register(r.Context(), req.Nome, req.Cognome, req.Email, req.Password)
	if err != nil {
		var vErr *usecase.ValidationError
		switch {
		case errors.As(err, &vErr):
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":   "Dati non validi",
				"details": vErr.Details,
			})
		case errors.Is(err, domain.ErrEmailAlreadyExists):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "Email già in uso"})
		default:
			log.Printf("[AUTH] register failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusCreated, authResponse{Token: token, User: user})
}

// Login handles POST /auth/login.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	user, token, err := h.auth.Login(r.Context(), req.Email, req.Password)
	if err != nil {
		var vErr *usecase.ValidationError
		switch {
		case errors.As(err, &vErr):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		case errors.Is(err, domain.ErrInvalidCredentials):
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Email o password non corretti"})
		default:
			log.Printf("[AUTH] login failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, authResponse{Token: token, User: user})
}

// writeJSON serializes v as a JSON response with the given status code.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("[AUTH] writing response failed: %v", err)
	}
}
