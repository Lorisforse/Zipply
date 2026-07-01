package usecase

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// AvailabilityAlertRepository astrae le letture e le scritture necessarie al
// worker di rilevamento anomalie (OP.02 / OP.07): batteria scarica e
// scarsita' mezzi per area di servizio. Il movimento illecito e' gestito a
// parte da VehicleUsecase.ReportPosition, agganciato alla telemetria in
// arrivo invece che al ciclo periodico.
type AvailabilityAlertRepository interface {
	Insert(ctx context.Context, alert domain.AvailabilityAlert) error
	List(ctx context.Context) ([]domain.AvailabilityAlert, error)
	HasRecentVehicleAlert(ctx context.Context, alertType, vehicleID string) (bool, error)
	HasRecentAreaAlert(ctx context.Context, serviceAreaID string) (bool, error)
	LowBatteryVehicles(ctx context.Context, threshold int) ([]domain.VehicleBatteryStatus, error)
	ActiveServiceAreas(ctx context.Context) ([]domain.ServiceArea, error)
	CountAvailableInArea(ctx context.Context, center domain.ServiceAreaCenter) (int, error)
}

// AvailabilityAlertUsecase orchestra il rilevamento periodico di anomalie
// (batteria scarica, scarsita' mezzi) e la consultazione degli avvisi
// generati (OP.02 / OP.07).
type AvailabilityAlertUsecase struct {
	repo AvailabilityAlertRepository
}

// NewAvailabilityAlertUsecase crea un AvailabilityAlertUsecase sul repository dato.
func NewAvailabilityAlertUsecase(repo AvailabilityAlertRepository) *AvailabilityAlertUsecase {
	return &AvailabilityAlertUsecase{repo: repo}
}

// List restituisce gli avvisi generati, per il pannello operatore.
func (uc *AvailabilityAlertUsecase) List(ctx context.Context) ([]domain.AvailabilityAlert, error) {
	return uc.repo.List(ctx)
}

// RunChecks esegue un ciclo di rilevamento: batteria scarica per ogni mezzo e
// scarsita' per ogni area di servizio attiva. Deduplica gli avvisi entro
// domain.AlertDedupeWindow per non spammare il log.
func (uc *AvailabilityAlertUsecase) RunChecks(ctx context.Context) error {
	if err := uc.checkLowBattery(ctx); err != nil {
		return fmt.Errorf("controllo batteria: %w", err)
	}
	if err := uc.checkScarceAreas(ctx); err != nil {
		return fmt.Errorf("controllo scarsita': %w", err)
	}
	return nil
}

func (uc *AvailabilityAlertUsecase) checkLowBattery(ctx context.Context) error {
	vehicles, err := uc.repo.LowBatteryVehicles(ctx, domain.LowBatteryThreshold)
	if err != nil {
		return err
	}
	for _, v := range vehicles {
		already, err := uc.repo.HasRecentVehicleAlert(ctx, domain.AlertTypeBatteria, v.VehicleID)
		if err != nil {
			return err
		}
		if already {
			continue
		}
		id := v.VehicleID
		if err := uc.repo.Insert(ctx, domain.AvailabilityAlert{
			Type:      domain.AlertTypeBatteria,
			VehicleID: &id,
			Message:   fmt.Sprintf("%s (%s): batteria scarica (%d%%)", v.QrCode, v.VehicleType, v.BatteryLevel),
		}); err != nil {
			return err
		}
	}
	return nil
}

func (uc *AvailabilityAlertUsecase) checkScarceAreas(ctx context.Context) error {
	areas, err := uc.repo.ActiveServiceAreas(ctx)
	if err != nil {
		return err
	}
	for _, a := range areas {
		count, err := uc.repo.CountAvailableInArea(ctx, a.Center)
		if err != nil {
			return err
		}
		if count >= a.MinVehicles {
			continue
		}
		already, err := uc.repo.HasRecentAreaAlert(ctx, a.ID)
		if err != nil {
			return err
		}
		if already {
			continue
		}
		areaID := a.ID
		available := count
		if err := uc.repo.Insert(ctx, domain.AvailabilityAlert{
			Type:           domain.AlertTypeScarsita,
			ServiceAreaID:  &areaID,
			AvailableCount: &available,
			Message:        fmt.Sprintf("Mezzi disponibili sotto soglia in %s (%d/%d)", a.Name, count, a.MinVehicles),
		}); err != nil {
			return err
		}
	}
	return nil
}

// StartWorker avvia il ciclo periodico di rilevamento anomalie in background,
// sullo stesso pattern di repository.StartSweeper (ticker + goroutine).
func (uc *AvailabilityAlertUsecase) StartWorker(ctx context.Context, interval time.Duration) {
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := uc.RunChecks(ctx); err != nil {
					log.Printf("[ALERTS] errore nel ciclo di rilevamento anomalie: %v", err)
				}
			}
		}
	}()
}
