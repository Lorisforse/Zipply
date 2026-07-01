package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
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
// stato e livello di carica per il monitoraggio in tempo reale (OP.01).
func (h *OperatorHandler) ListVehicles(w http.ResponseWriter, r *http.Request) {
	vehicles, err := h.operator.ListVehicles(r.Context())
	if err != nil {
		log.Printf("[OPERATOR] list vehicles failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}
	writeJSON(w, http.StatusOK, vehicles)
}

// BlockVehicle gestisce PATCH /operator/vehicles/{id}/block (OP.11 / UC-32).
// Imposta il mezzo in stato 'bloccato' a prescindere dallo stato corrente.
func (h *OperatorHandler) BlockVehicle(w http.ResponseWriter, r *http.Request) {
	vehicleID := r.PathValue("id")
	if vehicleID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID mezzo mancante"})
		return
	}

	if err := h.operator.BlockVehicle(r.Context(), vehicleID); err != nil {
		if errors.Is(err, domain.ErrVehicleNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "mezzo non trovato"})
			return
		}
		log.Printf("[OPERATOR] block vehicle %s failed: %v", vehicleID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "bloccato"})
}

// UnblockVehicle gestisce PATCH /operator/vehicles/{id}/unblock (OP.11 / UC-32).
// Sblocca il mezzo; lo status finale e' 'disponibile' o 'manutenzione' a seconda
// delle segnalazioni di malfunzionamento ancora aperte.
func (h *OperatorHandler) UnblockVehicle(w http.ResponseWriter, r *http.Request) {
	vehicleID := r.PathValue("id")
	if vehicleID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID mezzo mancante"})
		return
	}

	if err := h.operator.UnblockVehicle(r.Context(), vehicleID); err != nil {
		if errors.Is(err, domain.ErrVehicleNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "mezzo non trovato o non bloccato"})
			return
		}
		log.Printf("[OPERATOR] unblock vehicle %s failed: %v", vehicleID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "sbloccato"})
}

// ListParkingZones gestisce GET /operator/parking-zones (OP.04 / UC-27).
func (h *OperatorHandler) ListParkingZones(w http.ResponseWriter, r *http.Request) {
	zones, err := h.operator.ListParkingZones(r.Context())
	if err != nil {
		log.Printf("[OPERATOR] list parking zones failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}
	writeJSON(w, http.StatusOK, zones)
}

type createParkingZoneRequest struct {
	Name        string  `json:"name"`
	Lat         float64 `json:"lat"`
	Lng         float64 `json:"lng"`
	RadiusM     float64 `json:"radius_meters"`
	BonusCredit float64 `json:"bonus_credit"`
}

// CreateParkingZone gestisce POST /operator/parking-zones (OP.04 / UC-27).
func (h *OperatorHandler) CreateParkingZone(w http.ResponseWriter, r *http.Request) {
	var req createParkingZoneRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body JSON malformato"})
		return
	}
	if req.Name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nome zona mancante"})
		return
	}
	if req.RadiusM <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "raggio deve essere maggiore di 0"})
		return
	}

	zone := &domain.ParkingZone{
		Name: req.Name,
		Center: domain.ParkingZoneCenter{
			Lat:    req.Lat,
			Lng:    req.Lng,
			Radius: req.RadiusM,
		},
		BonusCredit: req.BonusCredit,
		IsActive:    true,
	}

	if err := h.operator.CreateParkingZone(r.Context(), zone); err != nil {
		log.Printf("[OPERATOR] create parking zone failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusCreated, zone)
}

// DeleteParkingZone gestisce DELETE /operator/parking-zones/{id} (OP.04 / UC-27).
func (h *OperatorHandler) DeleteParkingZone(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID zona mancante"})
		return
	}

	if err := h.operator.DeleteParkingZone(r.Context(), id); err != nil {
		if errors.Is(err, domain.ErrParkingZoneNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "zona parcheggio non trovata"})
			return
		}
		log.Printf("[OPERATOR] delete parking zone %s failed: %v", id, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
