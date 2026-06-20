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

	summary, err := r.endRideTx(ctx, tx, userID, rideID)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return summary, nil
}

// endRideTx chiude una singola corsa ('attiva' o 'paused') dell'utente dentro la
// transazione tx: calcola e persiste durata, costo e CO2, applica gli sconti,
// libera il mezzo e ritorna il riepilogo (senza commit). Condivisa da End (corsa
// singola) e da EndGroup (corsa di gruppo, UT.16).
func (r *RideRepository) endRideTx(ctx context.Context, tx pgx.Tx, userID, rideID string) (*domain.RideSummary, error) {
	var err error
	// Blocca la corsa e leggi inizio, tariffa e CO2/km della tipologia,
	// verificando che sia dell'utente e ancora attiva (o in pausa). Recupera anche
	// l'eventuale codice sconto collegato alla prenotazione (UT.09).
	var (
		vehicleID    string
		startedAt    time.Time
		ratePerMin   float64
		co2PerKm     float64
		discountID   *string
		discountPct  *float64
		promotionID  *string
		promotionPct *float64
	)
	err = tx.QueryRow(ctx,
		`SELECT r.vehicle_id, r.started_at,
		        vt.tariffa_al_minuto::float8, vt.co2_risparmiata_per_km::float8,
		        dc.id, dc.percentage::float8,
		        p.id, p.percentage::float8
		   FROM rides r
		   JOIN vehicles v       ON v.id = r.vehicle_id
		   JOIN vehicle_types vt ON vt.id = v.type_id
		   LEFT JOIN bookings b        ON b.id = r.booking_id
		   LEFT JOIN discount_codes dc ON dc.id = b.discount_code_id
		   LEFT JOIN promotions p      ON p.id = b.promotion_id
		  WHERE r.id = $1 AND r.user_id = $2 AND r.status IN ('attiva', 'paused')
		  FOR UPDATE OF r`,
		rideID, userID,
	).Scan(&vehicleID, &startedAt, &ratePerMin, &co2PerKm, &discountID, &discountPct, &promotionID, &promotionPct)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrRideNotFound
	}
	if err != nil {
		return nil, err
	}

	endedAt := time.Now()

	// Recupera tutti gli intervalli di pausa della corsa.
	rows, err := tx.Query(ctx,
		`SELECT paused_at, resumed_at FROM ride_pauses WHERE ride_id = $1 ORDER BY paused_at ASC`,
		rideID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var totalPauseDuration time.Duration
	for rows.Next() {
		var pAt time.Time
		var rAt *time.Time
		if err := rows.Scan(&pAt, &rAt); err != nil {
			return nil, err
		}
		var endP time.Time
		if rAt != nil {
			endP = *rAt
		} else {
			// Pausa non ancora chiusa (corsa terminata mentre era in pausa).
			endP = endedAt
			// Aggiorna il record nel database per coerenza storica.
			_, err = tx.Exec(ctx,
				`UPDATE ride_pauses SET resumed_at = $2 WHERE ride_id = $1 AND resumed_at IS NULL`,
				rideID, endedAt,
			)
			if err != nil {
				return nil, err
			}
		}
		totalPauseDuration += endP.Sub(pAt)
	}

	elapsed := endedAt.Sub(startedAt)
	activeDuration := elapsed - totalPauseDuration
	if activeDuration < 0 {
		activeDuration = 0
	}

	// Calcola i minuti di noleggio attivo ed i minuti di pausa addebitati.
	activeMinutes := domain.ChargedMinutes(activeDuration)
	pauseMinutes := 0
	if totalPauseDuration.Seconds() >= 20 {
		pauseMinutes = int((totalPauseDuration.Seconds() + 59) / 60)
	}

	// 3 minuti di pausa gratuiti (UT.15).
	chargeablePauseMinutes := 0
	if pauseMinutes > 3 {
		chargeablePauseMinutes = pauseMinutes - 3
	}

	// Tariffa di pausa ridotta al 50%.
	ratePausePerMin := ratePerMin * 0.50

	grossActive := float64(activeMinutes) * ratePerMin
	grossPause := float64(chargeablePauseMinutes) * ratePausePerMin
	gross := math.Round((grossActive + grossPause)*100) / 100

	co2 := math.Round(domain.EstimateCo2SavedGrams(activeDuration, co2PerKm))

	// UT.09 / UT.21 — applica lo sconto complessivo: somma la percentuale del
	// codice sconto manuale (se presente) e della promozione automatica (se presente),
	// fino a un massimo del 100%. Il costo finale è al netto e applied_discount
	// registra la quota scontata.
	cost := gross
	var appliedDiscount float64
	var discountPctCombined float64
	if discountPct != nil {
		discountPctCombined += *discountPct
	}
	if promotionPct != nil {
		discountPctCombined += *promotionPct
	}

	if discountPctCombined > 0 {
		if discountPctCombined > 100 {
			discountPctCombined = 100
		}
		cost, appliedDiscount = domain.ApplyDiscount(gross, discountPctCombined)
	}

	totalMinutes := activeMinutes + chargeablePauseMinutes

	if _, err := tx.Exec(ctx,
		`UPDATE rides
		    SET status = 'completata', ended_at = $2,
		        duration_minutes = $3, total_cost = $4, co2_saved = $5,
		        applied_discount = $6
		  WHERE id = $1`,
		rideID, endedAt, totalMinutes, cost, co2, appliedDiscount,
	); err != nil {
		return nil, err
	}

	// Registra l'utilizzo del codice solo se lo sconto è stato effettivamente
	// applicato (corsa a pagamento con un codice valido collegato).
	if discountID != nil && appliedDiscount > 0 {
		if _, err := tx.Exec(ctx,
			`UPDATE discount_codes SET used_count = used_count + 1 WHERE id = $1`,
			*discountID,
		); err != nil {
			return nil, err
		}
	}

	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'disponibile', updated_at = NOW() WHERE id = $1`,
		vehicleID,
	); err != nil {
		return nil, err
	}

	return &domain.RideSummary{
		DurationMinutes: totalMinutes,
		TotalCost:       cost,
		Co2SavedGrams:   co2,
		AppliedDiscount: appliedDiscount,
	}, nil
}

// Pause mette in pausa la corsa attiva dell'utente. Cambia lo stato della corsa
// a 'paused', inserisce un record in ride_pauses, e ritorna il tipo di veicolo.
func (r *RideRepository) Pause(ctx context.Context, userID, rideID string) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	// Verifica che la corsa sia dell'utente ed attiva, e recupera il tipo di veicolo.
	var status string
	var vehicleType string
	err = tx.QueryRow(ctx,
		`SELECT r.status, vt.nome
		   FROM rides r
		   JOIN vehicles v ON v.id = r.vehicle_id
		   JOIN vehicle_types vt ON vt.id = v.type_id
		  WHERE r.id = $1 AND r.user_id = $2 FOR UPDATE OF r`,
		rideID, userID,
	).Scan(&status, &vehicleType)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", domain.ErrRideNotFound
	}
	if err != nil {
		return "", err
	}
	if status != "attiva" {
		return "", errors.New("corsa non attiva, impossibile mettere in pausa")
	}

	// Imposta lo stato della corsa a 'paused'.
	_, err = tx.Exec(ctx,
		`UPDATE rides SET status = 'paused' WHERE id = $1`,
		rideID,
	)
	if err != nil {
		return "", err
	}

	// Inserisce l'intervallo di pausa in ride_pauses.
	_, err = tx.Exec(ctx,
		`INSERT INTO ride_pauses (ride_id, paused_at) VALUES ($1, NOW())`,
		rideID,
	)
	if err != nil {
		return "", err
	}

	return vehicleType, tx.Commit(ctx)
}

// Resume riattiva la corsa in pausa dell'utente. Ripristina lo stato a 'attiva',
// aggiorna resumed_at nell'ultimo record di ride_pauses, e ritorna il tipo di veicolo.
func (r *RideRepository) Resume(ctx context.Context, userID, rideID string) (string, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)

	// Verifica che la corsa sia dell'utente ed in pausa, e recupera il tipo di veicolo.
	var status string
	var vehicleType string
	err = tx.QueryRow(ctx,
		`SELECT r.status, vt.nome
		   FROM rides r
		   JOIN vehicles v ON v.id = r.vehicle_id
		   JOIN vehicle_types vt ON vt.id = v.type_id
		  WHERE r.id = $1 AND r.user_id = $2 FOR UPDATE OF r`,
		rideID, userID,
	).Scan(&status, &vehicleType)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", domain.ErrRideNotFound
	}
	if err != nil {
		return "", err
	}
	if status != "paused" {
		return "", errors.New("corsa non in pausa, impossibile riprenderla")
	}

	// Imposta lo stato della corsa a 'attiva'.
	_, err = tx.Exec(ctx,
		`UPDATE rides SET status = 'attiva' WHERE id = $1`,
		rideID,
	)
	if err != nil {
		return "", err
	}

	// Chiude l'intervallo di pausa aggiornando l'ultimo record di ride_pauses.
	_, err = tx.Exec(ctx,
		`UPDATE ride_pauses
		    SET resumed_at = NOW()
		  WHERE id = (
		      SELECT id FROM ride_pauses
		       WHERE ride_id = $1 AND resumed_at IS NULL
		       ORDER BY paused_at DESC
		       LIMIT 1
		  )`,
		rideID,
	)
	if err != nil {
		return "", err
	}

	return vehicleType, tx.Commit(ctx)
}

// UnlockGroup avvia tutte le corse di una prenotazione multipla (UT.16): per ogni
// prenotazione 'attiva' del gruppo consuma la prenotazione, crea una corsa con lo
// stesso group_id e porta il mezzo 'in_uso'. Ritorna domain.ErrRideNotFound se il
// gruppo non ha prenotazioni attive dell'utente.
func (r *RideRepository) UnlockGroup(ctx context.Context, userID, groupID string) ([]*domain.Ride, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx,
		`SELECT id, vehicle_id FROM bookings
		  WHERE group_id = $1 AND user_id = $2 AND status = 'attiva'
		  FOR UPDATE`,
		groupID, userID,
	)
	if err != nil {
		return nil, err
	}
	type bk struct{ bookingID, vehicleID string }
	var pending []bk
	for rows.Next() {
		var b bk
		if err := rows.Scan(&b.bookingID, &b.vehicleID); err != nil {
			rows.Close()
			return nil, err
		}
		pending = append(pending, b)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(pending) == 0 {
		return nil, domain.ErrRideNotFound
	}

	gid := groupID
	rides := make([]*domain.Ride, 0, len(pending))
	for _, p := range pending {
		if _, err := tx.Exec(ctx,
			`UPDATE bookings SET status = 'utilizzata' WHERE id = $1`, p.bookingID,
		); err != nil {
			return nil, err
		}
		ride := &domain.Ride{BookingID: p.bookingID, UserID: userID, VehicleID: p.vehicleID, GroupID: &gid}
		if err := tx.QueryRow(ctx,
			`INSERT INTO rides (booking_id, user_id, vehicle_id, group_id, started_at, status)
			 VALUES ($1, $2, $3, $4, NOW(), 'attiva')
			 RETURNING id, started_at, status`,
			p.bookingID, userID, p.vehicleID, groupID,
		).Scan(&ride.ID, &ride.StartedAt, &ride.Status); err != nil {
			return nil, err
		}
		if _, err := tx.Exec(ctx,
			`UPDATE vehicles SET status = 'in_uso', updated_at = NOW() WHERE id = $1`, p.vehicleID,
		); err != nil {
			return nil, err
		}
		rides = append(rides, ride)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return rides, nil
}

// EndGroup chiude tutte le corse attive/in pausa di un gruppo (UT.16) in un'unica
// transazione e ritorna il riepilogo aggregato (durata, costo, CO2 e sconto
// sommati). Ritorna domain.ErrRideNotFound se il gruppo non ha corse da chiudere.
func (r *RideRepository) EndGroup(ctx context.Context, userID, groupID string) (*domain.RideSummary, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx,
		`SELECT id FROM rides
		  WHERE group_id = $1 AND user_id = $2 AND status IN ('attiva', 'paused')`,
		groupID, userID,
	)
	if err != nil {
		return nil, err
	}
	var rideIDs []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, err
		}
		rideIDs = append(rideIDs, id)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(rideIDs) == 0 {
		return nil, domain.ErrRideNotFound
	}

	total := &domain.RideSummary{}
	for _, id := range rideIDs {
		s, err := r.endRideTx(ctx, tx, userID, id)
		if err != nil {
			return nil, err
		}
		total.DurationMinutes += s.DurationMinutes
		total.TotalCost += s.TotalCost
		total.Co2SavedGrams += s.Co2SavedGrams
		total.AppliedDiscount += s.AppliedDiscount
	}
	total.TotalCost = math.Round(total.TotalCost*100) / 100
	total.AppliedDiscount = math.Round(total.AppliedDiscount*100) / 100

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return total, nil
}
