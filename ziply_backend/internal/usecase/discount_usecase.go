package usecase

import (
	"context"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// DiscountRepository astrae la persistenza dei codici sconto.
type DiscountRepository interface {
	FindByCode(ctx context.Context, code string) (*domain.DiscountCode, error)
}

// DiscountUsecase implementa la validazione del codice sconto (UT.09).
type DiscountUsecase struct {
	discounts DiscountRepository
}

// NewDiscountUsecase crea un DiscountUsecase sul repository dato.
func NewDiscountUsecase(discounts DiscountRepository) *DiscountUsecase {
	return &DiscountUsecase{discounts: discounts}
}

// Validate verifica esistenza e validità (attivo, non scaduto, con utilizzi
// residui) del codice e ne restituisce i dati. Ritorna domain.ErrDiscountNotFound
// se il codice non esiste e domain.ErrDiscountNotValid se non è utilizzabile.
func (uc *DiscountUsecase) Validate(ctx context.Context, code string) (*domain.DiscountCode, error) {
	d, err := uc.discounts.FindByCode(ctx, code)
	if err != nil {
		return nil, err
	}
	if !d.Usable(time.Now()) {
		return nil, domain.ErrDiscountNotValid
	}
	return d, nil
}
