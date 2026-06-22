package handler

import (
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// OperatorHandler gestisce gli endpoint HTTP dell'area riservata operatore.
type OperatorHandler struct {
	operator *usecase.OperatorUsecase
}

// NewOperatorHandler crea un OperatorHandler sul usecase dato.
func NewOperatorHandler(operator *usecase.OperatorUsecase) *OperatorHandler {
	return &OperatorHandler{operator: operator}
}

// ListVehicles gestisce GET /operator/vehicles, restituendo l'intera flotta con
// stato e livello di carica per il monitoraggio in tempo reale (OP.01). La
// risposta è un array JSON di mezzi; l'accesso è riservato ai ruoli
// 'operatore' e 'amministrazione' (vedi RequireRole nel router).
func (h *OperatorHandler) ListVehicles(w http.ResponseWriter, r *http.Request) {
	vehicles, err := h.operator.ListVehicles(r.Context())
	if err != nil {
		log.Printf("[OPERATOR] list vehicles failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}
	writeJSON(w, http.StatusOK, vehicles)
}
