package usecase_test

import (
	"context"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockPaymentMethodRepository struct {
	methods []domain.PaymentMethod
	deleted map[string]bool
}

func (m *mockPaymentMethodRepository) Create(ctx context.Context, userID, cardLastFour, cardExpiry string, isDefault bool) (*domain.PaymentMethod, error) {
	method := &domain.PaymentMethod{
		ID:           "pm-test-id",
		UserID:       userID,
		CardLastFour: cardLastFour,
		CardExpiry:   cardExpiry,
		IsDefault:    isDefault,
	}
	m.methods = append(m.methods, *method)
	return method, nil
}

func (m *mockPaymentMethodRepository) ListByUser(ctx context.Context, userID string) ([]domain.PaymentMethod, error) {
	return m.methods, nil
}

func (m *mockPaymentMethodRepository) Delete(ctx context.Context, id, userID string) error {
	m.deleted[id] = true
	var active []domain.PaymentMethod
	for _, pm := range m.methods {
		if pm.ID != id {
			active = append(active, pm)
		}
	}
	m.methods = active
	return nil
}

func TestPaymentMethodFlow(t *testing.T) {
	repo := &mockPaymentMethodRepository{
		deleted: make(map[string]bool),
	}
	uc := usecase.NewPaymentMethodUsecase(repo)

	// Test add
	pm, err := uc.Add(context.Background(), "u1", "1234", "12/28", true)
	if err != nil {
		t.Fatalf("failed to add payment method: %v", err)
	}
	if pm.ID != "pm-test-id" || pm.CardLastFour != "1234" {
		t.Fatal("invalid payment method created")
	}

	// Test list
	list, err := uc.List(context.Background(), "u1")
	if err != nil {
		t.Fatalf("failed to list: %v", err)
	}
	if len(list) != 1 || list[0].CardLastFour != "1234" {
		t.Fatal("expected payment method in list")
	}

	// Test delete
	err = uc.Delete(context.Background(), pm.ID, "u1")
	if err != nil {
		t.Fatalf("failed to delete: %v", err)
	}
	if !repo.deleted[pm.ID] {
		t.Fatal("method not marked deleted in repo")
	}
}
