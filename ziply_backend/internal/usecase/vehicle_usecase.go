package usecase

import (
	"context"
	"fmt"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// VehicleRepository abstracts the persistence of vehicles required by the listing flow.
type VehicleRepository interface {
	ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error)
	GetPositionAndStatus(ctx context.Context, id string) (lat, lng float64, status, qrCode, vehicleType string, err error)
	UpdatePosition(ctx context.Context, id string, lat, lng float64) error
}

// VehicleAlertRecorder abstracts the persistence of anomaly alerts needed by
// the illicit-movement check (OP.02 / OP.07). E' lo stesso repository usato
// dal worker di scarsita'/batteria (AvailabilityAlertRepository), qui visto
// come interfaccia per poterlo mockare nei test.
type VehicleAlertRecorder interface {
	Insert(ctx context.Context, alert domain.AvailabilityAlert) error
	HasRecentVehicleAlert(ctx context.Context, alertType, vehicleID string) (bool, error)
}

// VehicleUsecase implements the available-vehicles listing flow.
type VehicleUsecase struct {
	vehicles VehicleRepository
	alerts   VehicleAlertRecorder
}

// NewVehicleUsecase creates a VehicleUsecase backed by the given repositories.
func NewVehicleUsecase(vehicles VehicleRepository, alerts VehicleAlertRecorder) *VehicleUsecase {
	return &VehicleUsecase{vehicles: vehicles, alerts: alerts}
}

// ListAvailable returns the available vehicles, optionally restricted to the given geographic filter.
func (uc *VehicleUsecase) ListAvailable(ctx context.Context, filter *domain.GeoFilter) ([]domain.Vehicle, error) {
	return uc.vehicles.ListAvailable(ctx, filter)
}

// ReportPosition registra una nuova posizione riportata per il mezzo,
// simulando la telemetria GPS (OP.02 / OP.07: non esiste hardware IoT reale).
// Se il mezzo non e' 'in_uso' e lo spostamento rispetto alla posizione nota
// supera domain.IllicitMovementMeters, genera un avviso di tipo "movimento"
// (deduplicato entro domain.AlertDedupeWindow). Ritorna true se e' stato
// generato un avviso. La posizione viene comunque aggiornata.
func (uc *VehicleUsecase) ReportPosition(ctx context.Context, vehicleID string, lat, lng float64) (bool, error) {
	prevLat, prevLng, status, qrCode, vehicleType, err := uc.vehicles.GetPositionAndStatus(ctx, vehicleID)
	if err != nil {
		return false, err
	}

	alertTriggered := false
	if status != "in_uso" {
		distance := haversineMeters(prevLat, prevLng, lat, lng)
		if distance > domain.IllicitMovementMeters {
			already, err := uc.alerts.HasRecentVehicleAlert(ctx, domain.AlertTypeMovimento, vehicleID)
			if err != nil {
				return false, err
			}
			if !already {
				id := vehicleID
				if err := uc.alerts.Insert(ctx, domain.AvailabilityAlert{
					Type:      domain.AlertTypeMovimento,
					VehicleID: &id,
					Message:   fmt.Sprintf("%s (%s): movimento rilevato senza corsa attiva (%.0fm)", qrCode, vehicleType, distance),
				}); err != nil {
					return false, err
				}
				alertTriggered = true
			}
		}
	}

	if err := uc.vehicles.UpdatePosition(ctx, vehicleID, lat, lng); err != nil {
		return false, err
	}
	return alertTriggered, nil
}
