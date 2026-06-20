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

// BookingHandler handles the /bookings HTTP endpoints.
type BookingHandler struct {
	bookings *usecase.BookingUsecase
}

// NewBookingHandler creates a BookingHandler backed by the given usecase.
func NewBookingHandler(bookings *usecase.BookingUsecase) *BookingHandler {
	return &BookingHandler{bookings: bookings}
}

// createBookingRequest mirrors the JSON body of POST /bookings.
// discount_code è opzionale (UT.09): se presente lo sconto viene collegato alla
// prenotazione e applicato al costo a fine corsa.
type createBookingRequest struct {
	VehicleID    string `json:"vehicle_id"`
	DiscountCode string `json:"discount_code"`
}

// bookingResponse is the JSON shape of a created booking.
type bookingResponse struct {
	ID                  string   `json:"id"`
	VehicleID           string   `json:"vehicle_id"`
	ExpiresAt           string   `json:"expires_at"`
	AppliedPromotion    *string  `json:"applied_promotion,omitempty"`
	PromotionPercentage *float64 `json:"promotion_percentage,omitempty"`
}

// createBookingResponse wraps the created booking.
type createBookingResponse struct {
	Booking bookingResponse `json:"booking"`
}

// Create handles POST /bookings, reserving the given vehicle for the authenticated user.
func (h *BookingHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req createBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VehicleID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	booking, err := h.bookings.Create(r.Context(), userID, req.VehicleID, req.DiscountCode)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrVehicleNotAvailable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "mezzo non disponibile"})
		case errors.Is(err, domain.ErrActiveBookingExists):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "hai già una prenotazione attiva"})
		case errors.Is(err, domain.ErrDiscountNotFound):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "codice sconto inesistente"})
		case errors.Is(err, domain.ErrDiscountNotValid):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "codice sconto scaduto o non più valido"})
		default:
			log.Printf("[BOOKINGS] create failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusCreated, createBookingResponse{
		Booking: bookingResponse{
			ID:                  booking.ID,
			VehicleID:           booking.VehicleID,
			ExpiresAt:           booking.ExpiresAt.UTC().Format(time.RFC3339),
			AppliedPromotion:    booking.PromotionDesc,
			PromotionPercentage: booking.PromotionPercentage,
		},
	})
}

// createMultiBookingRequest mirrors the JSON body of POST /bookings/multi (UT.16).
type createMultiBookingRequest struct {
	VehicleIDs []string `json:"vehicle_ids"`
}

// multiBookingResponse is the JSON shape of a multiple reservation.
type multiBookingResponse struct {
	GroupID  string            `json:"group_id"`
	Bookings []bookingResponse `json:"bookings"`
}

// CreateMulti handles POST /bookings/multi (UT.16), riservando insieme più mezzi
// (bici/monopattini) sotto un identificativo di gruppo condiviso.
func (h *BookingHandler) CreateMulti(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req createMultiBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || len(req.VehicleIDs) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	bookings, groupID, err := h.bookings.CreateMulti(r.Context(), userID, req.VehicleIDs)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrActiveBookingExists):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "hai già una prenotazione attiva"})
		case errors.Is(err, domain.ErrVehicleNotAvailable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "uno dei mezzi non è più disponibile"})
		case errors.Is(err, domain.ErrTooManyVehicles):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "puoi prenotare al massimo 5 mezzi"})
		case errors.Is(err, domain.ErrVehiclesTooFar):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "i mezzi devono essere entro 100 metri l'uno dall'altro"})
		case errors.Is(err, domain.ErrVehicleTypeNotAllowed):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "la prenotazione multipla è ammessa solo per bici e monopattini"})
		case errors.Is(err, domain.ErrEmptyGroup):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "nessun mezzo selezionato"})
		default:
			log.Printf("[BOOKINGS] create multi failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	items := make([]bookingResponse, 0, len(bookings))
	for _, b := range bookings {
		items = append(items, bookingResponse{
			ID:        b.ID,
			VehicleID: b.VehicleID,
			ExpiresAt: b.ExpiresAt.UTC().Format(time.RFC3339),
		})
	}

	writeJSON(w, http.StatusCreated, multiBookingResponse{GroupID: groupID, Bookings: items})
}

// createScheduledBookingRequest mirrors the JSON body of POST /bookings/scheduled (UT.19).
type createScheduledBookingRequest struct {
	VehicleID      string `json:"vehicle_id"`
	ScheduledStart string `json:"scheduled_start"` // RFC3339 UTC
}

// scheduledBookingResponse is the JSON shape of a created scheduled booking.
type scheduledBookingResponse struct {
	Booking      scheduledBookingItem `json:"booking"`
	PreAuthAmount float64             `json:"pre_auth_amount"`
}

type scheduledBookingItem struct {
	ID             string `json:"id"`
	VehicleID      string `json:"vehicle_id"`
	ScheduledStart string `json:"scheduled_start"`
	ExpiresAt      string `json:"expires_at"`
}

// CreateScheduled handles POST /bookings/scheduled (UT.19): prenotazione anticipata
// (solo bici/auto, max 24h prima). Calcola la preautorizzazione forfettaria progressiva
// e restituisce l'orario programmato unitamente all'importo da preautorizzare (mock).
func (h *BookingHandler) CreateScheduled(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req createScheduledBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.VehicleID == "" || req.ScheduledStart == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	scheduledStart, err := time.Parse(time.RFC3339, req.ScheduledStart)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "scheduled_start non valido (atteso RFC3339)"})
		return
	}

	booking, preAuth, err := h.bookings.CreateScheduled(r.Context(), userID, req.VehicleID, scheduledStart)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrVehicleNotAvailable):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "mezzo non disponibile"})
		case errors.Is(err, domain.ErrActiveBookingExists):
			writeJSON(w, http.StatusConflict, map[string]string{"error": "hai già una prenotazione attiva"})
		case errors.Is(err, domain.ErrVehicleTypeNotSchedulable):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "la prenotazione anticipata è disponibile solo per bici e automobili"})
		case errors.Is(err, domain.ErrScheduledStartTooSoon):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "l'orario deve essere almeno 15 minuti nel futuro"})
		case errors.Is(err, domain.ErrScheduledStartTooFar):
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{"error": "la prenotazione anticipata è possibile fino a 24 ore in anticipo"})
		default:
			log.Printf("[BOOKINGS] create scheduled failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusCreated, scheduledBookingResponse{
		Booking: scheduledBookingItem{
			ID:             booking.ID,
			VehicleID:      booking.VehicleID,
			ScheduledStart: booking.ScheduledStart.UTC().Format(time.RFC3339),
			ExpiresAt:      booking.ExpiresAt.UTC().Format(time.RFC3339),
		},
		PreAuthAmount: preAuth,
	})
}

// Cancel handles POST /bookings/{id}/cancel, annullando la prenotazione attiva
// dell'utente autenticato e liberando il mezzo.
func (h *BookingHandler) Cancel(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	bookingID := r.PathValue("id")
	if bookingID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	if err := h.bookings.Cancel(r.Context(), userID, bookingID); err != nil {
		switch {
		case errors.Is(err, domain.ErrBookingNotCancellable):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "prenotazione non trovata o già conclusa"})
		default:
			log.Printf("[BOOKINGS] cancel failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "annullata"})
}
