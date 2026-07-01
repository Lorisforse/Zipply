package usecase_test

import (
	"context"
	"errors"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockOperatorRepo implementa usecase.OperatorRepository in memoria per i test.
type mockOperatorRepo struct {
	vehicles      map[string]*domain.OperatorVehicle
	parkingZones  map[string]*domain.ParkingZone
	openReports   map[string]bool // vehicleID -> ha segnalazioni aperte
}

func (m *mockOperatorRepo) ListAllVehicles(ctx context.Context) ([]domain.OperatorVehicle, error) {
	out := make([]domain.OperatorVehicle, 0, len(m.vehicles))
	for _, v := range m.vehicles {
		out = append(out, *v)
	}
	return out, nil
}

func (m *mockOperatorRepo) BlockVehicle(ctx context.Context, vehicleID string) error {
	v, ok := m.vehicles[vehicleID]
	if !ok {
		return domain.ErrVehicleNotFound
	}
	v.Status = "bloccato"
	return nil
}

func (m *mockOperatorRepo) UnblockVehicle(ctx context.Context, vehicleID string) error {
	v, ok := m.vehicles[vehicleID]
	if !ok || v.Status != "bloccato" {
		return domain.ErrVehicleNotFound
	}
	if m.openReports[vehicleID] {
		v.Status = "manutenzione"
	} else {
		v.Status = "disponibile"
	}
	return nil
}

func (m *mockOperatorRepo) ListParkingZones(ctx context.Context) ([]domain.ParkingZone, error) {
	out := make([]domain.ParkingZone, 0, len(m.parkingZones))
	for _, z := range m.parkingZones {
		out = append(out, *z)
	}
	return out, nil
}

func (m *mockOperatorRepo) CreateParkingZone(ctx context.Context, z *domain.ParkingZone) error {
	z.ID = "zone-test-id"
	m.parkingZones[z.ID] = z
	return nil
}

func (m *mockOperatorRepo) DeleteParkingZone(ctx context.Context, id string) error {
	if _, ok := m.parkingZones[id]; !ok {
		return domain.ErrParkingZoneNotFound
	}
	delete(m.parkingZones, id)
	return nil
}

func newOperatorRepo() *mockOperatorRepo {
	return &mockOperatorRepo{
		vehicles: map[string]*domain.OperatorVehicle{
			"v1": {ID: "v1", QrCode: "ZP-001", Status: "disponibile"},
			"v2": {ID: "v2", QrCode: "ZP-002", Status: "bloccato"},
		},
		parkingZones: make(map[string]*domain.ParkingZone),
		openReports:  make(map[string]bool),
	}
}

// --- OP.11 / UC-32: blocco remoto ---

func TestBlockVehicle_Success(t *testing.T) {
	repo := newOperatorRepo()
	uc := usecase.NewOperatorUsecase(repo)

	if err := uc.BlockVehicle(context.Background(), "v1"); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if repo.vehicles["v1"].Status != "bloccato" {
		t.Errorf("expected status 'bloccato', got %q", repo.vehicles["v1"].Status)
	}
}

func TestBlockVehicle_NotFound(t *testing.T) {
	uc := usecase.NewOperatorUsecase(newOperatorRepo())
	err := uc.BlockVehicle(context.Background(), "inesistente")
	if !errors.Is(err, domain.ErrVehicleNotFound) {
		t.Errorf("expected ErrVehicleNotFound, got %v", err)
	}
}

func TestUnblockVehicle_NoOpenReports_BecomesDisponibile(t *testing.T) {
	repo := newOperatorRepo()
	uc := usecase.NewOperatorUsecase(repo)

	if err := uc.UnblockVehicle(context.Background(), "v2"); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if repo.vehicles["v2"].Status != "disponibile" {
		t.Errorf("expected status 'disponibile', got %q", repo.vehicles["v2"].Status)
	}
}

func TestUnblockVehicle_WithOpenReports_BecomesManutenzione(t *testing.T) {
	repo := newOperatorRepo()
	repo.openReports["v2"] = true
	uc := usecase.NewOperatorUsecase(repo)

	if err := uc.UnblockVehicle(context.Background(), "v2"); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if repo.vehicles["v2"].Status != "manutenzione" {
		t.Errorf("expected status 'manutenzione' (open reports exist), got %q", repo.vehicles["v2"].Status)
	}
}

func TestUnblockVehicle_NotBlocked_ReturnsNotFound(t *testing.T) {
	uc := usecase.NewOperatorUsecase(newOperatorRepo())
	// v1 e' 'disponibile', non 'bloccato'
	err := uc.UnblockVehicle(context.Background(), "v1")
	if !errors.Is(err, domain.ErrVehicleNotFound) {
		t.Errorf("expected ErrVehicleNotFound for non-blocked vehicle, got %v", err)
	}
}

// TestBlockedVehicle_NotBookable verifica l'invariante: un mezzo bloccato
// non puo' tornare 'disponibile' via unblock se ha segnalazioni aperte.
// La protezione contro la prenotazione e' garantita da BookingRepository.Create
// che richiede status='disponibile' (SELECT FOR UPDATE + check).
// Questo test documenta che unblock con report aperti -> 'manutenzione',
// che il booking usecase rifiuta come gli altri stati non-disponibili.
func TestBlockedVehicle_NotBookable(t *testing.T) {
	repo := newOperatorRepo()
	repo.openReports["v2"] = true
	uc := usecase.NewOperatorUsecase(repo)

	// Sblocco -> manutenzione (non disponibile)
	if err := uc.UnblockVehicle(context.Background(), "v2"); err != nil {
		t.Fatalf("unblock failed: %v", err)
	}
	if repo.vehicles["v2"].Status == "disponibile" {
		t.Error("mezzo con segnalazioni aperte non deve tornare disponibile dopo sblocco")
	}
}

// --- OP.04 / UC-27: zone parcheggio ---

func TestCreateParkingZone_Success(t *testing.T) {
	repo := newOperatorRepo()
	uc := usecase.NewOperatorUsecase(repo)

	zone := &domain.ParkingZone{
		Name:        "Zona A Bari",
		Center:      domain.ParkingZoneCenter{Lat: 41.12, Lng: 16.86, Radius: 100},
		BonusCredit: 0.50,
	}
	if err := uc.CreateParkingZone(context.Background(), zone); err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if zone.ID != "zone-test-id" {
		t.Errorf("expected zone ID set after create, got %q", zone.ID)
	}
}

func TestDeleteParkingZone_NotFound(t *testing.T) {
	uc := usecase.NewOperatorUsecase(newOperatorRepo())
	err := uc.DeleteParkingZone(context.Background(), "inesistente")
	if !errors.Is(err, domain.ErrParkingZoneNotFound) {
		t.Errorf("expected ErrParkingZoneNotFound, got %v", err)
	}
}
