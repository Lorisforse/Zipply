package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// rowQuerier è la parte di pgx.Tx / pgxpool.Pool usata per leggere una riga,
// così resolveDiscount può girare dentro una transazione esistente.
type rowQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// resolveDiscount valida un codice sconto dentro la transazione q e ne ritorna
// l'id. Ritorna domain.ErrDiscountNotFound se il codice non esiste e
// domain.ErrDiscountNotValid se non è utilizzabile (scaduto/esaurito/disattivo).
// Riusato dal flusso di prenotazione (UT.09) per collegare lo sconto.
func resolveDiscount(ctx context.Context, q rowQuerier, code string) (string, error) {
	d := domain.DiscountCode{}
	err := q.QueryRow(ctx,
		`SELECT id, code, percentage::float8, valid_from, valid_until,
		        is_active, max_uses, used_count
		   FROM discount_codes
		  WHERE UPPER(code) = UPPER($1)`,
		strings.TrimSpace(code),
	).Scan(
		&d.ID, &d.Code, &d.Percentage, &d.ValidFrom, &d.ValidUntil,
		&d.IsActive, &d.MaxUses, &d.UsedCount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", domain.ErrDiscountNotFound
	}
	if err != nil {
		return "", err
	}
	if !d.Usable(time.Now()) {
		return "", domain.ErrDiscountNotValid
	}
	return d.ID, nil
}

// DiscountRepository fornisce l'accesso alla tabella discount_codes.
type DiscountRepository struct {
	pool *pgxpool.Pool
}

// NewDiscountRepository crea un DiscountRepository sul pool di connessioni dato.
func NewDiscountRepository(pool *pgxpool.Pool) *DiscountRepository {
	return &DiscountRepository{pool: pool}
}

// FindByCode recupera il codice sconto per codice (case-insensitive, trim).
// Ritorna domain.ErrDiscountNotFound se non esiste.
func (r *DiscountRepository) FindByCode(ctx context.Context, code string) (*domain.DiscountCode, error) {
	d := &domain.DiscountCode{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, code, percentage::float8, valid_from, valid_until,
		        is_active, max_uses, used_count
		   FROM discount_codes
		  WHERE UPPER(code) = UPPER($1)`,
		strings.TrimSpace(code),
	).Scan(
		&d.ID, &d.Code, &d.Percentage, &d.ValidFrom, &d.ValidUntil,
		&d.IsActive, &d.MaxUses, &d.UsedCount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, domain.ErrDiscountNotFound
	}
	if err != nil {
		return nil, err
	}
	return d, nil
}

// GetActivePromotion recupera la promozione attiva con la percentuale di sconto maggiore.
// Se non ci sono promozioni attive ritorna nil, nil.
func (r *DiscountRepository) GetActivePromotion(ctx context.Context) (*domain.Promotion, error) {
	p := &domain.Promotion{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, description, percentage::float8, valid_from, valid_until, is_active
		   FROM promotions
		  WHERE is_active = TRUE AND NOW() BETWEEN valid_from AND valid_until
		  ORDER BY percentage DESC
		  LIMIT 1`,
	).Scan(
		&p.ID, &p.Description, &p.Percentage, &p.ValidFrom, &p.ValidUntil, &p.IsActive,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return p, nil
}
