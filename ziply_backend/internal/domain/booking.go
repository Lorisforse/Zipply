package domain

import (
	"errors"
	"math"
	"time"
)

// Booking represents a vehicle reservation stored in the bookings table.
// Status is one of: 'attiva' | 'scaduta' | 'utilizzata' | 'annullata'.
// BookingType is 'immediate' (default) or 'scheduled' (UT.19).
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
	// UT.19 — prenotazione anticipata.
	ScheduledStart *time.Time
}

// BookingHoldDuration is how long an immediate reservation stays active.
const BookingHoldDuration = 15 * time.Minute

// UT.16 — vincoli della prenotazione multipla.
const (
	MaxGroupVehicles  = 5     // numero massimo di mezzi prenotabili insieme
	GroupRadiusMeters = 100.0 // distanza massima tra i mezzi selezionati
)

// UT.19 — vincoli e costanti della prenotazione anticipata.
const (
	// MinScheduledAdvance: finestra minima (il mezzo deve essere almeno 15 min nel futuro).
	MinScheduledAdvance = 15 * time.Minute
	// MaxScheduledAdvance: finestra massima (max 24 ore in anticipo).
	MaxScheduledAdvance = 24 * time.Hour
	// ScheduledGracePeriod: tempo extra dopo scheduledStart prima che la prenotazione scada.
	ScheduledGracePeriod = 30 * time.Minute
	// BookingTypeScheduled identifica una prenotazione anticipata nella colonna booking_type.
	BookingTypeScheduled = "scheduled"
)

// ScheduledPreAuth calcola la preautorizzazione forfettaria con tariffa progressiva.
// hourlyRate è la tariffa oraria del mezzo (€/h); advanceHours è il numero di ore
// tra ora e scheduledStart (1–24). La formula scala linearmente: più si anticipa,
// più alta è la preautorizzazione.
func ScheduledPreAuth(hourlyRate, advanceHours float64) float64 {
	amount := hourlyRate * 0.5 * (1 + advanceHours/24)
	return math.Round(amount*100) / 100
}

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
	// UT.19 — errori della prenotazione anticipata.
	ErrVehicleTypeNotSchedulable = errors.New("la prenotazione anticipata è disponibile solo per bici e automobili")
	ErrScheduledStartTooSoon     = errors.New("l'orario deve essere almeno 15 minuti nel futuro")
	ErrScheduledStartTooFar      = errors.New("la prenotazione anticipata è possibile fino a 24 ore in anticipo")
)
