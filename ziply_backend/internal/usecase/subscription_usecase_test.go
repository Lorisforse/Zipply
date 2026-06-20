package usecase_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockSubscriptionRepository è un mock in memoria del SubscriptionRepository.
type mockSubscriptionRepository struct {
	vehicleTypes  []domain.VehicleType
	subscriptions []domain.Subscription
	// activeMap: userID+vehicleTypeID → true se esiste abbonamento attivo
	activeMap map[string]bool
}

func (m *mockSubscriptionRepository) ListVehicleTypes(_ context.Context) ([]domain.VehicleType, error) {
	return m.vehicleTypes, nil
}

func (m *mockSubscriptionRepository) VehicleTypeExists(_ context.Context, vehicleTypeID string) (bool, error) {
	for _, vt := range m.vehicleTypes {
		if vt.ID == vehicleTypeID {
			return true, nil
		}
	}
	return false, nil
}

func (m *mockSubscriptionRepository) HasActive(_ context.Context, userID, vehicleTypeID string) (bool, error) {
	return m.activeMap[userID+vehicleTypeID], nil
}

func (m *mockSubscriptionRepository) ListByUser(_ context.Context, userID string) ([]domain.Subscription, error) {
	result := make([]domain.Subscription, 0)
	for _, s := range m.subscriptions {
		if s.UserID == userID {
			result = append(result, s)
		}
	}
	return result, nil
}

func (m *mockSubscriptionRepository) Create(_ context.Context, sub *domain.Subscription) error {
	sub.ID = "sub-test-id"
	sub.StartDate = time.Now()
	m.subscriptions = append(m.subscriptions, *sub)
	m.activeMap[sub.UserID+sub.VehicleTypeID] = true
	return nil
}

func newMockSubRepo() *mockSubscriptionRepository {
	return &mockSubscriptionRepository{
		vehicleTypes: []domain.VehicleType{
			{ID: "vt1", Nome: "Bicicletta"},
			{ID: "vt2", Nome: "Monopattino elettrico"},
		},
		subscriptions: []domain.Subscription{},
		activeMap:     make(map[string]bool),
	}
}

func TestSubscribe_Success(t *testing.T) {
	repo := newMockSubRepo()
	uc := usecase.NewSubscriptionUsecase(repo)

	sub, err := uc.Subscribe(context.Background(), "u1", "vt1", 3)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if sub.ID != "sub-test-id" {
		t.Errorf("expected sub ID 'sub-test-id', got %s", sub.ID)
	}
	if sub.Status != "" {
		// Status è impostato dal DB (default 'active'); il mock non lo imposta — ok.
	}
	if sub.EndDate.Before(time.Now().AddDate(0, 2, 28)) {
		t.Errorf("end_date troppo vicina: %v", sub.EndDate)
	}
}

func TestSubscribe_InvalidDuration(t *testing.T) {
	repo := newMockSubRepo()
	uc := usecase.NewSubscriptionUsecase(repo)

	_, err := uc.Subscribe(context.Background(), "u1", "vt1", 7)
	if !errors.Is(err, domain.ErrInvalidDuration) {
		t.Errorf("expected ErrInvalidDuration, got %v", err)
	}
}

func TestSubscribe_VehicleTypeNotFound(t *testing.T) {
	repo := newMockSubRepo()
	uc := usecase.NewSubscriptionUsecase(repo)

	_, err := uc.Subscribe(context.Background(), "u1", "vt-inesistente", 1)
	if !errors.Is(err, domain.ErrVehicleTypeNotFound) {
		t.Errorf("expected ErrVehicleTypeNotFound, got %v", err)
	}
}

func TestSubscribe_AlreadyActive(t *testing.T) {
	repo := newMockSubRepo()
	repo.activeMap["u1vt1"] = true
	uc := usecase.NewSubscriptionUsecase(repo)

	_, err := uc.Subscribe(context.Background(), "u1", "vt1", 1)
	if !errors.Is(err, domain.ErrSubscriptionAlreadyActive) {
		t.Errorf("expected ErrSubscriptionAlreadyActive, got %v", err)
	}
}

func TestList_ReturnsBothSubsAndTypes(t *testing.T) {
	repo := newMockSubRepo()
	repo.subscriptions = []domain.Subscription{
		{ID: "s1", UserID: "u1", VehicleTypeID: "vt1", VehicleTypeName: "Bicicletta", Status: "active"},
	}
	uc := usecase.NewSubscriptionUsecase(repo)

	subs, types, err := uc.List(context.Background(), "u1")
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if len(subs) != 1 {
		t.Errorf("expected 1 subscription, got %d", len(subs))
	}
	if len(types) != 2 {
		t.Errorf("expected 2 vehicle types, got %d", len(types))
	}
}
