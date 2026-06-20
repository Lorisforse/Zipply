package usecase_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockPaymentLinkRepository struct {
	rides        map[string]*domain.Ride
	paymentLinks map[string]*domain.PaymentLink
	userCredits  map[string]float64
}

func (m *mockPaymentLinkRepository) Create(ctx context.Context, rideID string, totalAmount float64, participants int, amountPerHead float64, validUntil time.Time) (*domain.PaymentLink, error) {
	pl := &domain.PaymentLink{
		ID:            "pl-test-id",
		RideID:        rideID,
		TotalAmount:   totalAmount,
		Participants:  participants,
		AmountPerHead: amountPerHead,
		ValidUntil:    validUntil,
		Status:        "active",
	}
	m.paymentLinks[pl.ID] = pl
	return pl, nil
}

func (m *mockPaymentLinkRepository) GetByID(ctx context.Context, id string) (*domain.PaymentLink, error) {
	pl, ok := m.paymentLinks[id]
	if !ok {
		return nil, domain.ErrPaymentLinkNotFound
	}
	// Aggiunge prenotante name fittizio
	pl.PrenotanteName = "Mario Rossi"
	return pl, nil
}

func (m *mockPaymentLinkRepository) GetRideByID(ctx context.Context, rideID string) (*domain.Ride, error) {
	ride, ok := m.rides[rideID]
	if !ok {
		return nil, domain.ErrRideNotFound
	}
	return ride, nil
}

func (m *mockPaymentLinkRepository) GetGroupRidesDetails(ctx context.Context, groupID string) (int, float64, error) {
	count := 0
	total := 0.0
	for _, ride := range m.rides {
		if ride.GroupID != nil && *ride.GroupID == groupID {
			count++
			// Per simulare il costo della corsa, supponiamo che ciascuna costi 5.50
			total += 5.50
		}
	}
	if count == 0 {
		return 0, 0, nil
	}
	return count, total, nil
}

func (m *mockPaymentLinkRepository) Pay(ctx context.Context, id string) error {
	pl, ok := m.paymentLinks[id]
	if !ok {
		return domain.ErrPaymentLinkNotFound
	}
	if pl.Status == "expired" || time.Now().After(pl.ValidUntil) {
		pl.Status = "expired"
		return domain.ErrPaymentLinkExpired
	}
	if pl.Status == "paid" {
		return errors.New("quota già pagata")
	}

	pl.Status = "paid"

	// Accredita al prenotante (user_id della corsa associata)
	ride, ok := m.rides[pl.RideID]
	if ok {
		m.userCredits[ride.UserID] += pl.AmountPerHead
	}

	return nil
}

func (m *mockPaymentLinkRepository) GetUserCreditBalance(ctx context.Context, userID string) (float64, error) {
	balance, ok := m.userCredits[userID]
	if !ok {
		return 0, domain.ErrUserNotFound
	}
	return balance, nil
}

func TestGeneratePaymentLink_Success(t *testing.T) {
	groupID := "g1"
	mRides := map[string]*domain.Ride{
		"r1": {ID: "r1", UserID: "u1", Status: "completata", GroupID: &groupID},
		"r2": {ID: "r2", UserID: "u1", Status: "completata", GroupID: &groupID},
	}
	repo := &mockPaymentLinkRepository{
		rides:        mRides,
		paymentLinks: make(map[string]*domain.PaymentLink),
		userCredits:  map[string]float64{"u1": 0.0},
	}
	uc := usecase.NewPaymentLinkUsecase(repo)

	pl, err := uc.Generate(context.Background(), "u1", "r1")
	if err != nil {
		t.Fatalf("failed to generate payment link: %v", err)
	}

	if pl.Participants != 2 {
		t.Errorf("expected 2 participants, got %d", pl.Participants)
	}
	// Ciascuna corsa costa 5.50 (vedi GetGroupRidesDetails), totale = 11.00. Per head = 5.50.
	if pl.TotalAmount != 11.00 {
		t.Errorf("expected 11.00 total amount, got %f", pl.TotalAmount)
	}
	if pl.AmountPerHead != 5.50 {
		t.Errorf("expected 5.50 per head, got %f", pl.AmountPerHead)
	}
	if pl.Status != "active" {
		t.Errorf("expected status active, got %s", pl.Status)
	}
}

func TestGeneratePaymentLink_NotCompleted(t *testing.T) {
	groupID := "g1"
	mRides := map[string]*domain.Ride{
		"r1": {ID: "r1", UserID: "u1", Status: "attiva", GroupID: &groupID},
	}
	repo := &mockPaymentLinkRepository{
		rides:        mRides,
		paymentLinks: make(map[string]*domain.PaymentLink),
	}
	uc := usecase.NewPaymentLinkUsecase(repo)

	_, err := uc.Generate(context.Background(), "u1", "r1")
	if err == nil {
		t.Fatal("expected error for uncompleted ride, got nil")
	}
	expectedErr := "la corsa deve essere completata per generare un link di pagamento"
	if err.Error() != expectedErr {
		t.Errorf("expected error %q, got %q", expectedErr, err.Error())
	}
}

func TestGeneratePaymentLink_NotGroupRide(t *testing.T) {
	mRides := map[string]*domain.Ride{
		"r1": {ID: "r1", UserID: "u1", Status: "completata", GroupID: nil},
	}
	repo := &mockPaymentLinkRepository{
		rides:        mRides,
		paymentLinks: make(map[string]*domain.PaymentLink),
	}
	uc := usecase.NewPaymentLinkUsecase(repo)

	_, err := uc.Generate(context.Background(), "u1", "r1")
	if err == nil {
		t.Fatal("expected error for non-group ride, got nil")
	}
	expectedErr := "la corsa selezionata non fa parte di un noleggio di gruppo"
	if err.Error() != expectedErr {
		t.Errorf("expected error %q, got %q", expectedErr, err.Error())
	}
}

func TestPayPaymentLink_Success(t *testing.T) {
	groupID := "g1"
	mRides := map[string]*domain.Ride{
		"r1": {ID: "r1", UserID: "u1", Status: "completata", GroupID: &groupID},
	}
	repo := &mockPaymentLinkRepository{
		rides:        mRides,
		paymentLinks: make(map[string]*domain.PaymentLink),
		userCredits:  map[string]float64{"u1": 0.0},
	}
	uc := usecase.NewPaymentLinkUsecase(repo)

	pl, err := uc.Generate(context.Background(), "u1", "r1")
	if err != nil {
		t.Fatalf("failed to generate payment link: %v", err)
	}

	err = uc.Pay(context.Background(), pl.ID)
	if err != nil {
		t.Fatalf("payment failed: %v", err)
	}

	updatedPl, _ := uc.Get(context.Background(), pl.ID)
	if updatedPl.Status != "paid" {
		t.Errorf("expected status paid, got %s", updatedPl.Status)
	}

	// Verifica accredito credito (1 partecipante in mRides, quindi per head = 5.50)
	balance, _ := uc.GetUserCreditBalance(context.Background(), "u1")
	if balance != 5.50 {
		t.Errorf("expected credit balance 5.50, got %f", balance)
	}
}

func TestGetPaymentLink_Expired(t *testing.T) {
	groupID := "g1"
	mRides := map[string]*domain.Ride{
		"r1": {ID: "r1", UserID: "u1", Status: "completata", GroupID: &groupID},
	}
	repo := &mockPaymentLinkRepository{
		rides:        mRides,
		paymentLinks: make(map[string]*domain.PaymentLink),
	}
	uc := usecase.NewPaymentLinkUsecase(repo)

	pl, err := uc.Generate(context.Background(), "u1", "r1")
	if err != nil {
		t.Fatalf("failed to generate: %v", err)
	}

	// Forza scadenza
	pl.ValidUntil = time.Now().Add(-1 * time.Minute)

	fetchedPl, err := uc.Get(context.Background(), pl.ID)
	if err != nil {
		t.Fatalf("failed to get: %v", err)
	}

	if fetchedPl.Status != "expired" {
		t.Errorf("expected status expired, got %s", fetchedPl.Status)
	}
}
