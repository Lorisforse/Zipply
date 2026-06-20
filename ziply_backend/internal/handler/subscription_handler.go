package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// SubscriptionHandler gestisce le richieste HTTP per gli abbonamenti.
type SubscriptionHandler struct {
	usecase *usecase.SubscriptionUsecase
}

// NewSubscriptionHandler crea un nuovo SubscriptionHandler.
func NewSubscriptionHandler(uc *usecase.SubscriptionUsecase) *SubscriptionHandler {
	return &SubscriptionHandler{usecase: uc}
}

// List gestisce GET /subscriptions: restituisce gli abbonamenti dell'utente e
// le tipologie di mezzo disponibili, in modo che il client possa costruire l'intera
// schermata con una sola chiamata.
func (h *SubscriptionHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	subs, types, err := h.usecase.List(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore nel recupero abbonamenti"})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"subscriptions": subs,
		"vehicle_types": types,
	})
}

type subscribeRequest struct {
	VehicleTypeID  string `json:"vehicle_type_id"`
	DurationMonths int    `json:"duration_months"`
}

// Subscribe gestisce POST /subscriptions: crea un nuovo abbonamento per la
// tipologia e durata indicate nel corpo della richiesta.
func (h *SubscriptionHandler) Subscribe(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req subscribeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body JSON malformato"})
		return
	}
	if req.VehicleTypeID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "vehicle_type_id mancante"})
		return
	}

	sub, err := h.usecase.Subscribe(r.Context(), userID, req.VehicleTypeID, req.DurationMonths)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrVehicleTypeNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
		case errors.Is(err, domain.ErrSubscriptionAlreadyActive):
			writeJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
		case errors.Is(err, domain.ErrInvalidDuration):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "errore nella sottoscrizione"})
		}
		return
	}

	writeJSON(w, http.StatusCreated, sub)
}
