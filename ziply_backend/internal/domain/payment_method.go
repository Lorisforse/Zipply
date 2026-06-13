package domain

import (
	"errors"
	"time"
)

// PaymentMethod represents a saved (mock) payment card stored in the
// payment_methods table. Only the last four digits and the expiry are
// persisted: the full PAN and the CVV never reach the backend.
type PaymentMethod struct {
	ID           string
	UserID       string
	CardLastFour string
	CardExpiry   string
	IsDefault    bool
	CreatedAt    time.Time
}

// Domain errors returned by the payment method flow.
var (
	ErrPaymentMethodNotFound = errors.New("metodo di pagamento non trovato")
)
