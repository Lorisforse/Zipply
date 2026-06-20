package handler

import (
	"errors"
	"fmt"
	"log"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// PaymentLinkHandler gestisce le richieste HTTP per i link di pagamento.
type PaymentLinkHandler struct {
	usecase *usecase.PaymentLinkUsecase
}

// NewPaymentLinkHandler crea un nuovo PaymentLinkHandler.
func NewPaymentLinkHandler(usecase *usecase.PaymentLinkUsecase) *PaymentLinkHandler {
	return &PaymentLinkHandler{usecase: usecase}
}

// Create gestisce POST /rides/{id}/payment-link
func (h *PaymentLinkHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	rideID := r.PathValue("id")
	if rideID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID corsa mancante"})
		return
	}

	pl, err := h.usecase.Generate(r.Context(), userID, rideID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata"})
		default:
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		return
	}

	// Costruiamo il link condivisibile nel formato richiesto
	shareableLink := fmt.Sprintf("ziply://payment-links/%s", pl.ID)

	response := map[string]any{
		"id":              pl.ID,
		"ride_id":         pl.RideID,
		"total_amount":    pl.TotalAmount,
		"participants":    pl.Participants,
		"amount_per_head": pl.AmountPerHead,
		"valid_until":     pl.ValidUntil.UTC().Format("2006-01-02T15:04:05Z"),
		"status":          pl.Status,
		"link":            shareableLink,
	}

	writeJSON(w, http.StatusCreated, response)
}

// Get gestisce GET /payment-links/{id}
func (h *PaymentLinkHandler) Get(w http.ResponseWriter, r *http.Request) {
	_, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	linkID := r.PathValue("id")
	if linkID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID link di pagamento mancante"})
		return
	}

	pl, err := h.usecase.Get(r.Context(), linkID)
	if err != nil {
		if errors.Is(err, domain.ErrPaymentLinkNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "link di pagamento non trovato"})
		} else {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	response := map[string]any{
		"id":              pl.ID,
		"ride_id":         pl.RideID,
		"total_amount":    pl.TotalAmount,
		"participants":    pl.Participants,
		"amount_per_head": pl.AmountPerHead,
		"valid_until":     pl.ValidUntil.UTC().Format("2006-01-02T15:04:05Z"),
		"status":          pl.Status,
		"prenotante_name": pl.PrenotanteName,
	}

	writeJSON(w, http.StatusOK, response)
}

// Pay gestisce POST /payment-links/{id}/pay
func (h *PaymentLinkHandler) Pay(w http.ResponseWriter, r *http.Request) {
	_, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	linkID := r.PathValue("id")
	if linkID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID link di pagamento mancante"})
		return
	}

	err := h.usecase.Pay(r.Context(), linkID)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrPaymentLinkNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "link di pagamento non trovato"})
		case errors.Is(err, domain.ErrPaymentLinkExpired):
			writeJSON(w, http.StatusGone, map[string]string{"error": "link scaduto"})
		case err.Error() == "quota già pagata":
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		default:
			log.Printf("[PAYMENT_LINKS] pay failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "paid",
		"message": "pagamento quota effettuato con successo",
	})
}

// GetCreditBalance gestisce GET /users/credit-balance
func (h *PaymentLinkHandler) GetCreditBalance(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	balance, err := h.usecase.GetUserCreditBalance(r.Context(), userID)
	if err != nil {
		if errors.Is(err, domain.ErrUserNotFound) {
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "utente non trovato"})
		} else {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"credit_balance": balance,
	})
}
