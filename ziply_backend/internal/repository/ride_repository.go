package repository

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// RideRepository provides access to the rides table and the unlock/end flow.
type RideRepository struct {
	pool *pgxpool.Pool
}

// NewRideRepository creates a RideRepository backed by the given connection pool.
func NewRideRepository(pool *pgxpool.Pool) *RideRepository {
	return &RideRepository{pool: pool}
}

// Unlock atomically starts a ride on a vehicle, senza richiedere una
// prenotazione: l'utente può arrivare davanti al mezzo e sbloccarlo. Exactly
// one of vehicleID / qrCode identifies the vehicle: proximity passes the id, the
// QR flow passes the code printed on the physical vehicle.
//
// In una singola transazione blocca e risolve il veicolo, poi:
//   - se l'utente ha già una prenotazione 'attiva' su quel mezzo, la consuma;
//   - altrimenti pretende che il mezzo sia 'disponibile' e crea al volo una
//     prenotazione implicita (subito 'utilizzata') per ancorare la corsa.
//
// Infine inserisce la corsa ('attiva') e porta il veicolo 'in_uso'. Ritorna
// domain.ErrVehicleNotFound se il mezzo non esiste e domain.ErrVehicleNotAvailable
// se non è sbloccabile (in uso, in manutenzione o prenotato da un altro utente).
func (r *RideRepository) Unlock(ctx context.Context, userID, vehicleID, qrCode string) (*domain.Ride, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Risolve e blocca il veicolo, per id (proximity) o per qr_code (QR scan).
	var resolvedVehicleID, status string
	if qrCode != "" {
		err = tx.QueryRow(ctx,
			`SELECT id, status FROM vehicles WHERE qr_code = $1 FOR UPDATE`, qrCode,
		).Scan(&resolvedVehicleID, &status)
	} else {
		err = tx.QueryRow(ctx,
			`SELECT id, status FROM vehicles WHERE id = $1 FOR UPDATE`, vehicleID,
		).Scan(&resolvedVehicleID, &status)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrVehicleNotFound
	}
	if err != nil {
		return nil, err
	}

	// Eventuale prenotazione 'attiva' dell'utente su questo mezzo: se c'è la
	// consumiamo, altrimenti procediamo allo sblocco diretto.
	var bookingID string
	err = tx.QueryRow(ctx,
		`SELECT id FROM bookings
		 WHERE user_id = $1 AND vehicle_id = $2 AND status = 'attiva'
		 ORDER BY created_at DESC
		 LIMIT 1
		 FOR UPDATE`,
		userID, resolvedVehicleID,
	).Scan(&bookingID)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
		// Nessuna prenotazione: sblocco diretto, ma solo se il mezzo è libero.
		if status != "disponibile" {
			return nil, domain.ErrVehicleNotAvailable
		}
		// Prenotazione implicita (subito 'utilizzata') per ancorare la corsa.
		if err := tx.QueryRow(ctx,
			`INSERT INTO bookings (user_id, vehicle_id, expires_at, status)
			 VALUES ($1, $2, NOW(), 'utilizzata')
			 RETURNING id`,
			userID, resolvedVehicleID,
		).Scan(&bookingID); err != nil {
			return nil, err
		}
	case err != nil:
		return nil, err
	default:
		// Prenotazione attiva esistente: la marchiamo come utilizzata.
		if _, err := tx.Exec(ctx,
			`UPDATE bookings SET status = 'utilizzata' WHERE id = $1`,
			bookingID,
		); err != nil {
			return nil, err
		}
	}

	// Crea la corsa.
	ride := &domain.Ride{BookingID: bookingID, UserID: userID, VehicleID: resolvedVehicleID}
	if err := tx.QueryRow(ctx,
		`INSERT INTO rides (booking_id, user_id, vehicle_id, started_at, status)
		 VALUES ($1, $2, $3, NOW(), 'attiva')
		 RETURNING id, started_at, status`,
		bookingID, userID, resolvedVehicleID,
	).Scan(&ride.ID, &ride.StartedAt, &ride.Status); err != nil {
		return nil, err
	}

	// Porta il veicolo in uso.
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

// End chiude la corsa 'attiva' dell'utente, calcola e persiste durata, costo e
// CO2 risparmiata, e rimette il mezzo 'disponibile', in un'unica transazione.
// Ritorna domain.ErrRideNotFound se non esiste una corsa attiva con quell'id
// appartenente all'utente.
func (r *RideRepository) End(ctx context.Context, userID, rideID string) (*domain.RideSummary, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Blocca la corsa e leggi inizio, tariffa e CO2/km della tipologia,
	// verificando che sia dell'utente e ancora attiva.
	var (
		vehicleID  string
		startedAt  time.Time
		ratePerMin float64
		co2PerKm   float64
	)
	err = tx.QueryRow(ctx,
		`SELECT r.vehicle_id, r.started_at,
		        vt.tariffa_al_minuto::float8, vt.co2_risparmiata_per_km::float8
		   FROM rides r
		   JOIN vehicles v       ON v.id = r.vehicle_id
		   JOIN vehicle_types vt ON vt.id = v.type_id
		  WHERE r.id = $1 AND r.user_id = $2 AND r.status = 'attiva'
		  FOR UPDATE OF r`,
		rideID, userID,
	).Scan(&vehicleID, &startedAt, &ratePerMin, &co2PerKm)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrRideNotFound
	}
	if err != nil {
		return nil, err
	}

	endedAt := time.Now()
	elapsed := endedAt.Sub(startedAt)
	minutes := domain.ChargedMinutes(elapsed)
	cost := math.Round(float64(minutes)*ratePerMin*100) / 100
	co2 := math.Round(domain.EstimateCo2SavedGrams(elapsed, co2PerKm))

	if _, err := tx.Exec(ctx,
		`UPDATE rides
		    SET status = 'completata', ended_at = $2,
		        duration_minutes = $3, total_cost = $4, co2_saved = $5
		  WHERE id = $1`,
		rideID, endedAt, minutes, cost, co2,
	); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'disponibile', updated_at = NOW() WHERE id = $1`,
		vehicleID,
	); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &domain.RideSummary{
		DurationMinutes: minutes,
		TotalCost:       cost,
		Co2SavedGrams:   co2,
	}, nil
}
