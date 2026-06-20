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
