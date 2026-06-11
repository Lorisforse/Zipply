// Package repository implements the PostgreSQL persistence layer for domain entities.
package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// uniqueViolation is the PostgreSQL error code for UNIQUE constraint violations.
const uniqueViolation = "23505"

// UserRepository provides access to the users table.
type UserRepository struct {
	pool *pgxpool.Pool
}

// NewUserRepository creates a UserRepository backed by the given connection pool.
func NewUserRepository(pool *pgxpool.Pool) *UserRepository {
	return &UserRepository{pool: pool}
}

// FindByEmail returns the user with the given email, or domain.ErrUserNotFound.
func (r *UserRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	u := &domain.User{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, nome, cognome, email, password_hash, ruolo, created_at, updated_at
		 FROM users WHERE email = $1`,
		email,
	).Scan(&u.ID, &u.Nome, &u.Cognome, &u.Email, &u.PasswordHash, &u.Ruolo, &u.CreatedAt, &u.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	return u, nil
}

// Create inserts a new user, filling the generated id and timestamps; returns domain.ErrEmailAlreadyExists on duplicate email.
func (r *UserRepository) Create(ctx context.Context, u *domain.User) error {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO users (nome, cognome, email, password_hash, ruolo)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, created_at, updated_at`,
		u.Nome, u.Cognome, u.Email, u.PasswordHash, u.Ruolo,
	).Scan(&u.ID, &u.CreatedAt, &u.UpdatedAt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return domain.ErrEmailAlreadyExists
	}
	return err
}
