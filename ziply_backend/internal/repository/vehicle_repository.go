package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// VehicleRepository provides read access to the vehicles table.
type VehicleRepository struct {
	pool *pgxpool.Pool
}

// NewVehicleRepository creates a VehicleRepository backed by the given connection pool.
func NewVehicleRepository(pool *pgxpool.Pool) *VehicleRepository {
	return &VehicleRepository{pool: pool}
}

// ListAvailable returns the vehicles with status 'disponibile', joined with their type.
// When filter is non-nil the result is restricted to the Haversine distance radius (km).
func (r *VehicleRepository) ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error) {
	query := `SELECT v.id, vt.nome, v.qr_code, v.latitude, v.longitude, v.battery_level, vt.tariffa_al_minuto
		FROM vehicles v
		JOIN vehicle_types vt ON vt.id = v.type_id
		WHERE v.status = 'disponibile'`

	var args []any
	if filter != nil {
		query += `
		AND (6371 * acos(
			cos(radians($1)) * cos(radians(v.latitude)) *
			cos(radians(v.longitude) - radians($2)) +
			sin(radians($1)) * sin(radians(v.latitude))
		)) <= $3`
		args = append(args, filter.Lat, filter.Lng, filter.Radius)
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	vehicles := make([]domain.Vehicle, 0)
	for rows.Next() {
		var v domain.Vehicle
		if err := rows.Scan(
			&v.ID, &v.Type, &v.QrCode, &v.Latitude, &v.Longitude, &v.BatteryLevel, &v.TariffaAlMinuto,
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

// GetByID returns the vehicle with the given id joined with its type, or
// domain.ErrVehicleNotFound if it does not exist. Usato dal calcolo percorso
// (UT.07) per ricavare posizione e tipologia del mezzo selezionato.
func (r *VehicleRepository) GetByID(ctx context.Context, id string) (*domain.Vehicle, error) {
	const query = `SELECT v.id, vt.nome, v.qr_code, v.latitude, v.longitude, v.battery_level, vt.tariffa_al_minuto
		FROM vehicles v
		JOIN vehicle_types vt ON vt.id = v.type_id
		WHERE v.id = $1`

	var v domain.Vehicle
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&v.ID, &v.Type, &v.QrCode, &v.Latitude, &v.Longitude, &v.BatteryLevel, &v.TariffaAlMinuto,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrVehicleNotFound
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// GetPositionAndStatus restituisce posizione e stato correnti del mezzo,
// usati dal controllo di movimento illecito (OP.02 / OP.07). Ritorna
// domain.ErrVehicleNotFound se il mezzo non esiste.
func (r *VehicleRepository) GetPositionAndStatus(ctx context.Context, id string) (lat, lng float64, status string, err error) {
	err = r.pool.QueryRow(ctx,
		`SELECT latitude, longitude, status FROM vehicles WHERE id = $1`, id,
	).Scan(&lat, &lng, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, 0, "", domain.ErrVehicleNotFound
	}
	return lat, lng, status, err
}

// UpdatePosition sovrascrive la posizione riportata dal mezzo (simula la
// telemetria GPS, OP.02 / OP.07: non esiste hardware IoT reale, la posizione
// arriva via PATCH /operator/vehicles/{id}/report-position).
func (r *VehicleRepository) UpdatePosition(ctx context.Context, id string, lat, lng float64) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE vehicles SET latitude = $2, longitude = $3, updated_at = NOW() WHERE id = $1`,
		id, lat, lng,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrVehicleNotFound
	}
	return nil
}
