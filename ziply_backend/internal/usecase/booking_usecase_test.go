package usecase_test

import (
	"context"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockBookingRepository struct {
	bookings  map[string]*domain.Booking
	cancelled map[string]bool
	expired   map[string]bool
}

func (m *mockBookingRepository) Create(ctx context.Context, userID, vehicleID, discountCode string, expiresAt time.Time) (*domain.Booking, error) {
	b := &domain.Booking{
		ID:        "b-test-id",
		UserID:    userID,
		VehicleID: vehicleID,
		ExpiresAt: expiresAt,
		Status:    "attiva",
	}
	m.bookings[b.ID] = b
	return b, nil
}

func (m *mockBookingRepository) CreateMulti(ctx context.Context, userID string, vehicleIDs []string, expiresAt time.Time) ([]*domain.Booking, string, error) {
	groupID := "g-test-id"
	bookings := make([]*domain.Booking, 0, len(vehicleIDs))
	for i, vid := range vehicleIDs {
		b := &domain.Booking{
			ID:        "bm-test-id-" + string(rune('a'+i)),
			UserID:    userID,
			VehicleID: vid,
			ExpiresAt: expiresAt,
			Status:    "attiva",
			GroupID:   &groupID,
		}
		m.bookings[b.ID] = b
		bookings = append(bookings, b)
	}
	return bookings, groupID, nil
}

func (m *mockBookingRepository) Expire(ctx context.Context, bookingID, vehicleID string) error {
	m.expired[bookingID] = true
	if b, ok := m.bookings[bookingID]; ok {
		b.Status = "scaduta"
	}
	return nil
}

func (m *mockBookingRepository) Cancel(ctx context.Context, bookingID, userID string) error {
	m.cancelled[bookingID] = true
	if b, ok := m.bookings[bookingID]; ok {
		b.Status = "annullata"
	}
	return nil
}

func TestBookingCreateAndCancel(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	// Test booking creation
	b, err := uc.Create(context.Background(), "u1", "v1", "")
	if err != nil {
		t.Fatalf("failed to create booking: %v", err)
	}
	if b.ID != "b-test-id" || b.Status != "attiva" {
		t.Fatal("invalid booking created")
	}

	// Test booking cancellation
	err = uc.Cancel(context.Background(), "u1", b.ID)
	if err != nil {
		t.Fatalf("failed to cancel booking: %v", err)
	}
	if !repo.cancelled[b.ID] {
		t.Fatal("booking was not marked cancelled in repository")
	}
}

// UT.16 — prenotazione multipla: più mezzi riservati insieme sotto un group_id.
func TestBookingCreateMulti(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	bookings, groupID, err := uc.CreateMulti(
		context.Background(), "u1", []string{"v1", "v2", "v3"})
	if err != nil {
		t.Fatalf("failed to create multi booking: %v", err)
	}
	if groupID != "g-test-id" {
		t.Fatalf("unexpected group id: %s", groupID)
	}
	if len(bookings) != 3 {
		t.Fatalf("expected 3 bookings, got %d", len(bookings))
	}
	for _, b := range bookings {
		if b.Status != "attiva" {
			t.Fatalf("expected status attiva, got %s", b.Status)
		}
		if b.GroupID == nil || *b.GroupID != groupID {
			t.Fatal("booking not linked to the group")
		}
	}
}
