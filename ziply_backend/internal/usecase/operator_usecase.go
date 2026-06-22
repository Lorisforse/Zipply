package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// OperatorRepository definisce la persistenza necessaria all'area operatore
// (OP.01). Volutamente ridotta alla sola lettura della flotta: le altre
// funzionalità operatore (gestione malfunzionamenti, chat) sono rinviate allo
// Sprint 3.
type OperatorRepository interface {
	ListAllVehicles(ctx context.Context) ([]domain.OperatorVehicle, error)
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
