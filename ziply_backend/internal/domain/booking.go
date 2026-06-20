package domain

import (
	"errors"
	"time"
)

// Booking represents a vehicle reservation stored in the bookings table.
// Status is one of: 'attiva' | 'scaduta' | 'utilizzata' | 'annullata'.
type Booking struct {
	ID                  string
	UserID              string
	VehicleID           string
	CreatedAt           time.Time
	ExpiresAt           time.Time
	Status              string
	GroupID             *string // UT.16: prenotazione multipla; nil se singola
	PromotionID         *string
	PromotionDesc       *string
	PromotionPercentage *float64
}

// BookingHoldDuration is how long a reservation stays active before it expires.
const BookingHoldDuration = 15 * time.Minute

// UT.16 — vincoli della prenotazione multipla.
const (
	MaxGroupVehicles  = 5     // numero massimo di mezzi prenotabili insieme
	GroupRadiusMeters = 100.0 // distanza massima tra i mezzi selezionati
)

// Domain errors returned by the booking flow.
var (
	ErrVehicleNotAvailable   = errors.New("mezzo non disponibile")
	ErrActiveBookingExists   = errors.New("hai già una prenotazione attiva")
	ErrBookingNotCancellable = errors.New("prenotazione non annullabile")
	// UT.16 — errori della prenotazione multipla.
	ErrEmptyGroup            = errors.New("nessun mezzo selezionato")
	ErrTooManyVehicles       = errors.New("troppi mezzi selezionati")
	ErrVehiclesTooFar        = errors.New("mezzi troppo distanti tra loro")
	ErrVehicleTypeNotAllowed = errors.New("tipologia non ammessa per la prenotazione multipla")
)
