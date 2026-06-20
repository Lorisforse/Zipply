package domain

import (
	"errors"
	"time"
)

// PaymentLink rappresenta un link di pagamento associato a una quota di una corsa multipla.
type PaymentLink struct {
	ID            string    `json:"id"`
	RideID        string    `json:"ride_id"`
	TotalAmount   float64   `json:"total_amount"`
	Participants  int       `json:"participants"`
	AmountPerHead float64   `json:"amount_per_head"`
	ValidUntil    time.Time `json:"valid_until"`
	Status        string    `json:"status"` // 'active' | 'expired' | 'paid'
	PrenotanteName string   `json:"prenotante_name,omitempty"` // Campo extra per visualizzazione partecipante
}

var (
	ErrPaymentLinkNotFound = errors.New("link di pagamento non trovato")
	ErrPaymentLinkExpired  = errors.New("link di pagamento scaduto")
)
