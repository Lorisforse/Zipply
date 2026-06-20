package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
)

// ── Mock repository ──────────────────────────────────────────────────────────

type mockBookingRepo struct {
	scheduledErr error // se valorizzato, CreateScheduled lo restituisce
}

func (m *mockBookingRepo) Create(_ context.Context, userID, vehicleID, _ string, expiresAt time.Time) (*domain.Booking, error) {
	return &domain.Booking{ID: "b1", UserID: userID, VehicleID: vehicleID, ExpiresAt: expiresAt, Status: "attiva"}, nil
}

func (m *mockBookingRepo) CreateMulti(_ context.Context, userID string, vehicleIDs []string, expiresAt time.Time) ([]*domain.Booking, string, error) {
	return nil, "", nil
}

func (m *mockBookingRepo) CreateScheduled(_ context.Context, userID, vehicleID string, scheduledStart, expiresAt time.Time) (*domain.Booking, float64, error) {
	if m.scheduledErr != nil {
		return nil, 0, m.scheduledErr
	}
	b := &domain.Booking{
		ID:             "bs1",
		UserID:         userID,
		VehicleID:      vehicleID,
		ExpiresAt:      expiresAt,
		Status:         "attiva",
		ScheduledStart: &scheduledStart,
	}
	return b, 4.50, nil
}

func (m *mockBookingRepo) Expire(_ context.Context, _, _ string) error    { return nil }
func (m *mockBookingRepo) Cancel(_ context.Context, _, _ string) error    { return nil }

// ── Helpers ──────────────────────────────────────────────────────────────────

// withUser inietta l'userID nel contesto della request, simulando il middleware JWT.
func withUser(r *http.Request, userID string) *http.Request {
	ctx := context.WithValue(r.Context(), middleware.CtxUserID, userID)
	return r.WithContext(ctx)
}

func newScheduledMux(repo *mockBookingRepo) *http.ServeMux {
	uc := usecase.NewBookingUsecase(repo)
	h := handler.NewBookingHandler(uc)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /bookings/scheduled", func(w http.ResponseWriter, r *http.Request) {
		h.CreateScheduled(w, r)
	})
	return mux
}

// validScheduledBody costruisce un body JSON con scheduled_start 1h nel futuro.
func validScheduledBody() string {
	t := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	return `{"vehicle_id":"v1","scheduled_start":"` + t + `"}`
}

// ── Test cases ────────────────────────────────────────────────────────────────

func TestCreateScheduled_OK(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(validScheduledBody()))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d — body: %s", rr.Code, rr.Body.String())
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(rr.Body.Bytes(), &resp); err != nil {
		t.Fatalf("invalid JSON response: %v", err)
	}

	booking, ok := resp["booking"].(map[string]interface{})
	if !ok {
		t.Fatal("response missing 'booking' object")
	}
	if booking["id"] != "bs1" {
		t.Errorf("booking.id = %v, want bs1", booking["id"])
	}
	if booking["vehicle_id"] != "v1" {
		t.Errorf("booking.vehicle_id = %v, want v1", booking["vehicle_id"])
	}
	if booking["scheduled_start"] == "" || booking["scheduled_start"] == nil {
		t.Error("booking.scheduled_start should be set")
	}
	if booking["expires_at"] == "" || booking["expires_at"] == nil {
		t.Error("booking.expires_at should be set")
	}
	if resp["pre_auth_amount"] == nil {
		t.Error("response missing pre_auth_amount")
	}
	if resp["pre_auth_amount"].(float64) != 4.50 {
		t.Errorf("pre_auth_amount = %.2f, want 4.50", resp["pre_auth_amount"])
	}
}

func TestCreateScheduled_MissingVehicleID(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	body := `{"scheduled_start":"` + time.Now().Add(time.Hour).UTC().Format(time.RFC3339) + `"}`
	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rr.Code)
	}
}

func TestCreateScheduled_InvalidDateFormat(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	body := `{"vehicle_id":"v1","scheduled_start":"not-a-date"}`
	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", rr.Code)
	}
}

func TestCreateScheduled_NoAuth(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	// Request senza userID nel contesto (no middleware JWT).
	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(validScheduledBody()))
	req.Header.Set("Content-Type", "application/json")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnauthorized {
		t.Errorf("expected 401, got %d", rr.Code)
	}
}

// TestCreateScheduled_TooSoon: l'orario è nel passato o troppo vicino → 422.
// Il usecase valida il timing prima di chiamare il repository.
func TestCreateScheduled_TooSoon(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	// scheduled_start tra 5 minuti: sotto la soglia di 15 min.
	t5m := time.Now().Add(5 * time.Minute).UTC().Format(time.RFC3339)
	body := `{"vehicle_id":"v1","scheduled_start":"` + t5m + `"}`
	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d — body: %s", rr.Code, rr.Body.String())
	}
	assertErrorContains(t, rr.Body.String(), "15 minuti")
}

// TestCreateScheduled_TooFar: l'orario è oltre la fine del giorno successivo → 422.
func TestCreateScheduled_TooFar(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{})

	// Dopodomani: sempre oltre la fine del giorno successivo.
	t2d := time.Now().AddDate(0, 0, 2).UTC().Format(time.RFC3339)
	body := `{"vehicle_id":"v1","scheduled_start":"` + t2d + `"}`
	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d — body: %s", rr.Code, rr.Body.String())
	}
	assertErrorContains(t, rr.Body.String(), "giorno successivo")
}

// TestCreateScheduled_VehicleTypeNotSchedulable: repo rifiuta il monopattino → 422.
func TestCreateScheduled_VehicleTypeNotSchedulable(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{scheduledErr: domain.ErrVehicleTypeNotSchedulable})

	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(validScheduledBody()))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusUnprocessableEntity {
		t.Errorf("expected 422, got %d", rr.Code)
	}
	assertErrorContains(t, rr.Body.String(), "bici")
}

// TestCreateScheduled_VehicleNotAvailable: mezzo non disponibile → 409.
func TestCreateScheduled_VehicleNotAvailable(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{scheduledErr: domain.ErrVehicleNotAvailable})

	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(validScheduledBody()))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusConflict {
		t.Errorf("expected 409, got %d", rr.Code)
	}
}

// TestCreateScheduled_ActiveBookingExists: l'utente ha già una prenotazione attiva → 409.
func TestCreateScheduled_ActiveBookingExists(t *testing.T) {
	mux := newScheduledMux(&mockBookingRepo{scheduledErr: domain.ErrActiveBookingExists})

	req := httptest.NewRequest("POST", "/bookings/scheduled", strings.NewReader(validScheduledBody()))
	req.Header.Set("Content-Type", "application/json")
	req = withUser(req, "u1")
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusConflict {
		t.Errorf("expected 409, got %d", rr.Code)
	}
	assertErrorContains(t, rr.Body.String(), "prenotazione")
}

// assertErrorContains verifica che il body JSON contenga la substring nel campo "error".
func assertErrorContains(t *testing.T, body, substr string) {
	t.Helper()
	var resp map[string]string
	if err := json.Unmarshal([]byte(body), &resp); err != nil {
		t.Fatalf("invalid JSON in error response: %v — body: %s", err, body)
	}
	msg := resp["error"]
	if !strings.Contains(msg, substr) {
		t.Errorf("error message %q does not contain %q", msg, substr)
	}
}
