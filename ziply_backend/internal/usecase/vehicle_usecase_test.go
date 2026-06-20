package usecase_test

import (
	"context"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockVehicleRepository struct {
	vehicles []domain.Vehicle
}

func (m *mockVehicleRepository) ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error) {
	return m.vehicles, nil
}

func TestListAvailable(t *testing.T) {
	mockVehicles := []domain.Vehicle{
		{ID: "v1", Type: "Bicicletta", BatteryLevel: 90},
		{ID: "v2", Type: "Monopattino elettrico", BatteryLevel: 80},
	}
	repo := &mockVehicleRepository{vehicles: mockVehicles}
	uc := usecase.NewVehicleUsecase(repo)

	res, err := uc.ListAvailable(context.Background(), nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(res) != 2 || res[0].ID != "v1" {
		t.Fatal("expected mock vehicles to be returned")
	}
}
