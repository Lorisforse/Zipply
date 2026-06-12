package repository

import (
	"context"

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
	query := `SELECT v.id, vt.nome, v.latitude, v.longitude, v.battery_level, vt.tariffa_al_minuto
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
			&v.ID, &v.Type, &v.Latitude, &v.Longitude, &v.BatteryLevel, &v.TariffaAlMinuto,
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
