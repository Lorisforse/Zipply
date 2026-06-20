package handler_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockPaymentLinkRepository implementa usecase.PaymentLinkRepository per i test.
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
			total += 10.0
		}
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
	return nil
}

func (m *mockPaymentLinkRepository) GetUserCreditBalance(ctx context.Context, userID string) (float64, error) {
	return m.userCredits[userID], nil
}

func TestShowPayWeb_Active(t *testing.T) {
	repo := &mockPaymentLinkRepository{
		rides:        make(map[string]*domain.Ride),
		paymentLinks: make(map[string]*domain.PaymentLink),
	}
	
	// Pre-popoliamo un link attivo
	repo.paymentLinks["pl123"] = &domain.PaymentLink{
		ID:            "pl123",
		RideID:        "r1",
		TotalAmount:   20.0,
		Participants:  2,
		AmountPerHead: 10.0,
		ValidUntil:    time.Now().Add(10 * time.Minute),
		Status:        "active",
	}

	uc := usecase.NewPaymentLinkUsecase(repo)
	h := handler.NewPaymentLinkHandler(uc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /payment-links/{id}/pay-web", h.ShowPayWeb)

	req := httptest.NewRequest("GET", "/payment-links/pl123/pay-web", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rr.Code)
	}

	body := rr.Body.String()
	if !strings.Contains(body, "Dividi Costo") {
		t.Errorf("expected body to contain 'Dividi Costo'")
	}
	if !strings.Contains(body, "Mario Rossi") {
		t.Errorf("expected body to contain conductor name 'Mario Rossi'")
	}
	if !strings.Contains(body, "10.00") {
		t.Errorf("expected body to contain amount '10.00'")
	}
}

func TestShowPayWeb_Expired(t *testing.T) {
	repo := &mockPaymentLinkRepository{
		rides:        make(map[string]*domain.Ride),
		paymentLinks: make(map[string]*domain.PaymentLink),
	}
	
	// Pre-popoliamo un link scaduto
	repo.paymentLinks["pl123"] = &domain.PaymentLink{
		ID:            "pl123",
		RideID:        "r1",
		TotalAmount:   20.0,
		Participants:  2,
		AmountPerHead: 10.0,
		ValidUntil:    time.Now().Add(-10 * time.Minute),
		Status:        "active", // il controller farà la scadenza dinamica
	}

	uc := usecase.NewPaymentLinkUsecase(repo)
	h := handler.NewPaymentLinkHandler(uc)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /payment-links/{id}/pay-web", h.ShowPayWeb)

	req := httptest.NewRequest("GET", "/payment-links/pl123/pay-web", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	body := rr.Body.String()
	if !strings.Contains(body, "Questo link di pagamento è scaduto") {
		t.Errorf("expected body to contain error message about expiration, got: %s", body)
	}
}

func TestProcessPayWeb_Success(t *testing.T) {
	groupID := "g1"
	repo := &mockPaymentLinkRepository{
		rides: map[string]*domain.Ride{
			"r1": {ID: "r1", UserID: "u1", Status: "completata", GroupID: &groupID},
		},
		paymentLinks: make(map[string]*domain.PaymentLink),
		userCredits:  make(map[string]float64),
	}
	
	repo.paymentLinks["pl123"] = &domain.PaymentLink{
		ID:            "pl123",
		RideID:        "r1",
		TotalAmount:   20.0,
		Participants:  2,
		AmountPerHead: 10.0,
		ValidUntil:    time.Now().Add(10 * time.Minute),
		Status:        "active",
	}

	uc := usecase.NewPaymentLinkUsecase(repo)
	h := handler.NewPaymentLinkHandler(uc)

	mux := http.NewServeMux()
	mux.HandleFunc("POST /payment-links/{id}/pay-web", h.ProcessPayWeb)

	req := httptest.NewRequest("POST", "/payment-links/pl123/pay-web", nil)
	rr := httptest.NewRecorder()

	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rr.Code)
	}

	body := rr.Body.String()
	if !strings.Contains(body, "Pagamento Completato") {
		t.Errorf("expected body to contain success message, got: %s", body)
	}

	// Verifica lo stato aggiornato del pagamento
	pl := repo.paymentLinks["pl123"]
	if pl.Status != "paid" {
		t.Errorf("expected payment link status to be 'paid', got %s", pl.Status)
	}
}
