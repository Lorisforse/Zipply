package repository

import (
	"context"
	"errors"
	"math"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// BookingRepository provides access to the bookings table.
type BookingRepository struct {
	pool *pgxpool.Pool
}

// NewBookingRepository creates a BookingRepository backed by the given connection pool.
func NewBookingRepository(pool *pgxpool.Pool) *BookingRepository {
	return &BookingRepository{pool: pool}
}

// Create atomically reserves a vehicle for the user. In a single transaction it
// locks the vehicle row, verifies it is available, rejects the request when the
// user already holds an active booking, inserts the booking and marks the
// vehicle 'prenotato'. Returns domain.ErrVehicleNotAvailable or
// domain.ErrActiveBookingExists when the preconditions are not met.
//
// UT.09 — discountCode è opzionale: se valorizzato viene validato (esistenza,
// validità, utilizzi residui) e collegato alla prenotazione (discount_code_id),
// così lo sconto sarà applicato al costo a fine corsa. Un codice non valido fa
// fallire la prenotazione con domain.ErrDiscountNotFound / ErrDiscountNotValid.
func (r *BookingRepository) Create(ctx context.Context, userID, vehicleID, discountCode string, expiresAt time.Time) (*domain.Booking, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Lock the vehicle row and verify availability.
	var status string
	err = tx.QueryRow(ctx, `SELECT status FROM vehicles WHERE id = $1 FOR UPDATE`, vehicleID).Scan(&status)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrVehicleNotAvailable
	}
	if err != nil {
		return nil, err
	}
	if status != "disponibile" {
		return nil, domain.ErrVehicleNotAvailable
	}

	// Reject when the user already holds an active, non-expired booking.
	var hasActive bool
	err = tx.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM bookings
			WHERE user_id = $1 AND status = 'attiva' AND expires_at > NOW()
		)`,
		userID,
	).Scan(&hasActive)
	if err != nil {
		return nil, err
	}
	if hasActive {
		return nil, domain.ErrActiveBookingExists
	}

	// UT.09 — risolve l'eventuale codice sconto e lo collega alla prenotazione.
	var discountID *string
	if strings.TrimSpace(discountCode) != "" {
		id, err := resolveDiscount(ctx, tx, discountCode)
		if err != nil {
			return nil, err
		}
		discountID = &id
	}

	// UT.21 — ricerca di una promozione attiva applicabile.
	var promotionID, promotionDesc *string
	var promotionPercentage *float64
	var pID, pDesc string
	var pPct float64
	err = tx.QueryRow(ctx,
		`SELECT id, description, percentage::float8
		   FROM promotions
		  WHERE is_active = TRUE AND NOW() BETWEEN valid_from AND valid_until
		  ORDER BY percentage DESC
		  LIMIT 1`,
	).Scan(&pID, &pDesc, &pPct)
	if err == nil {
		promotionID = &pID
		promotionDesc = &pDesc
		promotionPercentage = &pPct
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	// Insert the booking.
	b := &domain.Booking{UserID: userID, VehicleID: vehicleID}
	err = tx.QueryRow(ctx,
		`INSERT INTO bookings (user_id, vehicle_id, expires_at, status, discount_code_id, promotion_id)
		 VALUES ($1, $2, $3, 'attiva', $4, $5)
		 RETURNING id, created_at, expires_at, status`,
		userID, vehicleID, expiresAt, discountID, promotionID,
	).Scan(&b.ID, &b.CreatedAt, &b.ExpiresAt, &b.Status)
	if err != nil {
		return nil, err
	}

	b.PromotionID = promotionID
	b.PromotionDesc = promotionDesc
	b.PromotionPercentage = promotionPercentage

	// Mark the vehicle reserved.
	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'prenotato', updated_at = NOW() WHERE id = $1`,
		vehicleID,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return b, nil
}

// CreateMulti riserva più mezzi insieme (UT.16 prenotazione multipla) in
// un'unica transazione, sotto un group_id condiviso. Vincoli: da 1 a
// domain.MaxGroupVehicles mezzi, solo bici/monopattini, ciascuno entro
// domain.GroupRadiusMeters dal primo selezionato; l'utente non deve avere
// prenotazioni attive. Ritorna le prenotazioni create e il group_id, oppure un
// errore di dominio (ErrTooManyVehicles, ErrVehiclesTooFar,
// ErrVehicleTypeNotAllowed, ErrVehicleNotAvailable, ErrActiveBookingExists).
func (r *BookingRepository) CreateMulti(ctx context.Context, userID string, vehicleIDs []string, expiresAt time.Time) ([]*domain.Booking, string, error) {
	if len(vehicleIDs) == 0 {
		return nil, "", domain.ErrEmptyGroup
	}
	if len(vehicleIDs) > domain.MaxGroupVehicles {
		return nil, "", domain.ErrTooManyVehicles
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, "", err
	}
	defer tx.Rollback(ctx)

	// Rifiuta se l'utente ha già una prenotazione attiva non scaduta.
	var hasActive bool
	if err := tx.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM bookings
			WHERE user_id = $1 AND status = 'attiva' AND expires_at > NOW()
		)`,
		userID,
	).Scan(&hasActive); err != nil {
		return nil, "", err
	}
	if hasActive {
		return nil, "", domain.ErrActiveBookingExists
	}

	// Blocca e carica ogni mezzo (stato, tipologia, coordinate), deduplicando.
	type vrow struct {
		id, status, typ string
		lat, lng        float64
	}
	loaded := make([]vrow, 0, len(vehicleIDs))
	seen := make(map[string]bool, len(vehicleIDs))
	for _, vid := range vehicleIDs {
		if seen[vid] {
			continue
		}
		seen[vid] = true

		var vr vrow
		err := tx.QueryRow(ctx,
			`SELECT v.id, v.status, vt.nome, v.latitude::float8, v.longitude::float8
			   FROM vehicles v
			   JOIN vehicle_types vt ON vt.id = v.type_id
			  WHERE v.id = $1 FOR UPDATE OF v`,
			vid,
		).Scan(&vr.id, &vr.status, &vr.typ, &vr.lat, &vr.lng)
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", domain.ErrVehicleNotAvailable
		}
		if err != nil {
			return nil, "", err
		}
		if vr.status != "disponibile" {
			return nil, "", domain.ErrVehicleNotAvailable
		}
		// Solo bici e monopattini: le auto sono escluse dalla prenotazione multipla.
		if vr.typ == "Automobile elettrica" {
			return nil, "", domain.ErrVehicleTypeNotAllowed
		}
		loaded = append(loaded, vr)
	}
	if len(loaded) == 0 {
		return nil, "", domain.ErrEmptyGroup
	}

	// Ogni mezzo entro il raggio massimo dal primo selezionato.
	for i := 1; i < len(loaded); i++ {
		if haversineMeters(loaded[0].lat, loaded[0].lng, loaded[i].lat, loaded[i].lng) > domain.GroupRadiusMeters {
			return nil, "", domain.ErrVehiclesTooFar
		}
	}

	// Identificativo di gruppo condiviso da tutte le prenotazioni.
	var groupID string
	if err := tx.QueryRow(ctx, `SELECT gen_random_uuid()`).Scan(&groupID); err != nil {
		return nil, "", err
	}

	bookings := make([]*domain.Booking, 0, len(loaded))
	for _, vr := range loaded {
		b := &domain.Booking{UserID: userID, VehicleID: vr.id, GroupID: &groupID}
		if err := tx.QueryRow(ctx,
			`INSERT INTO bookings (user_id, vehicle_id, expires_at, status, group_id)
			 VALUES ($1, $2, $3, 'attiva', $4)
			 RETURNING id, created_at, expires_at, status`,
			userID, vr.id, expiresAt, groupID,
		).Scan(&b.ID, &b.CreatedAt, &b.ExpiresAt, &b.Status); err != nil {
			return nil, "", err
		}
		if _, err := tx.Exec(ctx,
			`UPDATE vehicles SET status = 'prenotato', updated_at = NOW() WHERE id = $1`,
			vr.id,
		); err != nil {
			return nil, "", err
		}
		bookings = append(bookings, b)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, "", err
	}
	return bookings, groupID, nil
}

// haversineMeters restituisce la distanza in metri tra due coordinate geografiche.
func haversineMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const earthRadiusM = 6371000.0
	rad := math.Pi / 180
	dLat := (lat2 - lat1) * rad
	dLng := (lng2 - lng1) * rad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return 2 * earthRadiusM * math.Asin(math.Sqrt(a))
}

// Expire marks the booking as 'scaduta' and frees its vehicle, but only while
// the booking is still 'attiva'. When the booking has meanwhile been used or
// cancelled the vehicle is left untouched.
func (r *BookingRepository) Expire(ctx context.Context, bookingID, vehicleID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	tag, err := tx.Exec(ctx,
		`UPDATE bookings SET status = 'scaduta' WHERE id = $1 AND status = 'attiva'`,
		bookingID,
	)
	if err != nil {
		return err
	}
	// Booking no longer active (utilizzata/annullata): leave the vehicle as-is.
	if tag.RowsAffected() == 0 {
		return tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'disponibile', updated_at = NOW() WHERE id = $1`,
		vehicleID,
	); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// Cancel marks the user's active booking as 'annullata' and frees its vehicle,
// in a single transaction. Returns domain.ErrBookingNotCancellable when no
// active booking with the given id belongs to the user.
func (r *BookingRepository) Cancel(ctx context.Context, bookingID, userID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// Lock the booking and ensure it is the user's and still active.
	var vehicleID string
	err = tx.QueryRow(ctx,
		`SELECT vehicle_id FROM bookings
		 WHERE id = $1 AND user_id = $2 AND status = 'attiva' FOR UPDATE`,
		bookingID, userID,
	).Scan(&vehicleID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrBookingNotCancellable
	}
	if err != nil {
		return err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE bookings SET status = 'annullata' WHERE id = $1`,
		bookingID,
	); err != nil {
		return err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'disponibile', updated_at = NOW() WHERE id = $1`,
		vehicleID,
	); err != nil {
		return err
	}

	return tx.Commit(ctx)
}
