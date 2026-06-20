package domain

import (
	"errors"
	"time"
)

// ChatSession rappresenta una sessione di supporto tra utente e bot/operatore.
type ChatSession struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Status    string    `json:"status"` // 'bot' | 'operatore' | 'chiusa'
	CreatedAt time.Time `json:"created_at"`
}

// ChatMessage rappresenta un singolo messaggio in una sessione di chat.
type ChatMessage struct {
	ID        string    `json:"id"`
	SessionID string    `json:"session_id"`
	Sender    string    `json:"sender"` // 'utente' | 'bot' | 'operatore'
	Text      string    `json:"text"`
	SentAt    time.Time `json:"sent_at"`
}

var (
	ErrChatSessionNotFound = errors.New("sessione di chat non trovata")
)
