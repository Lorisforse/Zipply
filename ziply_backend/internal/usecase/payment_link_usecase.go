package usecase

import (
	"context"
	"errors"
	"math"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
)

// PaymentLinkRepository definisce i metodi richiesti per la persistenza dei link di pagamento.
type PaymentLinkRepository interface {
	Create(ctx context.Context, rideID string, totalAmount float64, participants int, amountPerHead float64, validUntil time.Time) (*domain.PaymentLink, error)
	GetByID(ctx context.Context, id string) (*domain.PaymentLink, error)
	GetRideByID(ctx context.Context, rideID string) (*domain.Ride, error)
	GetGroupRidesDetails(ctx context.Context, groupID string) (int, float64, error)
	Pay(ctx context.Context, id string) error
	GetUserCreditBalance(ctx context.Context, userID string) (float64, error)
}

// PaymentLinkUsecase implementa la logica di business dei link di pagamento.
type PaymentLinkUsecase struct {
	repo PaymentLinkRepository
}

// NewPaymentLinkUsecase crea un nuovo PaymentLinkUsecase.
func NewPaymentLinkUsecase(repo PaymentLinkRepository) *PaymentLinkUsecase {
	return &PaymentLinkUsecase{repo: repo}
}

// Generate crea un link di pagamento per dividere il costo di una corsa multipla.
func (uc *PaymentLinkUsecase) Generate(ctx context.Context, userID, rideID string) (*domain.PaymentLink, error) {
	// 1. Recupera la corsa e verifica che appartenga all'utente
	ride, err := uc.repo.GetRideByID(ctx, rideID)
	if err != nil {
		return nil, err
	}
	if ride.UserID != userID {
		return nil, domain.ErrRideNotFound // Per sicurezza non riveliamo l'esistenza della corsa altrui
	}

	// 2. Verifica che sia completata
	if ride.Status != "completata" {
		return nil, errors.New("la corsa deve essere completata per generare un link di pagamento")
	}

	// 3. Verifica che sia una corsa multipla (con group_id)
	if ride.GroupID == nil || *ride.GroupID == "" {
		return nil, errors.New("la corsa selezionata non fa parte di un noleggio di gruppo")
	}

	// 4. Recupera i dettagli del gruppo
	participants, totalAmount, err := uc.repo.GetGroupRidesDetails(ctx, *ride.GroupID)
	if err != nil {
		return nil, err
	}
	if participants <= 0 {
		return nil, errors.New("nessun partecipante trovato per il noleggio di gruppo")
	}

	// 5. Calcola la quota per partecipante e arrotonda a 2 decimali
	amountPerHead := math.Round((totalAmount/float64(participants))*100) / 100

	// 6. Crea il link di pagamento con validità 10 minuti
	validUntil := time.Now().Add(10 * time.Minute)
	return uc.repo.Create(ctx, rideID, totalAmount, participants, amountPerHead, validUntil)
}

// Get recupera i dettagli di un link di pagamento.
func (uc *PaymentLinkUsecase) Get(ctx context.Context, id string) (*domain.PaymentLink, error) {
	pl, err := uc.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	// Se il link non è pagato ed è scaduto, aggiorna lo stato in expired a livello di risposta
	if pl.Status == "active" && time.Now().After(pl.ValidUntil) {
		pl.Status = "expired"
	}

	return pl, nil
}

// Pay simula l'addebito e registra il pagamento della quota con accredito al prenotante.
func (uc *PaymentLinkUsecase) Pay(ctx context.Context, id string) error {
	// Simula la chiamata al gateway di pagamento (addebito quota)
	// log.Printf("[GATEWAY] Mock charge for payment link %s succeeded", id)

	return uc.repo.Pay(ctx, id)
}

// GetUserCreditBalance restituisce il saldo crediti dell'utente.
func (uc *PaymentLinkUsecase) GetUserCreditBalance(ctx context.Context, userID string) (float64, error) {
	return uc.repo.GetUserCreditBalance(ctx, userID)
}
