package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// OperatorRepository definisce la persistenza necessaria all'area operatore.
type OperatorRepository interface {
	ListAllVehicles(ctx context.Context) ([]domain.OperatorVehicle, error)
	BlockVehicle(ctx context.Context, vehicleID string) error
	UnblockVehicle(ctx context.Context, vehicleID string) error
	ListParkingZones(ctx context.Context) ([]domain.ParkingZone, error)
	CreateParkingZone(ctx context.Context, z *domain.ParkingZone) error
	DeleteParkingZone(ctx context.Context, id string) error
}

// OperatorUsecase orchestra le operazioni dell'area operatore.
type OperatorUsecase struct {
	repo OperatorRepository
}

// NewOperatorUsecase crea un OperatorUsecase sul repository dato.
func NewOperatorUsecase(repo OperatorRepository) *OperatorUsecase {
	return &OperatorUsecase{repo: repo}
}

// ListVehicles restituisce tutti i mezzi della flotta per il monitoraggio in
// tempo reale (OP.01).
func (uc *OperatorUsecase) ListVehicles(ctx context.Context) ([]domain.OperatorVehicle, error) {
	return uc.repo.ListAllVehicles(ctx)
}

// BlockVehicle forza il blocco remoto di un mezzo (OP.11 / UC-32).
func (uc *OperatorUsecase) BlockVehicle(ctx context.Context, vehicleID string) error {
	return uc.repo.BlockVehicle(ctx, vehicleID)
}

// UnblockVehicle sblocca un mezzo: torna 'disponibile' o 'manutenzione'
// a seconda delle segnalazioni aperte (OP.11 / UC-32).
func (uc *OperatorUsecase) UnblockVehicle(ctx context.Context, vehicleID string) error {
	return uc.repo.UnblockVehicle(ctx, vehicleID)
}

// ListParkingZones restituisce le zone parcheggio attive (OP.04 / UC-27).
func (uc *OperatorUsecase) ListParkingZones(ctx context.Context) ([]domain.ParkingZone, error) {
	return uc.repo.ListParkingZones(ctx)
}

// CreateParkingZone crea una nuova zona parcheggio designata (OP.04 / UC-27).
func (uc *OperatorUsecase) CreateParkingZone(ctx context.Context, z *domain.ParkingZone) error {
	return uc.repo.CreateParkingZone(ctx, z)
}

// DeleteParkingZone disattiva una zona parcheggio (OP.04 / UC-27).
func (uc *OperatorUsecase) DeleteParkingZone(ctx context.Context, id string) error {
	return uc.repo.DeleteParkingZone(ctx, id)
}
