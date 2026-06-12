package domain

import (
	"errors"
	"time"
)

// Booking represents a vehicle reservation stored in the bookings table.
// Status is one of: 'attiva' | 'scaduta' | 'utilizzata' | 'annullata'.
type Booking struct {
	ID        string
	UserID    string
	VehicleID string
	CreatedAt time.Time
	ExpiresAt time.Time
	Status    string
}

// BookingHoldDuration is how long a reservation stays active before it expires.
const BookingHoldDuration = 15 * time.Minute

// Domain errors returned by the booking flow.
var (
	ErrVehicleNotAvailable = errors.New("mezzo non disponibile")
	ErrActiveBookingExists = errors.New("hai già una prenotazione attiva")
)
