package domain

import (
	"time"
)

// Promotion rappresenta una promozione automatica (es. sconto weekend, prima corsa)
// memorizzata nella tabella promotions (UT.21).
type Promotion struct {
	ID          string
	Description string
	Percentage  float64
	ValidFrom   time.Time
	ValidUntil  time.Time
	IsActive    bool
}

// Usable indica se la promozione è correntemente attiva e utilizzabile all'istante now.
func (p Promotion) Usable(now time.Time) bool {
	if !p.IsActive {
		return false
	}
	return !now.Before(p.ValidFrom) && !now.After(p.ValidUntil)
}
