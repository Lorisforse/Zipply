package usecase

import (
	"context"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// ForbiddenZoneRepository abstracts the persistence of forbidden zones required by the listing flow.
type ForbiddenZoneRepository interface {
	ListActive(ctx context.Context) ([]domain.ForbiddenZone, error)
}

// ForbiddenZoneUsecase implements the forbidden-zones listing flow.
type ForbiddenZoneUsecase struct {
	zones ForbiddenZoneRepository
}

// NewForbiddenZoneUsecase creates a ForbiddenZoneUsecase backed by the given repository.
func NewForbiddenZoneUsecase(zones ForbiddenZoneRepository) *ForbiddenZoneUsecase {
	return &ForbiddenZoneUsecase{zones: zones}
}

// ListActive returns the active forbidden zones.
func (uc *ForbiddenZoneUsecase) ListActive(ctx context.Context) ([]domain.ForbiddenZone, error) {
	return uc.zones.ListActive(ctx)
}
