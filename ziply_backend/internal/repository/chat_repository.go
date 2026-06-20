package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lorisforse/ziply_backend/internal/domain"
)

// ChatRepository gestisce la persistenza di sessioni e messaggi di chat.
type ChatRepository struct {
	pool *pgxpool.Pool
}

// NewChatRepository crea un nuovo ChatRepository.
func NewChatRepository(pool *pgxpool.Pool) *ChatRepository {
	return &ChatRepository{pool: pool}
}

// GetOpenSession restituisce la sessione non chiusa dell'utente, se esiste.
func (r *ChatRepository) GetOpenSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	s := &domain.ChatSession{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, created_at
		 FROM chat_sessions
		 WHERE user_id = $1 AND status != 'chiusa'
		 ORDER BY created_at DESC LIMIT 1`,
		userID,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return s, nil
}

// CreateSession crea una nuova sessione di chat per l'utente.
func (r *ChatRepository) CreateSession(ctx context.Context, userID string) (*domain.ChatSession, error) {
	s := &domain.ChatSession{}
	err := r.pool.QueryRow(ctx,
		`INSERT INTO chat_sessions (user_id) VALUES ($1)
		 RETURNING id, user_id, status, created_at`,
		userID,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt)
	if err != nil {
		return nil, err
	}
	return s, nil
}

// SetEscalated imposta la sessione in stato 'operatore'.
func (r *ChatRepository) SetEscalated(ctx context.Context, sessionID string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE chat_sessions SET status = 'operatore' WHERE id = $1`,
		sessionID,
	)
	return err
}

// AddMessage inserisce un messaggio nella sessione.
func (r *ChatRepository) AddMessage(ctx context.Context, msg *domain.ChatMessage) error {
	return r.pool.QueryRow(ctx,
		`INSERT INTO chat_messages (session_id, sender, text)
		 VALUES ($1, $2, $3)
		 RETURNING id, sent_at`,
		msg.SessionID, msg.Sender, msg.Text,
	).Scan(&msg.ID, &msg.SentAt)
}

// GetMessages restituisce tutti i messaggi della sessione in ordine cronologico.
func (r *ChatRepository) GetMessages(ctx context.Context, sessionID string) ([]domain.ChatMessage, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, session_id, sender, text, sent_at
		 FROM chat_messages
		 WHERE session_id = $1
		 ORDER BY sent_at ASC`,
		sessionID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var msgs []domain.ChatMessage
	for rows.Next() {
		var m domain.ChatMessage
		if err := rows.Scan(&m.ID, &m.SessionID, &m.Sender, &m.Text, &m.SentAt); err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}
	return msgs, rows.Err()
}

// GetSession restituisce una sessione per ID verificando che appartenga all'utente.
func (r *ChatRepository) GetSession(ctx context.Context, sessionID, userID string) (*domain.ChatSession, error) {
	s := &domain.ChatSession{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, created_at
		 FROM chat_sessions WHERE id = $1 AND user_id = $2`,
		sessionID, userID,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrChatSessionNotFound
	}
	if err != nil {
		return nil, err
	}
	return s, nil
}
