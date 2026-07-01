package handler

import (
	"log"
	"net/http"
	"time"

	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// AvailabilityAlertHandler gestisce l'endpoint di consultazione avvisi
// (OP.02 / OP.07).
type AvailabilityAlertHandler struct {
	alerts *usecase.AvailabilityAlertUsecase
}

// NewAvailabilityAlertHandler crea un AvailabilityAlertHandler sul usecase dato.
func NewAvailabilityAlertHandler(alerts *usecase.AvailabilityAlertUsecase) *AvailabilityAlertHandler {
	return &AvailabilityAlertHandler{alerts: alerts}
}

// alertResponse e' la forma JSON di un singolo avviso.
type alertResponse struct {
	ID             string  `json:"id"`
	Type           string  `json:"type"`
	ServiceAreaID  *string `json:"service_area_id,omitempty"`
	VehicleID      *string `json:"vehicle_id,omitempty"`
	AvailableCount *int    `json:"available_count,omitempty"`
	Message        string  `json:"message"`
	CreatedAt      string  `json:"created_at"`
}

// List gestisce GET /operator/availability-alerts (OP.02 / OP.07 / UC-25):
// elenca gli avvisi generati dal worker di rilevamento anomalie, piu' recenti
// prima. E' un log di sola lettura, nessuna azione operatore prevista.
func (h *AvailabilityAlertHandler) List(w http.ResponseWriter, r *http.Request) {
	alerts, err := h.alerts.List(r.Context())
	if err != nil {
		log.Printf("[ALERTS] list failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	resp := make([]alertResponse, 0, len(alerts))
	for _, a := range alerts {
		resp = append(resp, alertResponse{
			ID:             a.ID,
			Type:           a.Type,
			ServiceAreaID:  a.ServiceAreaID,
			VehicleID:      a.VehicleID,
			AvailableCount: a.AvailableCount,
			Message:        a.Message,
			CreatedAt:      a.CreatedAt.UTC().Format(time.RFC3339),
		})
	}
	writeJSON(w, http.StatusOK, resp)
}
