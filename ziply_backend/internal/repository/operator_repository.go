package repository

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// OperatorRepository fornisce l'accesso alla flotta e alle zone operative per
// l'area riservata operatore.
type OperatorRepository struct {
	pool *pgxpool.Pool
}

// NewOperatorRepository crea un OperatorRepository sul pool dato.
func NewOperatorRepository(pool *pgxpool.Pool) *OperatorRepository {
	return &OperatorRepository{pool: pool}
}

// ListAllVehicles restituisce tutti i mezzi della flotta con il relativo stato
// operativo e tariffa, ordinati per qr_code. A differenza di
// VehicleRepository.ListAvailable (solo 'disponibile' per la mappa utente) qui
// non c'è filtro sullo status: l'operatore monitora l'intera flotta.
func (r *OperatorRepository) ListAllVehicles(ctx context.Context) ([]domain.OperatorVehicle, error) {
	const query = `SELECT v.id, vt.nome, v.qr_code, v.latitude, v.longitude, v.battery_level, vt.tariffa_al_minuto, v.status
		FROM vehicles v
		JOIN vehicle_types vt ON vt.id = v.type_id
		ORDER BY v.qr_code`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	vehicles := make([]domain.OperatorVehicle, 0)
	for rows.Next() {
		var v domain.OperatorVehicle
		if err := rows.Scan(
			&v.ID, &v.Type, &v.QrCode, &v.Latitude, &v.Longitude, &v.BatteryLevel, &v.TariffaAlMinuto, &v.Status,
		); err != nil {
			return nil, err
		}
		vehicles = append(vehicles, v)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return vehicles, nil
}

// BlockVehicle imposta lo status del mezzo a 'bloccato' (OP.11 / UC-32).
// L'operazione e' idempotente rispetto allo stato corrente; restituisce
// ErrVehicleNotFound se il mezzo non esiste.
func (r *OperatorRepository) BlockVehicle(ctx context.Context, vehicleID string) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE vehicles SET status = 'bloccato' WHERE id = $1`, vehicleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrVehicleNotFound
	}
	return nil
}

// UnblockVehicle sblocca un mezzo precedentemente bloccato (OP.11 / UC-32).
// La transizione finale dello status dipende dalle segnalazioni aperte:
//   - nessuna segnalazione in_attesa/preso_in_carico -> 'disponibile'
//   - almeno una segnalazione aperta -> 'manutenzione'
//
// Restituisce ErrVehicleNotFound se il mezzo non esiste o non e' in stato
// 'bloccato'.
func (r *OperatorRepository) UnblockVehicle(ctx context.Context, vehicleID string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Passo 1: sblocca solo se il mezzo e' in stato 'bloccato'.
	tag, err := tx.Exec(ctx,
		`UPDATE vehicles SET status = 'disponibile' WHERE id = $1 AND status = 'bloccato'`,
		vehicleID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrVehicleNotFound
	}

	// Passo 2: se esistono segnalazioni aperte, il mezzo torna in manutenzione
	// invece di tornare disponibile.
	_, err = tx.Exec(ctx, `
		UPDATE vehicles v SET status = 'manutenzione'
		WHERE v.id = $1
		  AND EXISTS (
		    SELECT 1 FROM malfunction_reports mr
		    WHERE mr.vehicle_id = v.id
		      AND mr.status IN ('in_attesa', 'preso_in_carico')
		  )`, vehicleID)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ListParkingZones restituisce le zone parcheggio attive (OP.04 / UC-27).
func (r *OperatorRepository) ListParkingZones(ctx context.Context) ([]domain.ParkingZone, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, name, polygon, bonus_credit, is_active
		 FROM parking_zones WHERE is_active = true ORDER BY name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	zones := make([]domain.ParkingZone, 0)
	for rows.Next() {
		var z domain.ParkingZone
		var polygonJSON []byte
		if err := rows.Scan(&z.ID, &z.Name, &polygonJSON, &z.BonusCredit, &z.IsActive); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(polygonJSON, &z.Center); err != nil {
			return nil, err
		}
		zones = append(zones, z)
	}
	return zones, rows.Err()
}

// CreateParkingZone inserisce una nuova zona parcheggio (OP.04 / UC-27).
// Il campo Center viene serializzato come JSONB nel campo polygon.
func (r *OperatorRepository) CreateParkingZone(ctx context.Context, z *domain.ParkingZone) error {
	polygonJSON, err := json.Marshal(z.Center)
	if err != nil {
		return err
	}
	return r.pool.QueryRow(ctx,
		`INSERT INTO parking_zones (name, polygon, bonus_credit, is_active)
		 VALUES ($1, $2, $3, true)
		 RETURNING id`,
		z.Name, polygonJSON, z.BonusCredit,
	).Scan(&z.ID)
}

// DeleteParkingZone rimuove logicamente una zona parcheggio impostando
// is_active=false. Restituisce ErrParkingZoneNotFound se non esiste.
func (r *OperatorRepository) DeleteParkingZone(ctx context.Context, id string) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE parking_zones SET is_active = false WHERE id = $1 AND is_active = true`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrParkingZoneNotFound
	}
	return nil
}
