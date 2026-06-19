package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// DiscountHandler gestisce gli endpoint /discount-codes.
type DiscountHandler struct {
	discounts *usecase.DiscountUsecase
}

// NewDiscountHandler crea un DiscountHandler sul usecase dato.
func NewDiscountHandler(discounts *usecase.DiscountUsecase) *DiscountHandler {
	return &DiscountHandler{discounts: discounts}
}

// validateRequest rispecchia il body JSON di POST /discount-codes/validate.
type validateRequest struct {
	Code string `json:"code"`
}

// Validate gestisce POST /discount-codes/validate: verifica il codice sconto
// inserito in fase di conferma prenotazione e ne restituisce la percentuale.
// Risponde 200 con {valid:true, code, percentage} se il codice è utilizzabile,
// 404 se inesistente e 422 se esiste ma non è valido (scaduto/esaurito).
func (h *DiscountHandler) Validate(w http.ResponseWriter, r *http.Request) {
	var req validateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Code == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	discount, err := h.discounts.Validate(r.Context(), req.Code)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrDiscountNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "Codice scaduto o inesistente"})
		case errors.Is(err, domain.ErrDiscountNotValid):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "Codice scaduto o inesistente"})
		default:
			log.Printf("[DISCOUNTS] validate failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"valid":      true,
		"code":       discount.Code,
		"percentage": discount.Percentage,
	})
}
