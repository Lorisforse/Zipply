package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// RideHandler handles the /rides HTTP endpoints.
type RideHandler struct {
	rides *usecase.RideUsecase
}

// NewRideHandler creates a RideHandler backed by the given usecase.
func NewRideHandler(rides *usecase.RideUsecase) *RideHandler {
	return &RideHandler{rides: rides}
}

// unlockRideRequest mirrors the JSON body of POST /rides/unlock. Per unlock_method,
// either vehicle_id ('proximity') or qr_code ('qr') is expected.
type unlockRideRequest struct {
	VehicleID    string `json:"vehicle_id"`
	QRCode       string `json:"qr_code"`
	UnlockMethod string `json:"unlock_method"`
}

// rideResponse is the JSON shape of a started ride.
type rideResponse struct {
	RideID    string `json:"ride_id"`
	VehicleID string `json:"vehicle_id"`
	StartedAt string `json:"started_at"`
}

// Unlock handles POST /rides/unlock, starting a ride on the vehicle the
// authenticated user has reserved. The vehicle is identified by vehicle_id
// (proximity) or qr_code (QR scan), selected by unlock_method.
func (h *RideHandler) Unlock(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req unlockRideRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	// The unlock method selects which identifier is required.
	var vehicleID, qrCode string
	switch req.UnlockMethod {
	case domain.UnlockMethodProximity:
		if req.VehicleID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
			return
		}
		vehicleID = req.VehicleID
	case domain.UnlockMethodQR:
		if req.QRCode == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
			return
		}
		qrCode = req.QRCode
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	ride, err := h.rides.Unlock(r.Context(), userID, vehicleID, qrCode)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrVehicleNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "veicolo non trovato"})
		case errors.Is(err, domain.ErrVehicleNotAvailable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "mezzo non disponibile"})
		default:
			log.Printf("[RIDES] unlock failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusCreated, rideResponse{
		RideID:    ride.ID,
		VehicleID: ride.VehicleID,
		StartedAt: ride.StartedAt.UTC().Format(time.RFC3339),
	})
}

// End handles POST /rides/{id}/end, chiudendo la corsa attiva dell'utente
// autenticato e rimettendo il mezzo disponibile.
func (h *RideHandler) End(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	rideID := r.PathValue("id")
	if rideID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	summary, err := h.rides.End(r.Context(), userID, rideID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata o già conclusa"})
		default:
			log.Printf("[RIDES] end failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":           "completata",
		"duration_minutes": summary.DurationMinutes,
		"total_cost":       summary.TotalCost,
		"co2_saved":        summary.Co2SavedGrams,
		"applied_discount": summary.AppliedDiscount,
	})
}
