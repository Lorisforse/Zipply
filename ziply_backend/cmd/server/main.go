// Package main boots the Ziply REST API server.
package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/lorisforse/ziply_backend/internal/handler"
	"github.com/lorisforse/ziply_backend/internal/repository"
	"github.com/lorisforse/ziply_backend/internal/usecase"
	"github.com/lorisforse/ziply_backend/pkg/database"
	"github.com/lorisforse/ziply_backend/pkg/middleware"
	"github.com/lorisforse/ziply_backend/pkg/ors"
)

// main wires the layers together and starts the HTTP server.
func main() {
	ctx := context.Background()

	pool, err := database.Connect(ctx)
	if err != nil {
		log.Fatalf("[AUTH] database connection failed: %v", err)
	}
	defer pool.Close()

	userRepo := repository.NewUserRepository(pool)
	authUsecase := usecase.NewAuthUsecase(userRepo)
	authHandler := handler.NewAuthHandler(authUsecase)

	vehicleRepo := repository.NewVehicleRepository(pool)
	vehicleUsecase := usecase.NewVehicleUsecase(vehicleRepo)
	vehicleHandler := handler.NewVehicleHandler(vehicleUsecase)

	bookingRepo := repository.NewBookingRepository(pool)
	bookingUsecase := usecase.NewBookingUsecase(bookingRepo)
	bookingHandler := handler.NewBookingHandler(bookingUsecase)

	forbiddenZoneRepo := repository.NewForbiddenZoneRepository(pool)
	forbiddenZoneUsecase := usecase.NewForbiddenZoneUsecase(forbiddenZoneRepo)
	forbiddenZoneHandler := handler.NewForbiddenZoneHandler(forbiddenZoneUsecase)

	paymentMethodRepo := repository.NewPaymentMethodRepository(pool)
	paymentMethodUsecase := usecase.NewPaymentMethodUsecase(paymentMethodRepo)
	paymentMethodHandler := handler.NewPaymentMethodHandler(paymentMethodUsecase)

	rideRepo := repository.NewRideRepository(pool)
	rideUsecase := usecase.NewRideUsecase(rideRepo)
	rideHandler := handler.NewRideHandler(rideUsecase)

	// Start the background sweeper for paused rides (> 24 hours)
	repository.StartSweeper(ctx, pool, rideRepo)

	// UT.09 — Validazione codici sconto inseriti in conferma prenotazione.
	discountRepo := repository.NewDiscountRepository(pool)
	discountUsecase := usecase.NewDiscountUsecase(discountRepo)
	discountHandler := handler.NewDiscountHandler(discountUsecase)

	// UT.23 — Link di pagamento e accredito credito.
	paymentLinkRepo := repository.NewPaymentLinkRepository(pool)
	paymentLinkUsecase := usecase.NewPaymentLinkUsecase(paymentLinkRepo)
	paymentLinkHandler := handler.NewPaymentLinkHandler(paymentLinkUsecase)

	// UT.11 — Segnalazione malfunzionamento.
	malfunctionRepo := repository.NewMalfunctionReportRepository(pool)
	malfunctionUsecase := usecase.NewMalfunctionReportUsecase(malfunctionRepo)
	malfunctionHandler := handler.NewMalfunctionReportHandler(malfunctionUsecase)

	// UT.07/03/08 — Percorso mezzo→destinazione via OpenRouteService, con stima
	// costo e suggerimento tipologia inclusi nella risposta.
	routeUsecase := usecase.NewRouteUsecase(vehicleRepo, forbiddenZoneRepo, ors.New(), discountRepo)
	routeHandler := handler.NewRouteHandler(routeUsecase)

	mux := http.NewServeMux()

	// Public routes.
	mux.HandleFunc("POST /auth/register", authHandler.Register)
	mux.HandleFunc("POST /auth/login", authHandler.Login)
	mux.HandleFunc("GET /forbidden-zones", forbiddenZoneHandler.List)
	mux.HandleFunc("GET /payment-links/{id}/pay-web", paymentLinkHandler.ShowPayWeb)
	mux.HandleFunc("POST /payment-links/{id}/pay-web", paymentLinkHandler.ProcessPayWeb)

	// Authenticated routes (JWT Bearer).
	mux.Handle("GET /vehicles", middleware.JWTAuth(http.HandlerFunc(vehicleHandler.List)))
	mux.Handle("POST /routes", middleware.JWTAuth(http.HandlerFunc(routeHandler.Compute)))
	mux.Handle("POST /discount-codes/validate", middleware.JWTAuth(http.HandlerFunc(discountHandler.Validate)))
	mux.Handle("POST /bookings", middleware.JWTAuth(http.HandlerFunc(bookingHandler.Create)))
	mux.Handle("POST /bookings/multi", middleware.JWTAuth(http.HandlerFunc(bookingHandler.CreateMulti)))
	mux.Handle("POST /bookings/scheduled", middleware.JWTAuth(http.HandlerFunc(bookingHandler.CreateScheduled)))
	mux.Handle("POST /bookings/{id}/cancel", middleware.JWTAuth(http.HandlerFunc(bookingHandler.Cancel)))
	mux.Handle("POST /rides/unlock", middleware.JWTAuth(http.HandlerFunc(rideHandler.Unlock)))
	mux.Handle("POST /rides/group/{id}/unlock", middleware.JWTAuth(http.HandlerFunc(rideHandler.UnlockGroup)))
	mux.Handle("POST /rides/group/{id}/end", middleware.JWTAuth(http.HandlerFunc(rideHandler.EndGroup)))
	mux.Handle("POST /rides/{id}/pause", middleware.JWTAuth(http.HandlerFunc(rideHandler.Pause)))
	mux.Handle("POST /rides/{id}/resume", middleware.JWTAuth(http.HandlerFunc(rideHandler.Resume)))
	mux.Handle("POST /rides/{id}/end", middleware.JWTAuth(http.HandlerFunc(rideHandler.End)))
	mux.Handle("POST /payment-methods", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.Create)))
	mux.Handle("GET /payment-methods", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.List)))
	mux.Handle("DELETE /payment-methods/{id}", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.Delete)))

	// UT.23 — Link di pagamento e accredito credito
	mux.Handle("POST /rides/{id}/payment-link", middleware.JWTAuth(http.HandlerFunc(paymentLinkHandler.Create)))
	mux.Handle("GET /payment-links/{id}", middleware.JWTAuth(http.HandlerFunc(paymentLinkHandler.Get)))
	mux.Handle("POST /payment-links/{id}/pay", middleware.JWTAuth(http.HandlerFunc(paymentLinkHandler.Pay)))
	mux.Handle("GET /users/credit-balance", middleware.JWTAuth(http.HandlerFunc(paymentLinkHandler.GetCreditBalance)))

	// UT.11 — Segnalazione malfunzionamento
	mux.Handle("POST /malfunction-reports", middleware.JWTAuth(http.HandlerFunc(malfunctionHandler.Create)))

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}

	// Logging middleware attorno all'intero mux: una riga di log per ogni
	// chiamata a un endpoint (metodo, path, status, durata).
	handler := middleware.Logging(mux)

	log.Printf("[AUTH] server listening on :%s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatalf("[AUTH] server stopped: %v", err)
	}
}
