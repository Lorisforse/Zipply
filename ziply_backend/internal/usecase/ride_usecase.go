package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// RideRepository abstracts the persistence required by the ride flow
// (unlock + end).
type RideRepository interface {
	Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error)
	End(ctx context.Context, userID, rideID string) error
}

// RideUsecase implements the vehicle unlock flow (UT.13).
type RideUsecase struct {
	rides RideRepository
}

// NewRideUsecase creates a RideUsecase backed by the given repository.
func NewRideUsecase(rides RideRepository) *RideUsecase {
	return &RideUsecase{rides: rides}
}

// Unlock starts a ride on the vehicle. The vehicle is identified by vehicleID
// (proximity) or qrCode (QR scan); exactly one is set. Non richiede una
// prenotazione preesistente.
func (uc *RideUsecase) Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error) {
	return uc.rides.Unlock(ctx, userID, vehicleID, qrCode)
}

// End chiude la corsa attiva dell'utente e libera il mezzo.
func (uc *RideUsecase) End(ctx context.Context, userID, rideID string) error {
	return uc.rides.End(ctx, userID, rideID)
}
