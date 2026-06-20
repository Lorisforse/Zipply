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
