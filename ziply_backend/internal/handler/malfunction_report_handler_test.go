package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/lorisforse/ziply_backend/internal/domain"
	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/usecase"
)

// mockMalfunctionRepo implementa usecase.MalfunctionReportRepository per i test
// degli endpoint operatore (OP.03 / UC-26).
type mockMalfunctionRepo struct {
	reports       []domain.OperatorMalfunctionReport
	lastStatusArg string
	updateErr     error
	updatedID     string
	updatedStatus string
}

func (m *mockMalfunctionRepo) GetRideDetails(ctx context.Context, rideID string) (*domain.Ride, error) {
	return nil, domain.ErrRideNotFound
}

func (m *mockMalfunctionRepo) Create(ctx context.Context, report *domain.MalfunctionReport) error {
	return nil
}

func (m *mockMalfunctionRepo) ListAll(ctx context.Context, statusFilter string) ([]domain.OperatorMalfunctionReport, error) {
	m.lastStatusArg = statusFilter
	return m.reports, nil
}

func (m *mockMalfunctionRepo) UpdateStatus(ctx context.Context, reportID, newStatus string) error {
	if m.updateErr != nil {
		return m.updateErr
	}
	m.updatedID = reportID
	m.updatedStatus = newStatus
	return nil
}

func newMalfunctionMux(repo *mockMalfunctionRepo) *http.ServeMux {
	uc := usecase.NewMalfunctionReportUsecase(repo)
	h := handler.NewMalfunctionReportHandler(uc)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /operator/malfunction-reports", h.ListForOperator)
	mux.HandleFunc("PATCH /operator/malfunction-reports/{id}", h.UpdateStatus)
	return mux
}

func TestListForOperator_OK(t *testing.T) {
	repo := &mockMalfunctionRepo{
		reports: []domain.OperatorMalfunctionReport{
			{ID: "rep1", VehicleID: "v1", VehicleQR: "ZP-SCOOTER-001", ProblemType: "freni", Source: "utente", Status: "in_attesa"},
		},
	}
	mux := newMalfunctionMux(repo)

	req := httptest.NewRequest("GET", "/operator/malfunction-reports?status=in_attesa", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	if repo.lastStatusArg != "in_attesa" {
		t.Errorf("expected status filter 'in_attesa' propagato al repo, got %q", repo.lastStatusArg)
	}
	var got []domain.OperatorMalfunctionReport
	if err := json.Unmarshal(rr.Body.Bytes(), &got); err != nil {
		t.Fatalf("risposta non decodificabile: %v", err)
	}
	if len(got) != 1 || got[0].VehicleQR != "ZP-SCOOTER-001" {
		t.Fatalf("expected 1 report ZP-SCOOTER-001, got %+v", got)
	}
}

func TestListForOperator_InvalidStatus(t *testing.T) {
	mux := newMalfunctionMux(&mockMalfunctionRepo{})

	req := httptest.NewRequest("GET", "/operator/malfunction-reports?status=inesistente", nil)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rr.Code)
	}
}

func TestUpdateStatus_OK(t *testing.T) {
	repo := &mockMalfunctionRepo{}
	mux := newMalfunctionMux(repo)

	body := strings.NewReader(`{"status":"risolto"}`)
	req := httptest.NewRequest("PATCH", "/operator/malfunction-reports/rep1", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rr.Code)
	}
	if repo.updatedID != "rep1" || repo.updatedStatus != "risolto" {
		t.Errorf("expected update (rep1, risolto), got (%q, %q)", repo.updatedID, repo.updatedStatus)
	}
}

func TestUpdateStatus_InvalidTransition(t *testing.T) {
	repo := &mockMalfunctionRepo{}
	mux := newMalfunctionMux(repo)

	// 'in_attesa' non è una transizione ammessa: deve essere respinta prima del repo.
	body := strings.NewReader(`{"status":"in_attesa"}`)
	req := httptest.NewRequest("PATCH", "/operator/malfunction-reports/rep1", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rr.Code)
	}
	if repo.updatedID != "" {
		t.Errorf("il repository non doveva essere invocato, got id %q", repo.updatedID)
	}
}

func TestUpdateStatus_NotFound(t *testing.T) {
	repo := &mockMalfunctionRepo{updateErr: domain.ErrMalfunctionReportNotFound}
	mux := newMalfunctionMux(repo)

	body := strings.NewReader(`{"status":"risolto"}`)
	req := httptest.NewRequest("PATCH", "/operator/malfunction-reports/inesistente", body)
	rr := httptest.NewRecorder()
	mux.ServeHTTP(rr, req)

	if rr.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rr.Code)
	}
}
