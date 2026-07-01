package usecase_test

import (
	"context"
	"strings"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockVehicleRepository struct {
	vehicles []domain.Vehicle
	// posizioni/stato per GetPositionAndStatus, indicizzate per vehicleID.
	lat, lng float64
	status   string
	updated  bool
}

func (m *mockVehicleRepository) ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error) {
	return m.vehicles, nil
}

func (m *mockVehicleRepository) GetPositionAndStatus(ctx context.Context, id string) (float64, float64, string, string, string, error) {
	if id == "inesistente" {
		return 0, 0, "", "", "", domain.ErrVehicleNotFound
	}
	return m.lat, m.lng, m.status, "ZP-TEST-001", "Bicicletta", nil
}

func (m *mockVehicleRepository) UpdatePosition(ctx context.Context, id string, lat, lng float64) error {
	m.updated = true
	return nil
}

type mockVehicleAlertRecorder struct {
	inserted  []domain.AvailabilityAlert
	hasRecent bool
}

func (m *mockVehicleAlertRecorder) Insert(ctx context.Context, alert domain.AvailabilityAlert) error {
	m.inserted = append(m.inserted, alert)
	return nil
}

func (m *mockVehicleAlertRecorder) HasRecentVehicleAlert(ctx context.Context, alertType, vehicleID string) (bool, error) {
	return m.hasRecent, nil
}

func TestListAvailable(t *testing.T) {
	mockVehicles := []domain.Vehicle{
		{ID: "v1", Type: "Bicicletta", BatteryLevel: 90},
		{ID: "v2", Type: "Monopattino elettrico", BatteryLevel: 80},
	}
	repo := &mockVehicleRepository{vehicles: mockVehicles}
	uc := usecase.NewVehicleUsecase(repo, &mockVehicleAlertRecorder{})

	res, err := uc.ListAvailable(context.Background(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(res) != 2 || res[0].ID != "v1" {
		t.Fatal("expected mock vehicles to be returned")
	}
}

// --- OP.02 / OP.07: rilevamento movimento illecito ---

func TestReportPosition_MovementBeyondThreshold_NotInUso_TriggersAlert(t *testing.T) {
	repo := &mockVehicleRepository{lat: 45.4654, lng: 9.1859, status: "disponibile"}
	alerts := &mockVehicleAlertRecorder{}
	uc := usecase.NewVehicleUsecase(repo, alerts)

	// ~1.2km a nord: ben oltre la soglia di 200m.
	triggered, err := uc.ReportPosition(context.Background(), "v1", 45.4760, 9.1859)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !triggered {
		t.Fatal("expected movement alert to be triggered")
	}
	if len(alerts.inserted) != 1 || alerts.inserted[0].Type != domain.AlertTypeMovimento {
		t.Fatalf("expected one movimento alert inserted, got %+v", alerts.inserted)
	}
	if !repo.updated {
		t.Fatal("expected vehicle position to be updated regardless of the alert")
	}
	if !strings.Contains(alerts.inserted[0].Message, "ZP-TEST-001") {
		t.Fatalf("expected message to include the vehicle QR code, got %q", alerts.inserted[0].Message)
	}
}

func TestReportPosition_MovementWithinThreshold_NoAlert(t *testing.T) {
	repo := &mockVehicleRepository{lat: 45.4654, lng: 9.1859, status: "disponibile"}
	alerts := &mockVehicleAlertRecorder{}
	uc := usecase.NewVehicleUsecase(repo, alerts)

	// Spostamento di pochi metri: sotto soglia.
	triggered, err := uc.ReportPosition(context.Background(), "v1", 45.46545, 9.18595)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if triggered {
		t.Fatal("expected no alert for a small movement")
	}
	if len(alerts.inserted) != 0 {
		t.Fatalf("expected no alert inserted, got %+v", alerts.inserted)
	}
}

func TestReportPosition_MovementWhileInUso_NoAlert(t *testing.T) {
	repo := &mockVehicleRepository{lat: 45.4654, lng: 9.1859, status: "in_uso"}
	alerts := &mockVehicleAlertRecorder{}
	uc := usecase.NewVehicleUsecase(repo, alerts)

	triggered, err := uc.ReportPosition(context.Background(), "v1", 45.4760, 9.1859)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if triggered {
		t.Fatal("un mezzo in corsa che si sposta non e' un movimento illecito")
	}
}

func TestReportPosition_DedupeWithinWindow_NoDuplicateAlert(t *testing.T) {
	repo := &mockVehicleRepository{lat: 45.4654, lng: 9.1859, status: "disponibile"}
	alerts := &mockVehicleAlertRecorder{hasRecent: true}
	uc := usecase.NewVehicleUsecase(repo, alerts)

	triggered, err := uc.ReportPosition(context.Background(), "v1", 45.4760, 9.1859)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if triggered {
		t.Fatal("expected no new alert when one was already raised recently")
	}
	if len(alerts.inserted) != 0 {
		t.Fatalf("expected no alert inserted, got %+v", alerts.inserted)
	}
}

func TestReportPosition_VehicleNotFound(t *testing.T) {
	repo := &mockVehicleRepository{}
	uc := usecase.NewVehicleUsecase(repo, &mockVehicleAlertRecorder{})

	_, err := uc.ReportPosition(context.Background(), "inesistente", 45.46, 9.18)
	if err != domain.ErrVehicleNotFound {
		t.Fatalf("expected ErrVehicleNotFound, got %v", err)
	}
}
