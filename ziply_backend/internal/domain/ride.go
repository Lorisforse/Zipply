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

// avgUrbanSpeedKmh è la velocità media urbana assunta per stimare la distanza
// percorsa (le corse non sono tracciate via GPS), usata per la stima di CO2.
const avgUrbanSpeedKmh = 15.0

// freeRideThresholdSeconds: le corse sotto questa soglia non vengono addebitate.
const freeRideThresholdSeconds = 20

// RideSummary raccoglie i valori di addebito calcolati al termine di una corsa.
type RideSummary struct {
	DurationMinutes int
	TotalCost       float64
	Co2SavedGrams   float64
}

// ChargedMinutes applica la regola di addebito a scatti di minuto: nessun
// addebito sotto i 20 secondi, altrimenti minuti arrotondati per eccesso.
func ChargedMinutes(d time.Duration) int {
	secs := int(d.Seconds())
	if secs < freeRideThresholdSeconds {
		return 0
	}
	return (secs + 59) / 60
}

// EstimateCo2SavedGrams stima i grammi di CO2 risparmiati: distanza stimata
// (velocità media urbana × durata) per il fattore di CO2 risparmiata al km
// della tipologia di mezzo.
func EstimateCo2SavedGrams(d time.Duration, co2SavedPerKm float64) float64 {
	km := avgUrbanSpeedKmh * d.Hours()
	return km * co2SavedPerKm
}
