package domain

import (
	"errors"
	"math"
	"time"
)

// DiscountCode rappresenta un codice sconto della tabella discount_codes,
// inserito manualmente dall'utente in fase di conferma prenotazione (UT.09).
type DiscountCode struct {
	ID         string
	Code       string
	Percentage float64
	ValidFrom  time.Time
	ValidUntil time.Time
	IsActive   bool
	MaxUses    int
	UsedCount  int
}

// Errori di dominio del flusso codice sconto.
var (
	// ErrDiscountNotFound: nessun codice sconto con il codice indicato.
	ErrDiscountNotFound = errors.New("codice sconto inesistente")
	// ErrDiscountNotValid: il codice esiste ma non è utilizzabile (disattivato,
	// non ancora valido, scaduto o esaurito negli utilizzi).
	ErrDiscountNotValid = errors.New("codice sconto non valido")
)

// Usable indica se il codice è applicabile all'istante now: deve essere attivo,
// dentro la finestra di validità e con utilizzi residui.
func (d DiscountCode) Usable(now time.Time) bool {
	if !d.IsActive {
		return false
	}
	if now.Before(d.ValidFrom) || now.After(d.ValidUntil) {
		return false
	}
	return d.UsedCount < d.MaxUses
}

// ApplyDiscount applica una percentuale di sconto a un costo, restituendo il
// costo scontato e l'importo dello sconto, entrambi arrotondati ai centesimi.
// Con percentuale o costo non positivi lo sconto è nullo e il costo invariato.
func ApplyDiscount(cost, percentage float64) (discounted, discount float64) {
	if percentage <= 0 || cost <= 0 {
		return cost, 0
	}
	discount = math.Round(cost*percentage) / 100
	discounted = math.Round((cost-discount)*100) / 100
	return discounted, discount
}
