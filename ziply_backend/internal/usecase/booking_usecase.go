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
	Create(ctx context.Context, userID, vehicleID, discountCode string, expiresAt time.Time) (*domain.Booking, error)
	CreateMulti(ctx context.Context, userID string, vehicleIDs []string, expiresAt time.Time) ([]*domain.Booking, string, error)
	CreateScheduled(ctx context.Context, userID, vehicleID string, scheduledStart, expiresAt time.Time) (*domain.Booking, float64, error)
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
// the automatic expiry of the booking once the hold elapses. discountCode è
// opzionale (UT.09): se valorizzato viene validato e collegato alla
// prenotazione perché lo sconto si applichi al costo a fine corsa.
func (uc *BookingUsecase) Create(ctx context.Context, userID, vehicleID, discountCode string) (*domain.Booking, error) {
	expiresAt := time.Now().Add(domain.BookingHoldDuration)

	booking, err := uc.bookings.Create(ctx, userID, vehicleID, discountCode, expiresAt)
	if err != nil {
		return nil, err
	}

	uc.scheduleExpiry(booking)
	return booking, nil
}

// CreateMulti riserva più mezzi insieme (UT.16) con scadenza 15 minuti e
// programma la scadenza automatica di ciascuna prenotazione del gruppo.
func (uc *BookingUsecase) CreateMulti(ctx context.Context, userID string, vehicleIDs []string) ([]*domain.Booking, string, error) {
	expiresAt := time.Now().Add(domain.BookingHoldDuration)

	bookings, groupID, err := uc.bookings.CreateMulti(ctx, userID, vehicleIDs, expiresAt)
	if err != nil {
		return nil, "", err
	}

	for _, b := range bookings {
		uc.scheduleExpiry(b)
	}
	return bookings, groupID, nil
}

// Cancel annulla la prenotazione attiva dell'utente e libera il mezzo. Il job
// di scadenza eventualmente già programmato diventa un no-op (Expire agisce
// solo su prenotazioni ancora 'attiva').
func (uc *BookingUsecase) Cancel(ctx context.Context, userID, bookingID string) error {
	return uc.bookings.Cancel(ctx, bookingID, userID)
}

// CreateScheduled crea una prenotazione anticipata (UT.19) per un mezzo che
// sarà utilizzato a scheduledStart, entro una finestra di 15 min – 24 h.
// Restituisce la prenotazione, la preautorizzazione forfettaria calcolata e
// schedula automaticamente la scadenza a scheduledStart + 30 min.
func (uc *BookingUsecase) CreateScheduled(ctx context.Context, userID, vehicleID string, scheduledStart time.Time) (*domain.Booking, float64, error) {
	advance := time.Until(scheduledStart)
	if advance < domain.MinScheduledAdvance {
		return nil, 0, domain.ErrScheduledStartTooSoon
	}
	if advance > domain.MaxScheduledAdvance {
		return nil, 0, domain.ErrScheduledStartTooFar
	}

	expiresAt := scheduledStart.Add(domain.ScheduledGracePeriod)
	booking, preAuth, err := uc.bookings.CreateScheduled(ctx, userID, vehicleID, scheduledStart, expiresAt)
	if err != nil {
		return nil, 0, err
	}

	uc.scheduleExpiry(booking)
	return booking, preAuth, nil
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
