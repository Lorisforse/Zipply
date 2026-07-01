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

// GetSessionByID restituisce una sessione per ID senza filtrare per utente,
// per l'uso lato console operatore (OP.08) dove la coda e' condivisa.
func (r *ChatRepository) GetSessionByID(ctx context.Context, sessionID string) (*domain.ChatSession, error) {
	s := &domain.ChatSession{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, created_at FROM chat_sessions WHERE id = $1`,
		sessionID,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrChatSessionNotFound
	}
	if err != nil {
		return nil, err
	}
	return s, nil
}

// ListForOperator restituisce le sessioni non chiuse con i dati dell'utente e
// l'ultimo messaggio, per la console di supporto operatore (OP.08). Ordinate
// per data dell'ultimo messaggio, piu' recenti prima.
func (r *ChatRepository) ListForOperator(ctx context.Context) ([]domain.OperatorChatSession, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT s.id, s.user_id, u.nome || ' ' || u.cognome, u.email, s.status, s.created_at,
		        lm.text, lm.sent_at, lm.sender
		 FROM chat_sessions s
		 JOIN users u ON u.id = s.user_id
		 JOIN LATERAL (
		     SELECT text, sent_at, sender FROM chat_messages
		     WHERE session_id = s.id ORDER BY sent_at DESC LIMIT 1
		 ) lm ON true
		 WHERE s.status = 'operatore'
		 ORDER BY lm.sent_at DESC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	sessions := make([]domain.OperatorChatSession, 0)
	for rows.Next() {
		var s domain.OperatorChatSession
		if err := rows.Scan(
			&s.ID, &s.UserID, &s.UserName, &s.UserEmail, &s.Status, &s.CreatedAt,
			&s.LastMessage, &s.LastMessageAt, &s.LastMessageFrom,
		); err != nil {
			return nil, err
		}
		sessions = append(sessions, s)
	}
	return sessions, rows.Err()
}

// CloseSession imposta la sessione in stato 'chiusa' (OP.08).
func (r *ChatRepository) CloseSession(ctx context.Context, sessionID string) error {
	_, err := r.pool.Exec(ctx, `UPDATE chat_sessions SET status = 'chiusa' WHERE id = $1`, sessionID)
	return err
}
