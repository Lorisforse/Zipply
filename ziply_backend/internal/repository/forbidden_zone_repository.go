package repository

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// ForbiddenZoneRepository provides read access to the forbidden_zones table.
type ForbiddenZoneRepository struct {
	pool *pgxpool.Pool
}

// NewForbiddenZoneRepository creates a ForbiddenZoneRepository backed by the given connection pool.
func NewForbiddenZoneRepository(pool *pgxpool.Pool) *ForbiddenZoneRepository {
	return &ForbiddenZoneRepository{pool: pool}
}

// ListActive returns the forbidden zones with is_active = true. The polygon
// JSONB column (GeoJSON Polygon o MultiPolygon) viene letta grezza e inoltrata
// senza interpretarla.
func (r *ForbiddenZoneRepository) ListActive(ctx context.Context) ([]domain.ForbiddenZone, error) {
	const query = `SELECT id, nome, polygon, is_active
		FROM forbidden_zones
		WHERE is_active = true`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	zones := make([]domain.ForbiddenZone, 0)
	for rows.Next() {
		var z domain.ForbiddenZone
		var polygon []byte
		if err := rows.Scan(&z.ID, &z.Nome, &polygon, &z.IsActive); err != nil {
			return nil, err
		}
		// Copia difensiva: pgx può riutilizzare il buffer della riga.
		z.Polygon = json.RawMessage(append([]byte(nil), polygon...))
		zones = append(zones, z)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return zones, nil
}
