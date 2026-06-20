package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lorisforse/ziply_backend/internal/domain"
)

// SubscriptionRepository gestisce la persistenza degli abbonamenti.
type SubscriptionRepository struct {
	pool *pgxpool.Pool
}

// NewSubscriptionRepository crea un nuovo SubscriptionRepository.
func NewSubscriptionRepository(pool *pgxpool.Pool) *SubscriptionRepository {
	return &SubscriptionRepository{pool: pool}
}

// ListVehicleTypes restituisce tutte le tipologie di mezzo disponibili.
func (r *SubscriptionRepository) ListVehicleTypes(ctx context.Context) ([]domain.VehicleType, error) {
	rows, err := r.pool.Query(ctx, `SELECT id, nome FROM vehicle_types ORDER BY nome`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	types := make([]domain.VehicleType, 0)
	for rows.Next() {
		var vt domain.VehicleType
		if err := rows.Scan(&vt.ID, &vt.Nome); err != nil {
			return nil, err
		}
		types = append(types, vt)
	}
	return types, rows.Err()
}

// VehicleTypeExists verifica che la tipologia di mezzo esista nel DB.
func (r *SubscriptionRepository) VehicleTypeExists(ctx context.Context, vehicleTypeID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM vehicle_types WHERE id = $1)`,
		vehicleTypeID,
	).Scan(&exists)
	return exists, err
}

// HasActive verifica se l'utente ha già un abbonamento attivo per la tipologia indicata.
func (r *SubscriptionRepository) HasActive(ctx context.Context, userID, vehicleTypeID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM subscriptions
			WHERE user_id = $1 AND vehicle_type_id = $2
			  AND status = 'active' AND end_date > NOW()
		)`,
		userID, vehicleTypeID,
	).Scan(&exists)
	return exists, err
}

// ListByUser restituisce tutti gli abbonamenti dell'utente, con il nome della tipologia.
func (r *SubscriptionRepository) ListByUser(ctx context.Context, userID string) ([]domain.Subscription, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT s.id, s.user_id, s.vehicle_type_id, vt.nome, s.start_date, s.end_date, s.status
		 FROM subscriptions s
		 JOIN vehicle_types vt ON vt.id = s.vehicle_type_id
		 WHERE s.user_id = $1
		 ORDER BY s.start_date DESC`,
		userID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	subs := make([]domain.Subscription, 0)
	for rows.Next() {
		var s domain.Subscription
		if err := rows.Scan(
			&s.ID, &s.UserID, &s.VehicleTypeID, &s.VehicleTypeName,
			&s.StartDate, &s.EndDate, &s.Status,
		); err != nil {
			return nil, err
		}
		subs = append(subs, s)
	}
	return subs, rows.Err()
}

// Create inserisce un nuovo abbonamento e popola ID e StartDate dalla risposta del DB.
func (r *SubscriptionRepository) Create(ctx context.Context, sub *domain.Subscription) error {
	return r.pool.QueryRow(ctx,
		`INSERT INTO subscriptions (user_id, vehicle_type_id, end_date, status)
		 VALUES ($1, $2, $3, 'active')
		 RETURNING id, start_date`,
		sub.UserID, sub.VehicleTypeID, sub.EndDate,
	).Scan(&sub.ID, &sub.StartDate)
}
