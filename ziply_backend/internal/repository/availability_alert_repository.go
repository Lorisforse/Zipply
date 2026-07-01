package repository

import (
	"context"
	"encoding/json"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// AvailabilityAlertRepository fornisce l'accesso alla tabella
// availability_alerts e alle letture necessarie al worker di rilevamento
// anomalie (OP.02 / OP.07).
type AvailabilityAlertRepository struct {
	pool *pgxpool.Pool
}

// NewAvailabilityAlertRepository crea un AvailabilityAlertRepository sul pool dato.
func NewAvailabilityAlertRepository(pool *pgxpool.Pool) *AvailabilityAlertRepository {
	return &AvailabilityAlertRepository{pool: pool}
}

// Insert registra un nuovo avviso.
func (r *AvailabilityAlertRepository) Insert(ctx context.Context, alert domain.AvailabilityAlert) error {
	return r.pool.QueryRow(ctx,
		`INSERT INTO availability_alerts (type, service_area_id, vehicle_id, available_count, message)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, created_at`,
		alert.Type, alert.ServiceAreaID, alert.VehicleID, alert.AvailableCount, alert.Message,
	).Scan(&alert.ID, &alert.CreatedAt)
}

// List restituisce gli ultimi avvisi (piu' recenti prima), per il pannello
// operatore. E' un log di sola lettura (nessuno stato di risoluzione, UC-25).
func (r *AvailabilityAlertRepository) List(ctx context.Context) ([]domain.AvailabilityAlert, error) {
	const query = `SELECT id, type, service_area_id, vehicle_id, available_count, message, created_at
		FROM availability_alerts
		ORDER BY created_at DESC
		LIMIT 200`

	rows, err := r.pool.Query(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	alerts := make([]domain.AvailabilityAlert, 0)
	for rows.Next() {
		var a domain.AvailabilityAlert
		if err := rows.Scan(&a.ID, &a.Type, &a.ServiceAreaID, &a.VehicleID, &a.AvailableCount, &a.Message, &a.CreatedAt); err != nil {
			return nil, err
		}
		alerts = append(alerts, a)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return alerts, nil
}

// HasRecentVehicleAlert indica se esiste gia' un avviso di quel tipo per quel
// mezzo entro la finestra di deduplica (domain.AlertDedupeWindow), per non
// spammare il log ad ogni ciclo del worker.
func (r *AvailabilityAlertRepository) HasRecentVehicleAlert(ctx context.Context, alertType, vehicleID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM availability_alerts
			WHERE type = $1 AND vehicle_id = $2
			  AND created_at > NOW() - make_interval(secs => $3)
		)`,
		alertType, vehicleID, domain.AlertDedupeWindow.Seconds(),
	).Scan(&exists)
	return exists, err
}

// HasRecentAreaAlert indica se esiste gia' un avviso di scarsita' per quella
// area entro la finestra di deduplica.
func (r *AvailabilityAlertRepository) HasRecentAreaAlert(ctx context.Context, serviceAreaID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM availability_alerts
			WHERE type = $1 AND service_area_id = $2
			  AND created_at > NOW() - make_interval(secs => $3)
		)`,
		domain.AlertTypeScarsita, serviceAreaID, domain.AlertDedupeWindow.Seconds(),
	).Scan(&exists)
	return exists, err
}

// LowBatteryVehicles restituisce i mezzi disponibili o prenotati con batteria
// sotto la soglia data (OP.02), con QR code e tipologia per un messaggio
// leggibile in dashboard.
func (r *AvailabilityAlertRepository) LowBatteryVehicles(ctx context.Context, threshold int) ([]domain.VehicleBatteryStatus, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT v.id, v.battery_level, v.qr_code, vt.nome
		 FROM vehicles v
		 JOIN vehicle_types vt ON vt.id = v.type_id
		 WHERE v.status IN ('disponibile', 'prenotato') AND v.battery_level < $1`,
		threshold,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]domain.VehicleBatteryStatus, 0)
	for rows.Next() {
		var v domain.VehicleBatteryStatus
		if err := rows.Scan(&v.VehicleID, &v.BatteryLevel, &v.QrCode, &v.VehicleType); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// ActiveServiceAreas restituisce le aree di servizio attive con la relativa
// soglia minima di mezzi (OP.07 / UC-25).
func (r *AvailabilityAlertRepository) ActiveServiceAreas(ctx context.Context) ([]domain.ServiceArea, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, name, polygon, min_vehicles FROM service_areas WHERE is_active = true`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	areas := make([]domain.ServiceArea, 0)
	for rows.Next() {
		var a domain.ServiceArea
		var centerJSON []byte
		if err := rows.Scan(&a.ID, &a.Name, &centerJSON, &a.MinVehicles); err != nil {
			return nil, err
		}
		if err := json.Unmarshal(centerJSON, &a.Center); err != nil {
			return nil, err
		}
		a.IsActive = true
		areas = append(areas, a)
	}
	return areas, rows.Err()
}

// CountAvailableInArea conta i mezzi 'disponibile' entro il raggio (in metri)
// dell'area data, riusando la stessa formula di Haversine di
// VehicleRepository.ListAvailable.
func (r *AvailabilityAlertRepository) CountAvailableInArea(ctx context.Context, center domain.ServiceAreaCenter) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM vehicles
		 WHERE status = 'disponibile'
		   AND (6371000 * acos(
		       cos(radians($1)) * cos(radians(latitude)) *
		       cos(radians(longitude) - radians($2)) +
		       sin(radians($1)) * sin(radians(latitude))
		   )) <= $3`,
		center.Lat, center.Lng, center.Radius,
	).Scan(&count)
	return count, err
}
