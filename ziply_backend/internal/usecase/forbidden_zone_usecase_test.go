package usecase_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockForbiddenZoneRepository struct {
	zones []domain.ForbiddenZone
}

func (m *mockForbiddenZoneRepository) ListActive(ctx context.Context) ([]domain.ForbiddenZone, error) {
	return m.zones, nil
}

func TestListActiveZones(t *testing.T) {
	mockZones := []domain.ForbiddenZone{
		{ID: "z1", Nome: "Centro", Polygon: json.RawMessage(`[[9,45], [10,45], [10,46], [9,46]]`)},
	}
	repo := &mockForbiddenZoneRepository{zones: mockZones}
	uc := usecase.NewForbiddenZoneUsecase(repo)

	res, err := uc.ListActive(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(res) != 1 || res[0].ID != "z1" {
		t.Fatal("expected mock forbidden zones to be returned")
	}
}
