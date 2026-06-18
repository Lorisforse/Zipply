package handler

import (
	"encoding/json"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// SuggestionHandler handles the /suggest-vehicle HTTP endpoint (UT.08).
type SuggestionHandler struct {
	suggestions *usecase.SuggestionUsecase
}

// NewSuggestionHandler creates a SuggestionHandler backed by the given usecase.
func NewSuggestionHandler(s *usecase.SuggestionUsecase) *SuggestionHandler {
	return &SuggestionHandler{suggestions: s}
}

// suggestRequest mirrors the JSON body of POST /suggest-vehicle.
type suggestRequest struct {
	FromLat float64 `json:"from_lat"`
	FromLng float64 `json:"from_lng"`
	DestLat float64 `json:"dest_lat"`
	DestLng float64 `json:"dest_lng"`
}

// suggestResponse is the JSON shape of a vehicle suggestion.
type suggestResponse struct {
	SuggestedType string  `json:"suggested_type"`
	DistanceKm    float64 `json:"distance_km"`
}

// Suggest handles POST /suggest-vehicle: consiglia la tipologia di mezzo più
// adatta al tragitto verso la destinazione inserita (UT.08).
func (h *SuggestionHandler) Suggest(w http.ResponseWriter, r *http.Request) {
	var req suggestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	s := h.suggestions.Suggest(req.FromLat, req.FromLng, req.DestLat, req.DestLng)
	writeJSON(w, http.StatusOK, suggestResponse{
		SuggestedType: s.Type,
		DistanceKm:    s.DistanceMeters / metersPerKm,
	})
}
