package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// OperatorRepository fornisce l'accesso in lettura alla flotta per l'area
// riservata operatore (OP.01).
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
