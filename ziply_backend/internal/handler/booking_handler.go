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
