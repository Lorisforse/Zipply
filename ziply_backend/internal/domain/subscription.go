package domain

import (
	"errors"
	"time"
)

// VehicleType rappresenta una tipologia di mezzo (es. Bicicletta, Monopattino elettrico).
type VehicleType struct {
	ID   string `json:"id"`
	Nome string `json:"nome"`
}

// Subscription rappresenta un abbonamento attivo o storico di un utente per una tipologia di mezzo.
type Subscription struct {
	ID              string    `json:"id"`
	UserID          string    `json:"user_id"`
	VehicleTypeID   string    `json:"vehicle_type_id"`
	VehicleTypeName string    `json:"vehicle_type_name"`
	StartDate       time.Time `json:"start_date"`
	EndDate         time.Time `json:"end_date"`
	Status          string    `json:"status"` // 'active' | 'expired' | 'cancelled'
}

var (
	ErrSubscriptionAlreadyActive = errors.New("hai già un abbonamento attivo per questa tipologia di mezzo")
	ErrVehicleTypeNotFound       = errors.New("tipologia di mezzo non trovata")
	ErrInvalidDuration           = errors.New("durata non valida: scegli 1, 3, 6 o 12 mesi")
)
