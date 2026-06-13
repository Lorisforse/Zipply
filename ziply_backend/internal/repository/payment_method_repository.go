package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// PaymentMethodRepository provides access to the payment_methods table.
type PaymentMethodRepository struct {
	pool *pgxpool.Pool
}

// NewPaymentMethodRepository creates a PaymentMethodRepository backed by the given connection pool.
func NewPaymentMethodRepository(pool *pgxpool.Pool) *PaymentMethodRepository {
	return &PaymentMethodRepository{pool: pool}
}

// Create inserts a new payment method for the user. When isDefault is true it
// first clears the default flag from the user's other cards, so that at most
// one card stays default; the whole operation runs in a single transaction.
func (r *PaymentMethodRepository) Create(ctx context.Context, userID, cardLastFour, cardExpiry string, isDefault bool) (*domain.PaymentMethod, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	if isDefault {
		if _, err := tx.Exec(ctx,
			`UPDATE payment_methods SET is_default = false WHERE user_id = $1`,
			userID,
		); err != nil {
			return nil, err
		}
	}

	pm := &domain.PaymentMethod{UserID: userID}
	err = tx.QueryRow(ctx,
		`INSERT INTO payment_methods (user_id, card_last_four, card_expiry, is_default)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, card_last_four, card_expiry, is_default, created_at`,
		userID, cardLastFour, cardExpiry, isDefault,
	).Scan(&pm.ID, &pm.CardLastFour, &pm.CardExpiry, &pm.IsDefault, &pm.CreatedAt)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return pm, nil
}

// ListByUser returns all the payment methods of the given user, with the
// default card first and the most recent ones before the older ones.
func (r *PaymentMethodRepository) ListByUser(ctx context.Context, userID string) ([]domain.PaymentMethod, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, card_last_four, card_expiry, is_default, created_at
		 FROM payment_methods
		 WHERE user_id = $1
		 ORDER BY is_default DESC, created_at DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	methods := make([]domain.PaymentMethod, 0)
	for rows.Next() {
		var pm domain.PaymentMethod
		pm.UserID = userID
		if err := rows.Scan(
			&pm.ID, &pm.CardLastFour, &pm.CardExpiry, &pm.IsDefault, &pm.CreatedAt,
		); err != nil {
			return nil, err
		}
		methods = append(methods, pm)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return methods, nil
}

// Delete removes the user's payment method with the given id. Returns
// domain.ErrPaymentMethodNotFound when no card with that id belongs to the user.
func (r *PaymentMethodRepository) Delete(ctx context.Context, id, userID string) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM payment_methods WHERE id = $1 AND user_id = $2`,
		id, userID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrPaymentMethodNotFound
	}
	return nil
}
