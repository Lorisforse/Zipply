package usecase_test

import (
	"context"
	"strings"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockAvailabilityAlertRepo implementa usecase.AvailabilityAlertRepository in
// memoria per i test del worker di rilevamento anomalie (OP.02 / OP.07).
type mockAvailabilityAlertRepo struct {
	batteryVehicles []domain.VehicleBatteryStatus
	areas           []domain.ServiceArea
	// availablePerArea e' indicizzata per Center.Lat (unico per area nei test),
	// dato che CountAvailableInArea riceve solo il centro, non l'ID area.
	availablePerArea map[float64]int

	recentVehicleAlert map[string]bool // vehicleID -> esiste gia' un avviso recente
	recentAreaAlert    map[string]bool // areaID -> esiste gia' un avviso recente

	inserted []domain.AvailabilityAlert
}

func newMockAvailabilityAlertRepo() *mockAvailabilityAlertRepo {
	return &mockAvailabilityAlertRepo{
		availablePerArea:   make(map[float64]int),
		recentVehicleAlert: make(map[string]bool),
		recentAreaAlert:    make(map[string]bool),
	}
}

func (m *mockAvailabilityAlertRepo) Insert(ctx context.Context, alert domain.AvailabilityAlert) error {
	m.inserted = append(m.inserted, alert)
	return nil
}

func (m *mockAvailabilityAlertRepo) List(ctx context.Context) ([]domain.AvailabilityAlert, error) {
	return m.inserted, nil
}

func (m *mockAvailabilityAlertRepo) HasRecentVehicleAlert(ctx context.Context, alertType, vehicleID string) (bool, error) {
	return m.recentVehicleAlert[vehicleID], nil
}

func (m *mockAvailabilityAlertRepo) HasRecentAreaAlert(ctx context.Context, serviceAreaID string) (bool, error) {
	return m.recentAreaAlert[serviceAreaID], nil
}

func (m *mockAvailabilityAlertRepo) LowBatteryVehicles(ctx context.Context, threshold int) ([]domain.VehicleBatteryStatus, error) {
	out := make([]domain.VehicleBatteryStatus, 0)
	for _, v := range m.batteryVehicles {
		if v.BatteryLevel < threshold {
			out = append(out, v)
		}
	}
	return out, nil
}

func (m *mockAvailabilityAlertRepo) ActiveServiceAreas(ctx context.Context) ([]domain.ServiceArea, error) {
	return m.areas, nil
}

func (m *mockAvailabilityAlertRepo) CountAvailableInArea(ctx context.Context, center domain.ServiceAreaCenter) (int, error) {
	return m.availablePerArea[center.Lat], nil
}

// --- OP.02: batteria scarica ---

func TestRunChecks_LowBattery_TriggersAlert(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	repo.batteryVehicles = []domain.VehicleBatteryStatus{
		{VehicleID: "v1", BatteryLevel: 15, QrCode: "ZP-BIKE-001", VehicleType: "Bicicletta"},
	}
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 1 || repo.inserted[0].Type != domain.AlertTypeBatteria {
		t.Fatalf("expected one batteria alert, got %+v", repo.inserted)
	}
	if *repo.inserted[0].VehicleID != "v1" {
		t.Fatalf("expected alert for v1, got %+v", repo.inserted[0])
	}
	if !strings.Contains(repo.inserted[0].Message, "ZP-BIKE-001") {
		t.Fatalf("expected message to include the vehicle QR code, got %q", repo.inserted[0].Message)
	}
}

func TestRunChecks_BatteryAboveThreshold_NoAlert(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	repo.batteryVehicles = []domain.VehicleBatteryStatus{{VehicleID: "v1", BatteryLevel: 80}}
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 0 {
		t.Fatalf("expected no alert, got %+v", repo.inserted)
	}
}

func TestRunChecks_LowBattery_DedupeWithinWindow(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	repo.batteryVehicles = []domain.VehicleBatteryStatus{{VehicleID: "v1", BatteryLevel: 10}}
	repo.recentVehicleAlert["v1"] = true
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 0 {
		t.Fatalf("expected no duplicate alert, got %+v", repo.inserted)
	}
}

// --- OP.07: scarsita' mezzi per area (UC-25) ---

func TestRunChecks_AreaBelowThreshold_TriggersAlert(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	area := domain.ServiceArea{ID: "a1", Name: "Centro", MinVehicles: 3, Center: domain.ServiceAreaCenter{Lat: 45.46, Lng: 9.18, Radius: 1000}}
	repo.areas = []domain.ServiceArea{area}
	repo.availablePerArea[area.Center.Lat] = 1
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 1 || repo.inserted[0].Type != domain.AlertTypeScarsita {
		t.Fatalf("expected one scarsita alert, got %+v", repo.inserted)
	}
	if *repo.inserted[0].ServiceAreaID != "a1" || *repo.inserted[0].AvailableCount != 1 {
		t.Fatalf("expected alert for area a1 with count 1, got %+v", repo.inserted[0])
	}
}

func TestRunChecks_AreaAboveThreshold_NoAlert(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	area := domain.ServiceArea{ID: "a1", Name: "Centro", MinVehicles: 3, Center: domain.ServiceAreaCenter{Lat: 45.46, Lng: 9.18, Radius: 1000}}
	repo.areas = []domain.ServiceArea{area}
	repo.availablePerArea[area.Center.Lat] = 5
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 0 {
		t.Fatalf("expected no alert, got %+v", repo.inserted)
	}
}

func TestRunChecks_AreaBelowThreshold_DedupeWithinWindow(t *testing.T) {
	repo := newMockAvailabilityAlertRepo()
	area := domain.ServiceArea{ID: "a1", Name: "Centro", MinVehicles: 3, Center: domain.ServiceAreaCenter{Lat: 45.46, Lng: 9.18, Radius: 1000}}
	repo.areas = []domain.ServiceArea{area}
	repo.availablePerArea[area.Center.Lat] = 0
	repo.recentAreaAlert["a1"] = true
	uc := usecase.NewAvailabilityAlertUsecase(repo)

	if err := uc.RunChecks(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(repo.inserted) != 0 {
		t.Fatalf("expected no duplicate alert, got %+v", repo.inserted)
	}
}
