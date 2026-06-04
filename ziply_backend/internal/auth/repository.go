package auth

import (
	"database/sql"
	"time"
)

type User struct {
	ID           string
	Nome         string
	Cognome      string
	Email        string
	PasswordHash string
	Ruolo        string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type Repository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) FindByEmail(email string) (*User, error) {
	u := &User{}
	err := r.db.QueryRow(
		`SELECT id, nome, cognome, email, password_hash, ruolo, created_at, updated_at
		 FROM users WHERE email = $1`,
		email,
	).Scan(&u.ID, &u.Nome, &u.Cognome, &u.Email, &u.PasswordHash, &u.Ruolo, &u.CreatedAt, &u.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return u, nil
}

func (r *Repository) Create(u *User) error {
	return r.db.QueryRow(
		`INSERT INTO users (nome, cognome, email, password_hash, ruolo)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, created_at, updated_at`,
		u.Nome, u.Cognome, u.Email, u.PasswordHash, u.Ruolo,
	).Scan(&u.ID, &u.CreatedAt, &u.UpdatedAt)
}
