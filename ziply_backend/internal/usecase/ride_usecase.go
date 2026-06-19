package usecase

import (
	"context"
	"log"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// RideRepository abstracts the persistence required by the ride flow
// (unlock + end + pause + resume).
type RideRepository interface {
	Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error)
	End(ctx context.Context, userID, rideID string) (*domain.RideSummary, error)
	Pause(ctx context.Context, userID, rideID string) (string, error)
	Resume(ctx context.Context, userID, rideID string) (string, error)
}

// RideUsecase implements the vehicle unlock, end, pause and resume flows.
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

// End chiude la corsa attiva dell'utente, calcola il costo e libera il mezzo.
func (uc *RideUsecase) End(ctx context.Context, userID, rideID string) (*domain.RideSummary, error) {
	return uc.rides.End(ctx, userID, rideID)
}

// Pause mette in pausa la corsa attiva dell'utente e simula la messa in sicurezza via IoT.
func (uc *RideUsecase) Pause(ctx context.Context, userID, rideID string) error {
	vehicleType, err := uc.rides.Pause(ctx, userID, rideID)
	if err != nil {
		return err
	}

	switch vehicleType {
	case "Bicicletta":
		log.Printf("[IoT] Messo in sicurezza mezzo (lucchetto chiuso) per corsa %s", rideID)
	case "Monopattino elettrico":
		log.Printf("[IoT] Messo in sicurezza mezzo (motore disabilitato) per corsa %s", rideID)
	case "Automobile elettrica":
		log.Printf("[IoT] Messo in sicurezza mezzo (portiere bloccate) per corsa %s", rideID)
	default:
		log.Printf("[IoT] Messo in sicurezza mezzo per corsa %s", rideID)
	}

	return nil
}

// Resume riattiva la corsa in pausa dell'utente e simula lo sblocco via IoT.
func (uc *RideUsecase) Resume(ctx context.Context, userID, rideID string) error {
	vehicleType, err := uc.rides.Resume(ctx, userID, rideID)
	if err != nil {
		return err
	}

	switch vehicleType {
	case "Bicicletta":
		log.Printf("[IoT] Sbloccato mezzo (lucchetto aperto) per corsa %s", rideID)
	case "Monopattino elettrico":
		log.Printf("[IoT] Sbloccato mezzo (motore abilitato) per corsa %s", rideID)
	case "Automobile elettrica":
		log.Printf("[IoT] Sbloccato mezzo (portiere sbloccate) per corsa %s", rideID)
	default:
		log.Printf("[IoT] Sbloccato mezzo per corsa %s", rideID)
	}

	return nil
}
