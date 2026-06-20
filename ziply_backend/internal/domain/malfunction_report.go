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

var (
	ErrInvalidProblemType      = errors.New("tipo di problema non valido")
	ErrMalfunctionReportNotFound = errors.New("segnalazione di malfunzionamento non trovata")
)
