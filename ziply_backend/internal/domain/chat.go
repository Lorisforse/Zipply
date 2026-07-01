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

// OperatorChatSession arricchisce la sessione con i dati dell'utente e
// l'ultimo messaggio, per l'elenco delle chat nella console operatore
// (OP.08 / UC-??). Coda condivisa: nessun operatore assegnato, ogni
// operatore collegato vede le stesse sessioni e puo' risponderne una
// qualsiasi.
type OperatorChatSession struct {
	ID              string    `json:"id"`
	UserID          string    `json:"user_id"`
	UserName        string    `json:"user_name"`
	UserEmail       string    `json:"user_email"`
	Status          string    `json:"status"` // 'bot' | 'operatore' | 'chiusa'
	CreatedAt       time.Time `json:"created_at"`
	LastMessage     string    `json:"last_message"`
	LastMessageAt   time.Time `json:"last_message_at"`
	LastMessageFrom string    `json:"last_message_from"` // 'utente' | 'bot' | 'operatore'
}

const (
	ChatStatusBot       = "bot"
	ChatStatusOperatore = "operatore"
	ChatStatusChiusa    = "chiusa"
)

var (
	ErrChatSessionNotFound = errors.New("sessione di chat non trovata")
	ErrChatSessionClosed   = errors.New("sessione di chat chiusa")
)
