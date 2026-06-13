package repository

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// RideRepository provides access to the rides table and the unlock flow.
type RideRepository struct {
	pool *pgxpool.Pool
}

// NewRideRepository creates a RideRepository backed by the given connection pool.
func NewRideRepository(pool *pgxpool.Pool) *RideRepository {
	return &RideRepository{pool: pool}
}

// Unlock atomically starts a ride on the vehicle reserved by the user. Exactly
// one of vehicleID / qrCode identifies the vehicle: proximity passes the id, the
// QR flow passes the code printed on the physical vehicle. In a single
// transaction it locks the vehicle row, resolves it, verifies the user holds an
// active and non-expired booking on it, then inserts the ride ('attiva'), marks
// the booking 'utilizzata' and the vehicle 'in_uso'.
//
// Returns domain.ErrVehicleNotFound when the vehicle does not exist,
// domain.ErrNoActiveBooking when the user has no active booking on it and
// domain.ErrBookingExpired when the booking is active but its hold has elapsed.
func (r *RideRepository) Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Lock and resolve the vehicle, by id (proximity) or by qr_code (QR scan).
	var resolvedVehicleID string
	if qrCode != "" {
		err = tx.QueryRow(ctx,
			`SELECT id FROM vehicles WHERE qr_code = $1 FOR UPDATE`, qrCode,
		).Scan(&resolvedVehicleID)
	} else {
		err = tx.QueryRow(ctx,
			`SELECT id FROM vehicles WHERE id = $1 FOR UPDATE`, vehicleID,
		).Scan(&resolvedVehicleID)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrVehicleNotFound
	}
	if err != nil {
		return nil, err
	}

	// Find the user's active booking on this vehicle and lock it. An expired
	// hold (expires_at <= now) is rejected distinctly from "no booking at all".
	var bookingID string
	var expiresAt time.Time
	err = tx.QueryRow(ctx,
		`SELECT id, expires_at FROM bookings
		 WHERE user_id = $1 AND vehicle_id = $2 AND status = 'attiva'
		 ORDER BY created_at DESC
		 LIMIT 1
		 FOR UPDATE`,
		userID, resolvedVehicleID,
	).Scan(&bookingID, &expiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrNoActiveBooking
	}
	if err != nil {
		return nil, err
	}
	if !expiresAt.After(time.Now()) {
		return nil, domain.ErrBookingExpired
	}

	// Create the ride.
	ride := &domain.Ride{BookingID: bookingID, UserID: userID, VehicleID: resolvedVehicleID}
	err = tx.QueryRow(ctx,
		`INSERT INTO rides (booking_id, user_id, vehicle_id, started_at, status)
		 VALUES ($1, $2, $3, NOW(), 'attiva')
		 RETURNING id, started_at, status`,
		bookingID, userID, resolvedVehicleID,
	).Scan(&ride.ID, &ride.StartedAt, &ride.Status)
	if err != nil {
		return nil, err
	}

	// Mark the booking used.
	if _, err := tx.Exec(ctx,
		`UPDATE bookings SET status = 'utilizzata' WHERE id = $1`,
		bookingID,
	); err != nil {
		return nil, err
	}

	// Mark the vehicle in use.
	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'in_uso', updated_at = NOW() WHERE id = $1`,
		resolvedVehicleID,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return ride, nil
}
