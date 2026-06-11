// Package domain defines the core business entities and errors shared across layers.
package domain

import (
	"errors"
	"time"
)

// User represents a registered Ziply account stored in the users table.
// PasswordHash is never serialized in JSON responses.
type User struct {
	ID           string    `json:"id"`
	Nome         string    `json:"nome"`
	Cognome      string    `json:"cognome"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	Ruolo        string    `json:"ruolo"`
	CreatedAt    time.Time `json:"-"`
	UpdatedAt    time.Time `json:"-"`
}

// Domain errors returned by repositories and usecases.
var (
	ErrEmailAlreadyExists = errors.New("email già in uso")
	ErrInvalidCredentials = errors.New("email o password non corretti")
	ErrUserNotFound       = errors.New("utente non trovato")
)
