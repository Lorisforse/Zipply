package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/lorisforse/ziply_backend/internal/domain"
)

// MalfunctionReportRepository gestisce la persistenza delle segnalazioni di malfunzionamento.
type MalfunctionReportRepository struct {
	pool *pgxpool.Pool
}

// NewMalfunctionReportRepository crea un nuovo MalfunctionReportRepository.
func NewMalfunctionReportRepository(pool *pgxpool.Pool) *MalfunctionReportRepository {
	return &MalfunctionReportRepository{pool: pool}
}

// GetRideDetails recupera le info essenziali della corsa per la convalida.
func (r *MalfunctionReportRepository) GetRideDetails(ctx context.Context, rideID string) (*domain.Ride, error) {
	ride := &domain.Ride{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, vehicle_id, status FROM rides WHERE id = $1`,
		rideID,
	).Scan(&ride.ID, &ride.UserID, &ride.VehicleID, &ride.Status)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrRideNotFound
	}
	if err != nil {
		return nil, err
	}
	return ride, nil
}

// Create inserisce la segnalazione nel DB e imposta il veicolo in manutenzione tramite transazione.
func (r *MalfunctionReportRepository) Create(ctx context.Context, report *domain.MalfunctionReport) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	// 1. Inserisce la segnalazione
	err = tx.QueryRow(ctx,
		`INSERT INTO malfunction_reports (user_id, vehicle_id, ride_id, problem_type, description, attachment_urls, status)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, created_at`,
		report.UserID, report.VehicleID, report.RideID, report.ProblemType, report.Description, report.AttachmentURLs, report.Status,
	).Scan(&report.ID, &report.CreatedAt)
	if err != nil {
		return err
	}

	// 2. Aggiorna lo stato del veicolo in manutenzione
	_, err = tx.Exec(ctx,
		`UPDATE vehicles SET status = 'manutenzione' WHERE id = $1`,
		report.VehicleID,
	)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// ListAll restituisce le segnalazioni con i dati del mezzo coinvolto per la
// dashboard operatore (OP.03 / UC-26). Se statusFilter è valorizzato, filtra per
// stato; altrimenti restituisce tutte le segnalazioni. Ordinate dalla più
// recente. La fonte è 'utente' (le segnalazioni da sensore non sono ancora
// persistite a DB).
func (r *MalfunctionReportRepository) ListAll(ctx context.Context, statusFilter string) ([]domain.OperatorMalfunctionReport, error) {
	query := `SELECT mr.id, mr.vehicle_id, v.qr_code, vt.nome, v.latitude, v.longitude,
	                 mr.problem_type, mr.description, mr.created_at, mr.status
	            FROM malfunction_reports mr
	            JOIN vehicles v ON v.id = mr.vehicle_id
	            JOIN vehicle_types vt ON vt.id = v.type_id`
	args := []any{}
	if statusFilter != "" {
		query += ` WHERE mr.status = $1`
		args = append(args, statusFilter)
	}
	query += ` ORDER BY mr.created_at DESC`

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	reports := make([]domain.OperatorMalfunctionReport, 0)
	for rows.Next() {
		var rep domain.OperatorMalfunctionReport
		if err := rows.Scan(
			&rep.ID, &rep.VehicleID, &rep.VehicleQR, &rep.VehicleType, &rep.Latitude, &rep.Longitude,
			&rep.ProblemType, &rep.Description, &rep.CreatedAt, &rep.Status,
		); err != nil {
			return nil, err
		}
		rep.Source = "utente"
		reports = append(reports, rep)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return reports, nil
}

// UpdateStatus aggiorna lo stato di lavorazione di una segnalazione. Quando la
// segnalazione passa a 'risolto' il mezzo viene rimesso disponibile (solo se era
// in 'manutenzione', per non sovrascrivere un eventuale blocco remoto). Il tutto
// in un'unica transazione. Restituisce ErrMalfunctionReportNotFound se la
// segnalazione non esiste.
func (r *MalfunctionReportRepository) UpdateStatus(ctx context.Context, reportID, newStatus string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var vehicleID string
	err = tx.QueryRow(ctx,
		`UPDATE malfunction_reports SET status = $1 WHERE id = $2 RETURNING vehicle_id`,
		newStatus, reportID,
	).Scan(&vehicleID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrMalfunctionReportNotFound
	}
	if err != nil {
		return err
	}

	if newStatus == domain.MalfunctionStatusRisolto {
		// Rimette il mezzo disponibile solo se non restano altre segnalazioni
		// aperte sullo stesso mezzo, e solo se era in 'manutenzione' (per non
		// sovrascrivere un eventuale blocco remoto dell'operatore).
		var openReports int
		err = tx.QueryRow(ctx,
			`SELECT COUNT(*) FROM malfunction_reports
			  WHERE vehicle_id = $1 AND status <> 'risolto'`,
			vehicleID,
		).Scan(&openReports)
		if err != nil {
			return err
		}
		if openReports == 0 {
			_, err = tx.Exec(ctx,
				`UPDATE vehicles SET status = 'disponibile' WHERE id = $1 AND status = 'manutenzione'`,
				vehicleID,
			)
			if err != nil {
				return err
			}
		}
	}

	return tx.Commit(ctx)
}
