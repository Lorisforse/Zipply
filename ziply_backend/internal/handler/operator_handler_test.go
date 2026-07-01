package handler_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockOperatorRepository implementa usecase.OperatorRepository per i test.
type mockOperatorRepository struct {
	vehicles []domain.OperatorVehicle
	err      error
}

func (m *mockOperatorRepository) ListAllVehicles(ctx context.Context) ([]domain.OperatorVehicle, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.vehicles, nil
}

func (m *mockOperatorRepository) BlockVehicle(ctx context.Context, vehicleID string) error {
	return nil
}

func (m *mockOperatorRepository) UnblockVehicle(ctx context.Context, vehicleID string) error {
	return nil
}

func (m *mockOperatorRepository) ListParkingZones(ctx context.Context) ([]domain.ParkingZone, error) {
	return nil, nil
}

func (m *mockOperatorRepository) CreateParkingZone(ctx context.Context, z *domain.ParkingZone) error {
	return nil
}

func (m *mockOperatorRepository) DeleteParkingZone(ctx context.Context, id string) error {
	return nil
}

func TestListVehicles_OK(t *testing.T) {
	repo := &mockOperatorRepository{
		vehicles: []domain.OperatorVehicle{
			{ID: "v1", Type: "Bicicletta", QrCode: "ZP-BIKE-001", Latitude: 45.46, Longitude: 9.18, BatteryLevel: 92, TariffaAlMinuto: 0.15, Status: "disponibile"},
			{ID: "v2", Type: "Automobile elettrica", QrCode: "ZP-CAR-001", Latitude: 45.47, Longitude: 9.19, BatteryLevel: 12, TariffaAlMinuto: 0.45, Status: "manutenzione"},
		},
	}

	uc := usecase.NewOperatorUsecase(repo)
	h := handler.NewOperatorHandler(uc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /operator/vehicles", h.ListVehicles)

	req := httptest.NewRequest("GET", "/operator/vehicles", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}

	var got []domain.OperatorVehicle
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("risposta non decodificabile: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("expected 2 vehicles, got %d", len(got))
	}
	// Lo status 'manutenzione' deve essere preservato: a differenza della mappa
	// utente, l'operatore vede anche i mezzi non disponibili (OP.01).
	if got[1].Status != "manutenzione" {
		t.Errorf("expected second vehicle status 'manutenzione', got %q", got[1].Status)
	}
}

func TestListVehicles_RepositoryError(t *testing.T) {
	repo := &mockOperatorRepository{err: errors.New("db down")}
	uc := usecase.NewOperatorUsecase(repo)
	h := handler.NewOperatorHandler(uc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /operator/vehicles", h.ListVehicles)

	req := httptest.NewRequest("GET", "/operator/vehicles", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusInternalServerError {
		t.Fatalf("expected status 500, got %d", rr.Code)
	}
}
