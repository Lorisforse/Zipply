package usecase_test

import (
	"context"
	"errors"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockMalfunctionReportRepository struct {
	rides        map[string]*domain.Ride
	reports      map[string]*domain.MalfunctionReport
	vehicleState map[string]string // updates vehicle status
}

func (m *mockMalfunctionReportRepository) GetRideDetails(ctx context.Context, rideID string) (*domain.Ride, error) {
	ride, ok := m.rides[rideID]
	if !ok {
		return nil, domain.ErrRideNotFound
	}
	return ride, nil
}

func (m *mockMalfunctionReportRepository) Create(ctx context.Context, report *domain.MalfunctionReport) error {
	report.ID = "rep-test-id"
	m.reports[report.ID] = report
	m.vehicleState[report.VehicleID] = "manutenzione"
	return nil
}

func (m *mockMalfunctionReportRepository) ListAll(ctx context.Context, statusFilter string) ([]domain.OperatorMalfunctionReport, error) {
	out := make([]domain.OperatorMalfunctionReport, 0)
	for _, rep := range m.reports {
		if statusFilter != "" && rep.Status != statusFilter {
			continue
		}
		out = append(out, domain.OperatorMalfunctionReport{
			ID:          rep.ID,
			VehicleID:   rep.VehicleID,
			ProblemType: rep.ProblemType,
			Description: rep.Description,
			Source:      "utente",
			Status:      rep.Status,
		})
	}
	return out, nil
}

func (m *mockMalfunctionReportRepository) UpdateStatus(ctx context.Context, reportID, newStatus string) error {
	rep, ok := m.reports[reportID]
	if !ok {
		return domain.ErrMalfunctionReportNotFound
	}
	rep.Status = newStatus
	if newStatus == domain.MalfunctionStatusRisolto {
		m.vehicleState[rep.VehicleID] = "disponibile"
	}
	return nil
}

func TestReportMalfunction_Success(t *testing.T) {
	rides := map[string]*domain.Ride{
		"r1": {
			ID:        "r1",
			UserID:    "u1",
			VehicleID: "v1",
			Status:    "completata",
		},
	}
	repo := &mockMalfunctionReportRepository{
		rides:        rides,
		reports:      make(map[string]*domain.MalfunctionReport),
		vehicleState: make(map[string]string),
	}

	uc := usecase.NewMalfunctionReportUsecase(repo)
	report, err := uc.Report(context.Background(), "u1", "r1", "freni", "I freni fischiano molto", "http://attachment.url/img.png")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}

	if report.ID != "rep-test-id" {
		t.Errorf("expected report ID rep-test-id, got %s", report.ID)
	}
	if report.Status != "in_attesa" {
		t.Errorf("expected status 'in_attesa', got %s", report.Status)
	}
	if repo.vehicleState["v1"] != "manutenzione" {
		t.Errorf("expected vehicle v1 status to be 'manutenzione', got %s", repo.vehicleState["v1"])
	}
}

func TestReportMalfunction_RideNotFound(t *testing.T) {
	repo := &mockMalfunctionReportRepository{
		rides:        make(map[string]*domain.Ride),
		reports:      make(map[string]*domain.MalfunctionReport),
		vehicleState: make(map[string]string),
	}

	uc := usecase.NewMalfunctionReportUsecase(repo)
	_, err := uc.Report(context.Background(), "u1", "r1", "freni", "desc", "")
	if !errors.Is(err, domain.ErrRideNotFound) {
		t.Errorf("expected ErrRideNotFound, got %v", err)
	}
}

func TestReportMalfunction_WrongUser(t *testing.T) {
	rides := map[string]*domain.Ride{
		"r1": {
			ID:        "r1",
			UserID:    "u1", // owned by u1
			VehicleID: "v1",
			Status:    "completata",
		},
	}
	repo := &mockMalfunctionReportRepository{
		rides:        rides,
		reports:      make(map[string]*domain.MalfunctionReport),
		vehicleState: make(map[string]string),
	}

	uc := usecase.NewMalfunctionReportUsecase(repo)
	_, err := uc.Report(context.Background(), "u2", "r1", "freni", "desc", "") // u2 reports
	if !errors.Is(err, domain.ErrRideNotFound) {
		t.Errorf("expected ErrRideNotFound (for safety), got %v", err)
	}
}

func TestReportMalfunction_RideNotCompleted(t *testing.T) {
	rides := map[string]*domain.Ride{
		"r1": {
			ID:        "r1",
			UserID:    "u1",
			VehicleID: "v1",
			Status:    "attiva", // still active
		},
	}
	repo := &mockMalfunctionReportRepository{
		rides:        rides,
		reports:      make(map[string]*domain.MalfunctionReport),
		vehicleState: make(map[string]string),
	}

	uc := usecase.NewMalfunctionReportUsecase(repo)
	_, err := uc.Report(context.Background(), "u1", "r1", "freni", "desc", "")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	expectedErr := "la segnalazione può essere effettuata solo dopo aver completato la corsa"
	if err.Error() != expectedErr {
		t.Errorf("expected error %q, got %q", expectedErr, err.Error())
	}
}

func TestReportMalfunction_InvalidProblemType(t *testing.T) {
	rides := map[string]*domain.Ride{
		"r1": {
			ID:        "r1",
			UserID:    "u1",
			VehicleID: "v1",
			Status:    "completata",
		},
	}
	repo := &mockMalfunctionReportRepository{
		rides:        rides,
		reports:      make(map[string]*domain.MalfunctionReport),
		vehicleState: make(map[string]string),
	}

	uc := usecase.NewMalfunctionReportUsecase(repo)
	_, err := uc.Report(context.Background(), "u1", "r1", "motore", "desc", "") // 'motore' is not valid
	if !errors.Is(err, domain.ErrInvalidProblemType) {
		t.Errorf("expected ErrInvalidProblemType, got %v", err)
	}
}

// --- OP.03 / UC-26: gestione segnalazioni lato operatore ---

func newOperatorRepoWithReport(status string) *mockMalfunctionReportRepository {
	return &mockMalfunctionReportRepository{
		rides: make(map[string]*domain.Ride),
		reports: map[string]*domain.MalfunctionReport{
			"rep1": {ID: "rep1", VehicleID: "v1", ProblemType: "freni", Status: status},
		},
		vehicleState: map[string]string{"v1": "manutenzione"},
	}
}

func TestListReports_InvalidStatusFilter(t *testing.T) {
	uc := usecase.NewMalfunctionReportUsecase(newOperatorRepoWithReport("in_attesa"))
	_, err := uc.ListReports(context.Background(), "inesistente")
	if !errors.Is(err, domain.ErrInvalidMalfunctionStatus) {
		t.Errorf("expected ErrInvalidMalfunctionStatus, got %v", err)
	}
}

func TestListReports_FilterByStatus(t *testing.T) {
	uc := usecase.NewMalfunctionReportUsecase(newOperatorRepoWithReport("in_attesa"))
	got, err := uc.ListReports(context.Background(), "in_attesa")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 1 || got[0].ID != "rep1" {
		t.Errorf("expected 1 report rep1, got %+v", got)
	}
	none, _ := uc.ListReports(context.Background(), "risolto")
	if len(none) != 0 {
		t.Errorf("expected no report for status risolto, got %+v", none)
	}
}

func TestUpdateStatus_RejectsInAttesa(t *testing.T) {
	uc := usecase.NewMalfunctionReportUsecase(newOperatorRepoWithReport("in_attesa"))
	err := uc.UpdateStatus(context.Background(), "rep1", "in_attesa")
	if !errors.Is(err, domain.ErrInvalidMalfunctionStatus) {
		t.Errorf("expected ErrInvalidMalfunctionStatus, got %v", err)
	}
}

func TestUpdateStatus_ResolvedFreesVehicle(t *testing.T) {
	repo := newOperatorRepoWithReport("preso_in_carico")
	uc := usecase.NewMalfunctionReportUsecase(repo)
	if err := uc.UpdateStatus(context.Background(), "rep1", "risolto"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.reports["rep1"].Status != "risolto" {
		t.Errorf("expected report status risolto, got %q", repo.reports["rep1"].Status)
	}
	if repo.vehicleState["v1"] != "disponibile" {
		t.Errorf("expected vehicle disponibile after resolution, got %q", repo.vehicleState["v1"])
	}
}

func TestUpdateStatus_NotFound(t *testing.T) {
	uc := usecase.NewMalfunctionReportUsecase(newOperatorRepoWithReport("in_attesa"))
	err := uc.UpdateStatus(context.Background(), "inesistente", "risolto")
	if !errors.Is(err, domain.ErrMalfunctionReportNotFound) {
		t.Errorf("expected ErrMalfunctionReportNotFound, got %v", err)
	}
}
