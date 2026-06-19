package repository

import (
	"context"
	"log"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// StartSweeper starts a background goroutine that checks for rides paused for more than 24 hours
// and ends them automatically.
func StartSweeper(ctx context.Context, pool *pgxpool.Pool, rideRepo *RideRepository) {
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				sweep(ctx, pool, rideRepo)
			}
		}
	}()
}

func sweep(ctx context.Context, pool *pgxpool.Pool, rideRepo *RideRepository) {
	// Query for rides that have been paused for more than 24 hours.
	// rp.resumed_at IS NULL means the pause is still active.
	rows, err := pool.Query(ctx,
		`SELECT r.id, r.user_id
		   FROM rides r
		   JOIN ride_pauses rp ON rp.ride_id = r.id
		  WHERE r.status = 'paused'
		    AND rp.resumed_at IS NULL
		    AND rp.paused_at < NOW() - INTERVAL '24 hours'`)
	if err != nil {
		log.Printf("[SWEEPER] error querying paused rides: %v", err)
		return
	}
	defer rows.Close()

	type rideInfo struct {
		ID     string
		UserID string
	}
	var ridesToEnd []rideInfo

	for rows.Next() {
		var r rideInfo
		if err := rows.Scan(&r.ID, &r.UserID); err != nil {
			log.Printf("[SWEEPER] error scanning paused ride: %v", err)
			continue
		}
		ridesToEnd = append(ridesToEnd, r)
	}
	rows.Close()

	for _, r := range ridesToEnd {
		log.Printf("[SWEEPER] auto-ending ride %s for user %s (paused > 24h)", r.ID, r.UserID)
		_, err := rideRepo.End(ctx, r.UserID, r.ID)
		if err != nil {
			log.Printf("[SWEEPER] failed to end ride %s: %v", r.ID, err)
		} else {
			log.Printf("[SWEEPER] ride %s ended successfully by sweeper", r.ID)
		}
	}
}
