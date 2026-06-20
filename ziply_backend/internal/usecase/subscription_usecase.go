package usecase

import (
	"context"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// SubscriptionRepository definisce i metodi richiesti per la persistenza degli abbonamenti.
type SubscriptionRepository interface {
	ListVehicleTypes(ctx context.Context) ([]domain.VehicleType, error)
	VehicleTypeExists(ctx context.Context, vehicleTypeID string) (bool, error)
	HasActive(ctx context.Context, userID, vehicleTypeID string) (bool, error)
	ListByUser(ctx context.Context, userID string) ([]domain.Subscription, error)
	Create(ctx context.Context, sub *domain.Subscription) error
}

// SubscriptionUsecase implementa la business logic degli abbonamenti.
type SubscriptionUsecase struct {
	repo SubscriptionRepository
}

// NewSubscriptionUsecase crea un nuovo SubscriptionUsecase.
func NewSubscriptionUsecase(repo SubscriptionRepository) *SubscriptionUsecase {
	return &SubscriptionUsecase{repo: repo}
}

// validDurations enumera le durate consentite in mesi.
var validDurations = map[int]bool{1: true, 3: true, 6: true, 12: true}

// List restituisce gli abbonamenti dell'utente e tutte le tipologie di mezzo disponibili.
func (uc *SubscriptionUsecase) List(ctx context.Context, userID string) ([]domain.Subscription, []domain.VehicleType, error) {
	subs, err := uc.repo.ListByUser(ctx, userID)
	if err != nil {
		return nil, nil, err
	}
	types, err := uc.repo.ListVehicleTypes(ctx)
	if err != nil {
		return nil, nil, err
	}
	return subs, types, nil
}

// Subscribe crea un abbonamento per l'utente per la tipologia e durata indicate.
func (uc *SubscriptionUsecase) Subscribe(ctx context.Context, userID, vehicleTypeID string, durationMonths int) (*domain.Subscription, error) {
	if !validDurations[durationMonths] {
		return nil, domain.ErrInvalidDuration
	}

	exists, err := uc.repo.VehicleTypeExists(ctx, vehicleTypeID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, domain.ErrVehicleTypeNotFound
	}

	hasActive, err := uc.repo.HasActive(ctx, userID, vehicleTypeID)
	if err != nil {
		return nil, err
	}
	if hasActive {
		return nil, domain.ErrSubscriptionAlreadyActive
	}

	sub := &domain.Subscription{
		UserID:        userID,
		VehicleTypeID: vehicleTypeID,
		EndDate:       time.Now().AddDate(0, durationMonths, 0),
	}
	if err := uc.repo.Create(ctx, sub); err != nil {
		return nil, err
	}
	return sub, nil
}
