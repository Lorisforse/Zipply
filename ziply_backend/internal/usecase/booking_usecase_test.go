package usecase_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockBookingRepository struct {
	bookings     map[string]*domain.Booking
	cancelled    map[string]bool
	expired      map[string]bool
	scheduledErr error // se valorizzato, CreateScheduled lo restituisce
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

func (m *mockBookingRepository) CreateScheduled(ctx context.Context, userID, vehicleID string, scheduledStart, expiresAt time.Time) (*domain.Booking, float64, error) {
	if m.scheduledErr != nil {
		return nil, 0, m.scheduledErr
	}
	b := &domain.Booking{
		ID:             "bs-test-id",
		UserID:         userID,
		VehicleID:      vehicleID,
		ExpiresAt:      expiresAt,
		Status:         "attiva",
		ScheduledStart: &scheduledStart,
	}
	m.bookings[b.ID] = b
	// Preauth mock: 3.00€ fissi (la logica reale è nel repository + domain).
	return b, 3.00, nil
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

// UT.19 — prenotazione anticipata: validazione temporale e happy path.
func TestCreateScheduled_HappyPath(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	scheduledStart := time.Now().Add(2 * time.Hour)
	b, preAuth, err := uc.CreateScheduled(context.Background(), "u1", "v1", scheduledStart)
	if err != nil {
		t.Fatalf("expected no error, got %v", err)
	}
	if b.ID != "bs-test-id" {
		t.Errorf("unexpected booking ID: %s", b.ID)
	}
	if b.ScheduledStart == nil {
		t.Fatal("scheduledStart should be set")
	}
	if !b.ScheduledStart.Equal(scheduledStart) {
		t.Errorf("scheduledStart mismatch: got %v, want %v", b.ScheduledStart, scheduledStart)
	}
	// L'expiresAt deve essere scheduledStart + 30min.
	wantExpiry := scheduledStart.Add(domain.ScheduledGracePeriod)
	if !b.ExpiresAt.Equal(wantExpiry) {
		t.Errorf("expiresAt = %v, want %v", b.ExpiresAt, wantExpiry)
	}
	if preAuth <= 0 {
		t.Errorf("expected positive preAuth, got %.2f", preAuth)
	}
}

func TestCreateScheduled_TooSoon(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	// 10 minuti nel futuro: sotto la soglia minima di 15 min.
	scheduledStart := time.Now().Add(10 * time.Minute)
	_, _, err := uc.CreateScheduled(context.Background(), "u1", "v1", scheduledStart)
	if !errors.Is(err, domain.ErrScheduledStartTooSoon) {
		t.Errorf("expected ErrScheduledStartTooSoon, got %v", err)
	}
}

func TestCreateScheduled_TooFar(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	// Dopodomani: sempre oltre la fine del giorno successivo.
	scheduledStart := time.Now().AddDate(0, 0, 2)
	_, _, err := uc.CreateScheduled(context.Background(), "u1", "v1", scheduledStart)
	if !errors.Is(err, domain.ErrScheduledStartTooFar) {
		t.Errorf("expected ErrScheduledStartTooFar, got %v", err)
	}
}

func TestCreateScheduled_ExactBoundaries(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:  make(map[string]*domain.Booking),
		cancelled: make(map[string]bool),
		expired:   make(map[string]bool),
	}
	uc := usecase.NewBookingUsecase(repo)

	// 15 min esatti: al limite inferiore, deve passare.
	atMin := time.Now().Add(domain.MinScheduledAdvance + time.Second)
	_, _, err := uc.CreateScheduled(context.Background(), "u1", "v1", atMin)
	if err != nil {
		t.Errorf("at minimum boundary: expected no error, got %v", err)
	}

	// Fine del giorno successivo -1 min: al limite superiore, deve passare.
	n := time.Now()
	tomorrow := n.AddDate(0, 0, 1)
	atMax := time.Date(tomorrow.Year(), tomorrow.Month(), tomorrow.Day(), 23, 0, 0, 0, n.Location())
	_, _, err = uc.CreateScheduled(context.Background(), "u1", "v1", atMax)
	if err != nil {
		t.Errorf("at maximum boundary: expected no error, got %v", err)
	}
}

func TestCreateScheduled_RepoErrorPropagated(t *testing.T) {
	repo := &mockBookingRepository{
		bookings:     make(map[string]*domain.Booking),
		cancelled:    make(map[string]bool),
		expired:      make(map[string]bool),
		scheduledErr: domain.ErrVehicleTypeNotSchedulable,
	}
	uc := usecase.NewBookingUsecase(repo)

	scheduledStart := time.Now().Add(2 * time.Hour)
	_, _, err := uc.CreateScheduled(context.Background(), "u1", "v-scooter", scheduledStart)
	if !errors.Is(err, domain.ErrVehicleTypeNotSchedulable) {
		t.Errorf("expected ErrVehicleTypeNotSchedulable, got %v", err)
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
