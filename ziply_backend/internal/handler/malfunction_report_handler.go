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
