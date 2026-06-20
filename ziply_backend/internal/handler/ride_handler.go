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

// Pause handles POST /rides/{id}/pause, pausing the active ride of the authenticated user.
func (h *RideHandler) Pause(w http.ResponseWriter, r *http.Request) {
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

	err := h.rides.Pause(r.Context(), userID, rideID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata o non attiva"})
		default:
			log.Printf("[RIDES] pause failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "paused"})
}

// Resume handles POST /rides/{id}/resume, resuming the paused ride of the authenticated user.
func (h *RideHandler) Resume(w http.ResponseWriter, r *http.Request) {
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

	err := h.rides.Resume(r.Context(), userID, rideID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata o non in pausa"})
		default:
			log.Printf("[RIDES] resume failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "attiva"})
}

// groupUnlockResponse is the JSON shape of a started group ride (UT.16).
type groupUnlockResponse struct {
	GroupID string         `json:"group_id"`
	Rides   []rideResponse `json:"rides"`
}

// UnlockGroup handles POST /rides/group/{id}/unlock (UT.16), avviando tutte le
// corse della prenotazione multipla identificata dal group_id.
func (h *RideHandler) UnlockGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	groupID := r.PathValue("id")
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	rides, err := h.rides.UnlockGroup(r.Context(), userID, groupID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "nessuna prenotazione di gruppo da sbloccare"})
		default:
			log.Printf("[RIDES] unlock group failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	items := make([]rideResponse, 0, len(rides))
	for _, ride := range rides {
		items = append(items, rideResponse{
			RideID:    ride.ID,
			VehicleID: ride.VehicleID,
			StartedAt: ride.StartedAt.UTC().Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusCreated, groupUnlockResponse{GroupID: groupID, Rides: items})
}

// EndGroup handles POST /rides/group/{id}/end (UT.16), chiudendo tutte le corse
// del gruppo e restituendo il riepilogo aggregato.
func (h *RideHandler) EndGroup(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	groupID := r.PathValue("id")
	if groupID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	summary, err := h.rides.EndGroup(r.Context(), userID, groupID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa di gruppo non trovata o già conclusa"})
		default:
			log.Printf("[RIDES] end group failed: %v", err)
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
