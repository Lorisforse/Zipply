package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// PaymentMethodRepository abstracts the persistence of payment methods required
// by the payment management flow.
type PaymentMethodRepository interface {
	Create(ctx context.Context, userID, cardLastFour, cardExpiry string, isDefault bool) (*domain.PaymentMethod, error)
	ListByUser(ctx context.Context, userID string) ([]domain.PaymentMethod, error)
	Delete(ctx context.Context, id, userID string) error
}

// PaymentMethodUsecase implements the payment method management flow.
type PaymentMethodUsecase struct {
	methods PaymentMethodRepository
}

// NewPaymentMethodUsecase creates a PaymentMethodUsecase backed by the given repository.
func NewPaymentMethodUsecase(methods PaymentMethodRepository) *PaymentMethodUsecase {
	return &PaymentMethodUsecase{methods: methods}
}

// Add saves a new payment method for the user.
func (uc *PaymentMethodUsecase) Add(ctx context.Context, userID, cardLastFour, cardExpiry string, isDefault bool) (*domain.PaymentMethod, error) {
	return uc.methods.Create(ctx, userID, cardLastFour, cardExpiry, isDefault)
}

// List returns the user's saved payment methods.
func (uc *PaymentMethodUsecase) List(ctx context.Context, userID string) ([]domain.PaymentMethod, error) {
	return uc.methods.ListByUser(ctx, userID)
}

// Delete removes the user's payment method with the given id.
func (uc *PaymentMethodUsecase) Delete(ctx context.Context, id, userID string) error {
	return uc.methods.Delete(ctx, id, userID)
}
