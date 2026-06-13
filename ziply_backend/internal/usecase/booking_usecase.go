package usecase

import (
	"context"
	"log"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// expiryJobTimeout bounds the background transaction that frees an expired hold.
const expiryJobTimeout = 10 * time.Second

// BookingRepository abstracts the persistence of bookings required by the reservation flow.
type BookingRepository interface {
	Create(ctx context.Context, userID, vehicleID string, expiresAt time.Time) (*domain.Booking, error)
	Expire(ctx context.Context, bookingID, vehicleID string) error
	Cancel(ctx context.Context, bookingID, userID string) error
}

// BookingUsecase implements the vehicle reservation flow.
type BookingUsecase struct {
	bookings BookingRepository
}

// NewBookingUsecase creates a BookingUsecase backed by the given repository.
func NewBookingUsecase(bookings BookingRepository) *BookingUsecase {
	return &BookingUsecase{bookings: bookings}
}

// Create reserves the vehicle for the user with a 15-minute hold and schedules
// the automatic expiry of the booking once the hold elapses.
func (uc *BookingUsecase) Create(ctx context.Context, userID, vehicleID string) (*domain.Booking, error) {
	expiresAt := time.Now().Add(domain.BookingHoldDuration)

	booking, err := uc.bookings.Create(ctx, userID, vehicleID, expiresAt)
	if err != nil {
		return nil, err
	}

	uc.scheduleExpiry(booking)
	return booking, nil
}

// Cancel annulla la prenotazione attiva dell'utente e libera il mezzo. Il job
// di scadenza eventualmente già programmato diventa un no-op (Expire agisce
// solo su prenotazioni ancora 'attiva').
func (uc *BookingUsecase) Cancel(ctx context.Context, userID, bookingID string) error {
	return uc.bookings.Cancel(ctx, bookingID, userID)
}

// scheduleExpiry fires once the hold elapses and, if the booking is still
// active, marks it expired and frees the vehicle. It runs on its own
// background context, detached from the originating request.
func (uc *BookingUsecase) scheduleExpiry(b *domain.Booking) {
	time.AfterFunc(time.Until(b.ExpiresAt), func() {
		ctx, cancel := context.WithTimeout(context.Background(), expiryJobTimeout)
		defer cancel()
		if err := uc.bookings.Expire(ctx, b.ID, b.VehicleID); err != nil {
			log.Printf("[BOOKINGS] expiry of booking %s failed: %v", b.ID, err)
		}
	})
}
