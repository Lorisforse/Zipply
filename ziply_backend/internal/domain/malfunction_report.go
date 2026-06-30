package domain

import (
	"errors"
	"time"
)

// MalfunctionReport rappresenta una segnalazione di malfunzionamento associata a un mezzo ed a una corsa conclusa.
type MalfunctionReport struct {
	ID             string    `json:"id"`
	UserID         string    `json:"user_id"`
	VehicleID      string    `json:"vehicle_id"`
	RideID         string    `json:"ride_id"`
	ProblemType    string    `json:"problem_type"`
	Description    string    `json:"description"`
	AttachmentURLs string    `json:"attachment_urls"`
	CreatedAt      time.Time `json:"created_at"`
	Status         string    `json:"status"` // 'in_attesa' | 'preso_in_carico' | 'risolto'
}

// Stati di lavorazione di una segnalazione (enum E-05 MalfunctionStatus).
const (
	MalfunctionStatusInAttesa      = "in_attesa"
	MalfunctionStatusPresoInCarico = "preso_in_carico"
	MalfunctionStatusRisolto       = "risolto"
)

// OperatorMalfunctionReport arricchisce la segnalazione con i dati del mezzo
// coinvolto, per la visualizzazione nella dashboard operatore (OP.03 / UC-26).
type OperatorMalfunctionReport struct {
	ID           string    `json:"id"`
	VehicleID    string    `json:"vehicle_id"`
	VehicleQR    string    `json:"vehicle_qr"`
	VehicleType  string    `json:"vehicle_type"`
	Latitude     float64   `json:"latitude"`
	Longitude    float64   `json:"longitude"`
	ProblemType  string    `json:"problem_type"`
	Description  string    `json:"description"`
	Source       string    `json:"source"` // 'utente' | 'sensore'
	CreatedAt    time.Time `json:"created_at"`
	Status       string    `json:"status"`
}

var (
	ErrInvalidProblemType        = errors.New("tipo di problema non valido")
	ErrMalfunctionReportNotFound = errors.New("segnalazione di malfunzionamento non trovata")
	ErrInvalidMalfunctionStatus  = errors.New("stato segnalazione non valido")
)

// IsValidMalfunctionStatus indica se s è uno stato ammesso per una segnalazione.
func IsValidMalfunctionStatus(s string) bool {
	switch s {
	case MalfunctionStatusInAttesa, MalfunctionStatusPresoInCarico, MalfunctionStatusRisolto:
		return true
	default:
		return false
	}
}
