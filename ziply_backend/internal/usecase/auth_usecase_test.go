package usecase_test

import (
	"context"
	"errors"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

type mockUserRepository struct {
	users     map[string]*domain.User
	createErr error
}

func (m *mockUserRepository) FindByEmail(ctx context.Context, email string) (*domain.User, error) {
	for _, u := range m.users {
		if u.Email == email {
			return u, nil
		}
	}
	return nil, domain.ErrUserNotFound
}

func (m *mockUserRepository) Create(ctx context.Context, u *domain.User) error {
	if m.createErr != nil {
		return m.createErr
	}
	u.ID = "test-user-id"
	m.users[u.Email] = u
	return nil
}

func TestRegister(t *testing.T) {
	repo := &mockUserRepository{users: make(map[string]*domain.User)}
	uc := usecase.NewAuthUsecase(repo)

	// Test validation error: empty name
	_, _, err := uc.Register(context.Background(), "", "Rossi", "test@test.com", "password123")
	if err == nil {
		t.Fatal("expected validation error for empty name")
	}

	// Test successful registration
	user, token, err := uc.Register(context.Background(), "Mario", "Rossi", "test@test.com", "password123")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if user.Email != "test@test.com" || token == "" {
		t.Fatalf("invalid user or token returned")
	}

	// Test validation error: password too short
	_, _, err = uc.Register(context.Background(), "Mario", "Rossi", "test2@test.com", "123")
	if err == nil {
		t.Fatal("expected error for short password")
	}
}

func TestLogin(t *testing.T) {
	repo := &mockUserRepository{users: make(map[string]*domain.User)}
	uc := usecase.NewAuthUsecase(repo)

	// Register a user first
	_, _, err := uc.Register(context.Background(), "Mario", "Rossi", "login@test.com", "password123")
	if err != nil {
		t.Fatalf("failed to register user: %v", err)
	}

	// Test successful login
	u, token, err := uc.Login(context.Background(), "login@test.com", "password123")
	if err != nil {
		t.Fatalf("login failed: %v", err)
	}
	if u.Email != "login@test.com" || token == "" {
		t.Fatal("invalid login result")
	}

	// Test invalid password
	_, _, err = uc.Login(context.Background(), "login@test.com", "wrongpassword")
	if !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("expected ErrInvalidCredentials, got %v", err)
	}

	// Test non-existent email
	_, _, err = uc.Login(context.Background(), "notfound@test.com", "password")
	if !errors.Is(err, domain.ErrInvalidCredentials) {
		t.Fatalf("expected ErrInvalidCredentials, got %v", err)
	}
}
