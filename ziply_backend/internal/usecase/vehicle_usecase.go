package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// VehicleRepository abstracts the persistence of vehicles required by the listing flow.
type VehicleRepository interface {
	ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error)
}

// VehicleUsecase implements the available-vehicles listing flow.
type VehicleUsecase struct {
	vehicles VehicleRepository
}

// NewVehicleUsecase creates a VehicleUsecase backed by the given repository.
func NewVehicleUsecase(vehicles VehicleRepository) *VehicleUsecase {
	return &VehicleUsecase{vehicles: vehicles}
}

// ListAvailable returns the available vehicles, optionally restricted to the given geographic filter.
func (uc *VehicleUsecase) ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error) {
	return uc.vehicles.ListAvailable(ctx, filter)
}
