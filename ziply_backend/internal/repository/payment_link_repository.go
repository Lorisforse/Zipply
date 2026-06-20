package repository

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lorisforse/ziply_backend/internal/domain"
)

// PaymentLinkRepository gestisce la persistenza dei link di pagamento.
type PaymentLinkRepository struct {
	pool *pgxpool.Pool
}

// NewPaymentLinkRepository crea un nuovo PaymentLinkRepository.
func NewPaymentLinkRepository(pool *pgxpool.Pool) *PaymentLinkRepository {
	return &PaymentLinkRepository{pool: pool}
}

// Create crea un nuovo link di pagamento.
func (r *PaymentLinkRepository) Create(ctx context.Context, rideID string, totalAmount float64, participants int, amountPerHead float64, validUntil time.Time) (*domain.PaymentLink, error) {
	pl := &domain.PaymentLink{
		RideID:        rideID,
		TotalAmount:   totalAmount,
		Participants:  participants,
		AmountPerHead: amountPerHead,
		ValidUntil:    validUntil,
		Status:        "active",
	}

	err := r.pool.QueryRow(ctx,
		`INSERT INTO payment_links (ride_id, total_amount, participants, amount_per_head, valid_until, status)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 RETURNING id`,
		pl.RideID, pl.TotalAmount, pl.Participants, pl.AmountPerHead, pl.ValidUntil, pl.Status,
	).Scan(&pl.ID)
	if err != nil {
		return nil, err
	}

	return pl, nil
}

// GetByID recupera un link di pagamento per ID, includendo il nome del prenotante.
func (r *PaymentLinkRepository) GetByID(ctx context.Context, id string) (*domain.PaymentLink, error) {
	pl := &domain.PaymentLink{}
	err := r.pool.QueryRow(ctx,
		`SELECT pl.id, pl.ride_id, pl.total_amount::float8, pl.participants, pl.amount_per_head::float8, pl.valid_until, pl.status,
		        u.nome || ' ' || u.cognome AS prenotante_name
		   FROM payment_links pl
		   JOIN rides r ON r.id = pl.ride_id
		   JOIN users u ON u.id = r.user_id
		  WHERE pl.id = $1`,
		id,
	).Scan(&pl.ID, &pl.RideID, &pl.TotalAmount, &pl.Participants, &pl.AmountPerHead, &pl.ValidUntil, &pl.Status, &pl.PrenotanteName)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrPaymentLinkNotFound
	}
	if err != nil {
		return nil, err
	}

	return pl, nil
}

// GetRideByID recupera una corsa per ID.
func (r *PaymentLinkRepository) GetRideByID(ctx context.Context, rideID string) (*domain.Ride, error) {
	ride := &domain.Ride{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, booking_id, user_id, vehicle_id, started_at, status, group_id
		   FROM rides WHERE id = $1`,
		rideID,
	).Scan(&ride.ID, &ride.BookingID, &ride.UserID, &ride.VehicleID, &ride.StartedAt, &ride.Status, &ride.GroupID)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrRideNotFound
	}
	if err != nil {
		return nil, err
	}
	return ride, nil
}

// GetGroupRidesDetails recupera il conteggio dei partecipanti e il costo totale per un noleggio di gruppo.
func (r *PaymentLinkRepository) GetGroupRidesDetails(ctx context.Context, groupID string) (int, float64, error) {
	var count int
	var total float64

	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*), COALESCE(SUM(total_cost::float8), 0.0)
		   FROM rides WHERE group_id = $1`,
		groupID,
	).Scan(&count, &total)
	if err != nil {
		return 0, 0, err
	}

	return count, total, nil
}

// Pay effettua la transazione di pagamento del link di pagamento.
func (r *PaymentLinkRepository) Pay(ctx context.Context, id string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var rideID string
	var amountPerHead float64
	var validUntil time.Time
	var status string

	err = tx.QueryRow(ctx,
		`SELECT ride_id, amount_per_head::float8, valid_until, status
		   FROM payment_links
		  WHERE id = $1
		    FOR UPDATE`,
		id,
	).Scan(&rideID, &amountPerHead, &validUntil, &status)

	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrPaymentLinkNotFound
	}
	if err != nil {
		return err
	}

	// Verifica se scaduto
	if status == "expired" || time.Now().After(validUntil) {
		if status != "expired" {
			_, _ = tx.Exec(ctx, `UPDATE payment_links SET status = 'expired' WHERE id = $1`, id)
			_ = tx.Commit(ctx)
		}
		return domain.ErrPaymentLinkExpired
	}

	if status == "paid" {
		return errors.New("quota già pagata")
	}

	// Cambia stato in paid
	_, err = tx.Exec(ctx, `UPDATE payment_links SET status = 'paid' WHERE id = $1`, id)
	if err != nil {
		return err
	}

	// Trova l'utente prenotante (user_id della corsa)
	var prenotanteID string
	err = tx.QueryRow(ctx, `SELECT user_id FROM rides WHERE id = $1`, rideID).Scan(&prenotanteID)
	if err != nil {
		return err
	}

	// Accredita il credito al prenotante
	_, err = tx.Exec(ctx, `UPDATE users SET credit_balance = credit_balance + $1 WHERE id = $2`, amountPerHead, prenotanteID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// GetUserCreditBalance recupera il saldo crediti di un utente.
func (r *PaymentLinkRepository) GetUserCreditBalance(ctx context.Context, userID string) (float64, error) {
	var balance float64
	err := r.pool.QueryRow(ctx, `SELECT credit_balance::float8 FROM users WHERE id = $1`, userID).Scan(&balance)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, domain.ErrUserNotFound
	}
	return balance, err
}
