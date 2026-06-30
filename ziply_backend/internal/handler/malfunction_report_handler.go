package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// MalfunctionReportHandler gestisce le richieste HTTP per le segnalazioni di malfunzionamento.
type MalfunctionReportHandler struct {
	usecase *usecase.MalfunctionReportUsecase
}

// NewMalfunctionReportHandler crea un nuovo MalfunctionReportHandler.
func NewMalfunctionReportHandler(usecase *usecase.MalfunctionReportUsecase) *MalfunctionReportHandler {
	return &MalfunctionReportHandler{usecase: usecase}
}

type createReportRequest struct {
	RideID         string   `json:"ride_id"`
	ProblemType    string   `json:"problem_type"`
	Description    string   `json:"description"`
	AttachmentURLs []string `json:"attachment_urls"`
}

// Create gestisce POST /malfunction-reports
func (h *MalfunctionReportHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := r.Context().Value(middleware.CtxUserID).(string)
	if !ok || userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token non valido"})
		return
	}

	var req createReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body JSON malformato"})
		return
	}

	if req.RideID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID corsa mancante"})
		return
	}

	attachments := strings.Join(req.AttachmentURLs, ",")

	report, err := h.usecase.Report(r.Context(), userID, req.RideID, req.ProblemType, req.Description, attachments)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrRideNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "corsa non trovata o non associata all'utente"})
		case errors.Is(err, domain.ErrInvalidProblemType):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tipologia problema non valida (scegli tra freni, batteria, luci, ruote, altro)"})
		default:
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		}
		return
	}

	writeJSON(w, http.StatusCreated, report)
}

// ListForOperator gestisce GET /operator/malfunction-reports (OP.03 / UC-26).
// Restituisce tutte le segnalazioni, opzionalmente filtrate per stato via query
// param `status`, arricchite con i dati del mezzo coinvolto. Riservato ai ruoli
// operatore/amministrazione (RequireRole nel router).
func (h *MalfunctionReportHandler) ListForOperator(w http.ResponseWriter, r *http.Request) {
	statusFilter := strings.TrimSpace(r.URL.Query().Get("status"))

	reports, err := h.usecase.ListReports(r.Context(), statusFilter)
	if err != nil {
		if errors.Is(err, domain.ErrInvalidMalfunctionStatus) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stato non valido (in_attesa, preso_in_carico, risolto)"})
			return
		}
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		return
	}

	writeJSON(w, http.StatusOK, reports)
}

type updateReportStatusRequest struct {
	Status string `json:"status"`
}

// UpdateStatus gestisce PATCH /operator/malfunction-reports/{id} (OP.03 / UC-26).
// Aggiorna lo stato della segnalazione a 'preso_in_carico' o 'risolto'; su
// 'risolto' il mezzo torna disponibile. Riservato a operatore/amministrazione.
func (h *MalfunctionReportHandler) UpdateStatus(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ID segnalazione mancante"})
		return
	}

	var req updateReportStatusRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "body JSON malformato"})
		return
	}

	if err := h.usecase.UpdateStatus(r.Context(), id, req.Status); err != nil {
		switch {
		case errors.Is(err, domain.ErrInvalidMalfunctionStatus):
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "stato non valido (preso_in_carico, risolto)"})
		case errors.Is(err, domain.ErrMalfunctionReportNotFound):
			writeJSON(w, http.StatusNotFound, map[string]string{"error": "segnalazione non trovata"})
		default:
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "Errore interno del server"})
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": req.Status})
}
