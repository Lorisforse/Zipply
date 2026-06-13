package domain

import (
	"errors"
	"time"
)

// Ride represents a ride created when the user unlocks a reserved vehicle,
// stored in the rides table. Status is one of: 'attiva' | 'completata'.
type Ride struct {
	ID        string
	BookingID string
	UserID    string
	VehicleID string
	StartedAt time.Time
	Status    string
}

// Unlock methods accepted by POST /rides/unlock.
const (
	UnlockMethodProximity = "proximity"
	UnlockMethodQR        = "qr"
)

// Domain errors returned by the ride flow. Lo sblocco non richiede una
// prenotazione: basta che il mezzo sia disponibile (o già prenotato
// dall'utente stesso). Il 409 condivide ErrVehicleNotAvailable con il flusso
// di prenotazione.
var (
	ErrVehicleNotFound = errors.New("veicolo non trovato")
	ErrRideNotFound    = errors.New("corsa non trovata")
)
