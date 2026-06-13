package handler

import (
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// ForbiddenZoneHandler handles the /forbidden-zones HTTP endpoints.
type ForbiddenZoneHandler struct {
	zones *usecase.ForbiddenZoneUsecase
}

// NewForbiddenZoneHandler creates a ForbiddenZoneHandler backed by the given usecase.
func NewForbiddenZoneHandler(zones *usecase.ForbiddenZoneUsecase) *ForbiddenZoneHandler {
	return &ForbiddenZoneHandler{zones: zones}
}

// forbiddenZoneResponse is the JSON shape of a single forbidden zone.
type forbiddenZoneResponse struct {
	ID       string         `json:"id"`
	Nome     string         `json:"nome"`
	Polygon  domain.Polygon `json:"polygon"`
	IsActive bool           `json:"is_active"`
}

// List handles GET /forbidden-zones, returning all the active forbidden zones.
func (h *ForbiddenZoneHandler) List(w http.ResponseWriter, r *http.Request) {
	zones, err := h.zones.ListActive(r.Context())
	if err != nil {
		log.Printf("[FORBIDDEN_ZONES] list failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	resp := make([]forbiddenZoneResponse, 0, len(zones))
	for _, z := range zones {
		resp = append(resp, forbiddenZoneResponse{
			ID:       z.ID,
			Nome:     z.Nome,
			Polygon:  z.Polygon,
			IsActive: z.IsActive,
		})
	}

	writeJSON(w, http.StatusOK, resp)
}
