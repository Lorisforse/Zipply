package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// minutesPerHour converts the per-minute fare into the hourly rate exposed by the API.
const minutesPerHour = 60

// VehicleHandler handles the /vehicles HTTP endpoints.
type VehicleHandler struct {
	vehicles *usecase.VehicleUsecase
}

// NewVehicleHandler creates a VehicleHandler backed by the given usecase.
func NewVehicleHandler(vehicles *usecase.VehicleUsecase) *VehicleHandler {
	return &VehicleHandler{vehicles: vehicles}
}

// vehicleResponse is the JSON shape of a single available vehicle.
type vehicleResponse struct {
	ID           string  `json:"id"`
	Type         string  `json:"type"`
	QrCode       string  `json:"qr_code"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	BatteryLevel int     `json:"battery_level"`
	HourlyRate   float64 `json:"hourly_rate"`
}

// listVehiclesResponse wraps the available vehicles list.
type listVehiclesResponse struct {
	Vehicles []vehicleResponse `json:"vehicles"`
}

// List handles GET /vehicles, returning the available vehicles optionally filtered by area.
func (h *VehicleHandler) List(w http.ResponseWriter, r *http.Request) {
	filter := parseGeoFilter(r)

	vehicles, err := h.vehicles.ListAvailable(r.Context(), filter)
	if err != nil {
		log.Printf("[VEHICLES] list failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	resp := listVehiclesResponse{Vehicles: make([]vehicleResponse, 0, len(vehicles))}
	for _, v := range vehicles {
		resp.Vehicles = append(resp.Vehicles, vehicleResponse{
			ID:           v.ID,
			Type:         v.Type,
			QrCode:       v.QrCode,
			Latitude:     v.Latitude,
			Longitude:    v.Longitude,
			BatteryLevel: v.BatteryLevel,
			HourlyRate:   v.TariffaAlMinuto * minutesPerHour,
		})
	}

	writeJSON(w, http.StatusOK, resp)
}

type reportPositionRequest struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// ReportPosition gestisce PATCH /operator/vehicles/{id}/report-position
// (OP.02 / OP.07): simula la telemetria GPS di un mezzo (non esiste hardware
// IoT reale). Se il mezzo non e' in uso e lo spostamento supera la soglia
// configurata, genera un avviso di movimento illecito.
func (h *VehicleHandler) ReportPosition(w http.ResponseWriter, r *http.Request) {
	vehicleID := r.PathValue("id")
	if vehicleID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID mezzo mancante"})
		return
	}

	var req reportPositionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body JSON malformato"})
		return
	}

	alertTriggered, err := h.vehicles.ReportPosition(r.Context(), vehicleID, req.Latitude, req.Longitude)
	if err != nil {
		if errors.Is(err, domain.ErrVehicleNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "mezzo non trovato"})
			return
		}
		log.Printf("[VEHICLES] report position for %s failed: %v", vehicleID, err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"alert_triggered": alertTriggered})
}

// parseGeoFilter builds a GeoFilter only when lat, lng and radius are all present and parsable.
func parseGeoFilter(r *http.Request) *domain.GeoFilter {
	q := r.URL.Query()
	latStr, lngStr, radiusStr := q.Get("lat"), q.Get("lng"), q.Get("radius")
	if latStr == "" || lngStr == "" || radiusStr == "" {
		return nil
	}
	lat, errLat := strconv.ParseFloat(latStr, 64)
	lng, errLng := strconv.ParseFloat(lngStr, 64)
	radius, errRadius := strconv.ParseFloat(radiusStr, 64)
	if errLat != nil || errLng != nil || errRadius != nil {
		return nil
	}
	return &domain.GeoFilter{Lat: lat, Lng: lng, Radius: radius}
}
