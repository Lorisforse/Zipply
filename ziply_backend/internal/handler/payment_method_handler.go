package handler

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// Patterns che validano i dati minimi della carta accettati dal backend: solo
// le ultime 4 cifre e la scadenza MM/YY (il PAN completo e il CVV non arrivano
// mai qui, sono validati e scartati lato client).
var (
	cardLastFourPattern = regexp.MustCompile(`^[0-9]{4}$`)
	cardExpiryPattern   = regexp.MustCompile(`^(0[1-9]|1[0-2])/[0-9]{2}$`)
)

// PaymentMethodHandler handles the /payment-methods HTTP endpoints.
type PaymentMethodHandler struct {
	methods *usecase.PaymentMethodUsecase
}

// NewPaymentMethodHandler creates a PaymentMethodHandler backed by the given usecase.
func NewPaymentMethodHandler(methods *usecase.PaymentMethodUsecase) *PaymentMethodHandler {
	return &PaymentMethodHandler{methods: methods}
}

// createPaymentMethodRequest mirrors the JSON body of POST /payment-methods.
type createPaymentMethodRequest struct {
	CardLastFour string `json:"card_last_four"`
	CardExpiry   string `json:"card_expiry"`
	IsDefault    bool   `json:"is_default"`
}

// paymentMethodResponse is the JSON shape of a single saved payment method.
type paymentMethodResponse struct {
	ID           string `json:"id"`
	CardLastFour string `json:"card_last_four"`
	CardExpiry   string `json:"card_expiry"`
	IsDefault    bool   `json:"is_default"`
	CreatedAt    string `json:"created_at"`
}

// newPaymentMethodResponse maps a domain payment method to its JSON shape.
func newPaymentMethodResponse(pm *domain.PaymentMethod) paymentMethodResponse {
	return paymentMethodResponse{
		ID:           pm.ID,
		CardLastFour: pm.CardLastFour,
		CardExpiry:   pm.CardExpiry,
		IsDefault:    pm.IsDefault,
		CreatedAt:    pm.CreatedAt.UTC().Format(time.RFC3339),
	}
}

// Create handles POST /payment-methods, saving a payment method for the authenticated user.
func (h *PaymentMethodHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req createPaymentMethodRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}
	if !cardLastFourPattern.MatchString(req.CardLastFour) || !cardExpiryPattern.MatchString(req.CardExpiry) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	pm, err := h.methods.Add(r.Context(), userID, req.CardLastFour, req.CardExpiry, req.IsDefault)
	if err != nil {
		log.Printf("[PAYMENTS] create failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusCreated, newPaymentMethodResponse(pm))
}

// List handles GET /payment-methods, returning the authenticated user's saved payment methods.
func (h *PaymentMethodHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	methods, err := h.methods.List(r.Context(), userID)
	if err != nil {
		log.Printf("[PAYMENTS] list failed: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	resp := make([]paymentMethodResponse, 0, len(methods))
	for i := range methods {
		resp = append(resp, newPaymentMethodResponse(&methods[i]))
	}

	writeJSON(w, http.StatusOK, resp)
}

// Delete handles DELETE /payment-methods/{id}, removing one of the authenticated
// user's payment methods. Returns 404 when the card does not belong to the user.
func (h *PaymentMethodHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Dati non validi"})
		return
	}

	if err := h.methods.Delete(r.Context(), id, userID); err != nil {
		switch {
		case errors.Is(err, domain.ErrPaymentMethodNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "metodo di pagamento non trovato"})
		default:
			log.Printf("[PAYMENTS] delete failed: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
