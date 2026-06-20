package usecase_test

import (
	"context"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockRideRepository struct {
	rides   map[string]*domain.Ride
	ended   map[string]bool
	paused  map[string]bool
	resumed map[string]bool
}

func (m *mockRideRepository) Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error) {
	r := &domain.Ride{
		ID:        "r-test-id",
		UserID:    userID,
		VehicleID: vehicleID,
		Status:    "attiva",
	}
	m.rides[r.ID] = r
	return r, nil
}

func (m *mockRideRepository) End(ctx context.Context, userID, rideID string) (*domain.RideSummary, error) {
	m.ended[rideID] = true
	if r, ok := m.rides[rideID]; ok {
		r.Status = "completata"
	}
	return &domain.RideSummary{
		DurationMinutes: 10,
		TotalCost:       2.5,
		Co2SavedGrams:   500,
	}, nil
}

func (m *mockRideRepository) UnlockGroup(ctx context.Context, userID, groupID string) ([]*domain.Ride, error) {
	r := &domain.Ride{
		ID:        "rg-test-id",
		UserID:    userID,
		VehicleID: "v-group",
		Status:    "attiva",
		GroupID:   &groupID,
	}
	m.rides[r.ID] = r
	return []*domain.Ride{r}, nil
}

func (m *mockRideRepository) EndGroup(ctx context.Context, userID, groupID string) (*domain.RideSummary, error) {
	return &domain.RideSummary{
		DurationMinutes: 20,
		TotalCost:       5.0,
		Co2SavedGrams:   1000,
	}, nil
}

func (m *mockRideRepository) Pause(ctx context.Context, userID, rideID string) (string, error) {
	m.paused[rideID] = true
	if r, ok := m.rides[rideID]; ok {
		r.Status = "paused"
	}
	return "Monopattino elettrico", nil
}

func (m *mockRideRepository) Resume(ctx context.Context, userID, rideID string) (string, error) {
	m.resumed[rideID] = true
	if r, ok := m.rides[rideID]; ok {
		r.Status = "attiva"
	}
	return "Monopattino elettrico", nil
}

func TestRideFlow(t *testing.T) {
	repo := &mockRideRepository{
		rides:   make(map[string]*domain.Ride),
		ended:   make(map[string]bool),
		paused:  make(map[string]bool),
		resumed: make(map[string]bool),
	}
	uc := usecase.NewRideUsecase(repo)

	// Test unlock
	r, err := uc.Unlock(context.Background(), "u1", "v1", "")
	if err != nil {
		t.Fatalf("failed to unlock: %v", err)
	}
	if r.ID != "r-test-id" || r.Status != "attiva" {
		t.Fatal("invalid ride created")
	}

	// Test pause
	err = uc.Pause(context.Background(), "u1", r.ID)
	if err != nil {
		t.Fatalf("failed to pause: %v", err)
	}
	if !repo.paused[r.ID] {
		t.Fatal("ride was not paused in repository")
	}

	// Test resume
	err = uc.Resume(context.Background(), "u1", r.ID)
	if err != nil {
		t.Fatalf("failed to resume: %v", err)
	}
	if !repo.resumed[r.ID] {
		t.Fatal("ride was not resumed in repository")
	}

	// Test end
	summary, err := uc.End(context.Background(), "u1", r.ID)
	if err != nil {
		t.Fatalf("failed to end: %v", err)
	}
	if !repo.ended[r.ID] {
		t.Fatal("ride was not ended in repository")
	}
	if summary.TotalCost != 2.5 {
		t.Fatal("invalid summary cost")
	}
}

// UT.16 — corsa di gruppo: sblocco simultaneo e fine corsa aggregata.
func TestRideGroupFlow(t *testing.T) {
	repo := &mockRideRepository{
		rides:   make(map[string]*domain.Ride),
		ended:   make(map[string]bool),
		paused:  make(map[string]bool),
		resumed: make(map[string]bool),
	}
	uc := usecase.NewRideUsecase(repo)

	// Sblocco di gruppo
	rides, err := uc.UnlockGroup(context.Background(), "u1", "g1")
	if err != nil {
		t.Fatalf("failed to unlock group: %v", err)
	}
	if len(rides) == 0 {
		t.Fatal("expected at least one ride in the group")
	}
	if rides[0].GroupID == nil || *rides[0].GroupID != "g1" {
		t.Fatal("ride not linked to the group")
	}

	// Fine corsa di gruppo (riepilogo aggregato)
	summary, err := uc.EndGroup(context.Background(), "u1", "g1")
	if err != nil {
		t.Fatalf("failed to end group: %v", err)
	}
	if summary.TotalCost != 5.0 {
		t.Fatalf("unexpected group summary cost: %v", summary.TotalCost)
	}
}
