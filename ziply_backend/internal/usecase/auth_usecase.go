// Package usecase contains the application business logic for authentication.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"net/mail"
	"strings"

	"golang.org/x/crypto/bcrypt"

	"github.com/lorisforse/ziply_backend/internal/domain"
	appjwt "github.com/lorisforse/ziply_backend/pkg/jwt"
)

// bcryptCost is the work factor used to hash passwords.
const bcryptCost = 12

// minPasswordLen is the minimum accepted password length.
const minPasswordLen = 8

// UserRepository abstracts the persistence of users required by the auth flows.
type UserRepository interface {
	FindByEmail(ctx context.Context, email string) (*domain.User, error)
	Create(ctx context.Context, u *domain.User) error
}

// ValidationError describes a request payload that failed validation.
type ValidationError struct {
	Details string
}

// Error returns the validation failure details.
func (e *ValidationError) Error() string { return e.Details }

// AuthUsecase implements the registration and login flows.
type AuthUsecase struct {
	users UserRepository
}

// NewAuthUsecase creates an AuthUsecase backed by the given repository.
func NewAuthUsecase(users UserRepository) *AuthUsecase {
	return &AuthUsecase{users: users}
}

// Register validates the input, stores a new user with role 'utente', and returns it with a signed JWT.
func (uc *AuthUsecase) Register(ctx context.Context, nome, cognome, email, password string) (*domain.User, string, error) {
	nome = strings.TrimSpace(nome)
	cognome = strings.TrimSpace(cognome)
	email = strings.TrimSpace(email)

	if err := validateRegistration(nome, cognome, email, password); err != nil {
		return nil, "", err
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	if err != nil {
		return nil, "", fmt.Errorf("hashing password: %w", err)
	}

	u := &domain.User{
		Nome:         nome,
		Cognome:      cognome,
		Email:        email,
		PasswordHash: string(hash),
		Ruolo:        "utente",
	}
	if err := uc.users.Create(ctx, u); err != nil {
		return nil, "", err
	}

	token, err := appjwt.GenerateToken(u.ID, u.Email, u.Ruolo)
	if err != nil {
		return nil, "", fmt.Errorf("signing token: %w", err)
	}
	return u, token, nil
}

// Login verifies the credentials and returns the matching user with a signed JWT.
func (uc *AuthUsecase) Login(ctx context.Context, email, password string) (*domain.User, string, error) {
	email = strings.TrimSpace(email)
	if email == "" || password == "" {
		return nil, "", &ValidationError{Details: "email e password sono obbligatorie"}
	}

	u, err := uc.users.FindByEmail(ctx, email)
	if errors.Is(err, domain.ErrUserNotFound) {
		return nil, "", domain.ErrInvalidCredentials
	}
	if err != nil {
		return nil, "", err
	}

	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)) != nil {
		return nil, "", domain.ErrInvalidCredentials
	}

	token, err := appjwt.GenerateToken(u.ID, u.Email, u.Ruolo)
	if err != nil {
		return nil, "", fmt.Errorf("signing token: %w", err)
	}
	return u, token, nil
}

// validateRegistration checks the registration fields and returns a ValidationError on failure.
func validateRegistration(nome, cognome, email, password string) error {
	switch {
	case nome == "":
		return &ValidationError{Details: "il nome è obbligatorio"}
	case cognome == "":
		return &ValidationError{Details: "il cognome è obbligatorio"}
	case email == "":
		return &ValidationError{Details: "l'email è obbligatoria"}
	case len(password) < minPasswordLen:
		return &ValidationError{Details: "la password deve avere almeno 8 caratteri"}
	}
	if _, err := mail.ParseAddress(email); err != nil {
		return &ValidationError{Details: "email non valida"}
	}
	return nil
}
