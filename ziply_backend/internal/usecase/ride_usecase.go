package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// RideRepository abstracts the persistence required by the vehicle unlock flow.
type RideRepository interface {
	Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error)
}

// RideUsecase implements the vehicle unlock flow (UT.13).
type RideUsecase struct {
	rides RideRepository
}

// NewRideUsecase creates a RideUsecase backed by the given repository.
func NewRideUsecase(rides RideRepository) *RideUsecase {
	return &RideUsecase{rides: rides}
}

// Unlock starts a ride on the vehicle reserved by the user. The vehicle is
// identified by vehicleID (proximity) or qrCode (QR scan); exactly one is set.
func (uc *RideUsecase) Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error) {
	return uc.rides.Unlock(ctx, userID, vehicleID, qrCode)
}
