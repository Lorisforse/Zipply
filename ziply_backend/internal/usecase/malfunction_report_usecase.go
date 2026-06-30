package usecase

import (
	"context"
	"errors"
	"strings"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// MalfunctionReportRepository definisce i metodi richiesti per la persistenza delle segnalazioni.
type MalfunctionReportRepository interface {
	GetRideDetails(ctx context.Context, rideID string) (*domain.Ride, error)
	Create(ctx context.Context, report *domain.MalfunctionReport) error
	ListAll(ctx context.Context, statusFilter string) ([]domain.OperatorMalfunctionReport, error)
	UpdateStatus(ctx context.Context, reportID, newStatus string) error
}

// MalfunctionReportUsecase implementa la business logic delle segnalazioni.
type MalfunctionReportUsecase struct {
	repo MalfunctionReportRepository
}

// NewMalfunctionReportUsecase crea un nuovo MalfunctionReportUsecase.
func NewMalfunctionReportUsecase(repo MalfunctionReportRepository) *MalfunctionReportUsecase {
	return &MalfunctionReportUsecase{repo: repo}
}

// Report crea una nuova segnalazione per una corsa completata.
func (uc *MalfunctionReportUsecase) Report(ctx context.Context, userID, rideID, problemType, description, attachmentURLs string) (*domain.MalfunctionReport, error) {
	// 1. Recupera la corsa per validarla
	ride, err := uc.repo.GetRideDetails(ctx, rideID)
	if err != nil {
		return nil, err
	}

	// 2. Verifica che la corsa appartenga all'utente
	if ride.UserID != userID {
		return nil, domain.ErrRideNotFound
	}

	// 3. Verifica che la corsa sia conclusa
	if ride.Status != "completata" {
		return nil, errors.New("la segnalazione può essere effettuata solo dopo aver completato la corsa")
	}

	// 4. Convalida la tipologia di problema
	cleanedType := strings.TrimSpace(strings.ToLower(problemType))
	if cleanedType == "" || !isValidProblemType(cleanedType) {
		return nil, domain.ErrInvalidProblemType
	}

	report := &domain.MalfunctionReport{
		UserID:         userID,
		VehicleID:      ride.VehicleID,
		RideID:         ride.ID,
		ProblemType:    problemType,
		Description:    description,
		AttachmentURLs: attachmentURLs,
		Status:         "in_attesa",
	}

	// 5. Salva nel DB ed aggiorna lo stato del veicolo
	if err := uc.repo.Create(ctx, report); err != nil {
		return nil, err
	}

	return report, nil
}

// ListReports restituisce le segnalazioni per la dashboard operatore (OP.03 /
// UC-26). statusFilter è facoltativo: se valorizzato deve essere uno stato
// valido, altrimenti vengono restituite tutte le segnalazioni.
func (uc *MalfunctionReportUsecase) ListReports(ctx context.Context, statusFilter string) ([]domain.OperatorMalfunctionReport, error) {
	if statusFilter != "" && !domain.IsValidMalfunctionStatus(statusFilter) {
		return nil, domain.ErrInvalidMalfunctionStatus
	}
	return uc.repo.ListAll(ctx, statusFilter)
}

// UpdateStatus aggiorna lo stato di lavorazione di una segnalazione (OP.03 /
// UC-26). L'operatore può portarla a 'preso_in_carico' o 'risolto'; riportarla
// a 'in_attesa' non è una transizione ammessa.
func (uc *MalfunctionReportUsecase) UpdateStatus(ctx context.Context, reportID, newStatus string) error {
	if newStatus != domain.MalfunctionStatusPresoInCarico && newStatus != domain.MalfunctionStatusRisolto {
		return domain.ErrInvalidMalfunctionStatus
	}
	return uc.repo.UpdateStatus(ctx, reportID, newStatus)
}

func isValidProblemType(pt string) bool {
	valid := map[string]bool{
		"freni":    true,
		"batteria": true,
		"luci":     true,
		"ruote":    true,
		"altro":    true,
	}
	return valid[pt]
}
