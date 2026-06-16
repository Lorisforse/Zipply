package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// secondsPerMinute converte i secondi di durata nei minuti esposti dall'API.
const secondsPerMinute = 60

// metersPerKm converte i metri di distanza nei chilometri esposti dall'API.
const metersPerKm = 1000

// RouteHandler handles the /routes HTTP endpoint (UT.07).
type RouteHandler struct {
	routes *usecase.RouteUsecase
}

// NewRouteHandler creates a RouteHandler backed by the given usecase.
func NewRouteHandler(routes *usecase.RouteUsecase) *RouteHandler {
	return &RouteHandler{routes: routes}
}

// routeRequest mirrors the JSON body of POST /routes.
type routeRequest struct {
	VehicleID string  `json:"vehicle_id"`
	DestLat   float64 `json:"dest_lat"`
	DestLng   float64 `json:"dest_lng"`
}

// routeResponse is the JSON shape of a computed route.
type routeResponse struct {
	Geometry        json.RawMessage `json:"geometry"`
	DistanceKm      float64         `json:"distance_km"`
	DurationMinutes float64         `json:"duration_minutes"`
	Fallback        bool            `json:"fallback"`
}

// Compute handles POST /routes: percorso più rapido dal mezzo selezionato alla
// destinazione, per tipologia ed evitando le zone vietate.
func (h *RouteHandler) Compute(w http.ResponseWriter, r *http.Request) {
	var req routeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VehicleID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	res, err := h.routes.Compute(r.Context(), req.VehicleID, req.DestLat, req.DestLng)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrVehicleNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "veicolo non trovato"})
		default:
			log.Printf("[ROUTES] compute failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, routeResponse{
		Geometry:        res.Geometry,
		DistanceKm:      res.DistanceMeters / metersPerKm,
		DurationMinutes: res.DurationSeconds / secondsPerMinute,
		Fallback:        res.Fallback,
	})
}
