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

	// UT.07 — Calcolo percorso mezzo→destinazione via OpenRouteService.
	routeUsecase := usecase.NewRouteUsecase(vehicleRepo, forbiddenZoneRepo, ors.New())
	routeHandler := handler.NewRouteHandler(routeUsecase)

	// UT.08 — Suggerimento tipologia mezzo per il tragitto.
	suggestionUsecase := usecase.NewSuggestionUsecase()
	suggestionHandler := handler.NewSuggestionHandler(suggestionUsecase)

	mux := http.NewServeMux()

	// Public routes.
	mux.HandleFunc("POST /auth/register", authHandler.Register)
	mux.HandleFunc("POST /auth/login", authHandler.Login)
	mux.HandleFunc("GET /forbidden-zones", forbiddenZoneHandler.List)

	// Authenticated routes (JWT Bearer).
	mux.Handle("GET /vehicles", middleware.JWTAuth(http.HandlerFunc(vehicleHandler.List)))
	mux.Handle("POST /routes", middleware.JWTAuth(http.HandlerFunc(routeHandler.Compute)))
	mux.Handle("POST /suggest-vehicle", middleware.JWTAuth(http.HandlerFunc(suggestionHandler.Suggest)))
	mux.Handle("POST /bookings", middleware.JWTAuth(http.HandlerFunc(bookingHandler.Create)))
	mux.Handle("POST /bookings/{id}/cancel", middleware.JWTAuth(http.HandlerFunc(bookingHandler.Cancel)))
	mux.Handle("POST /rides/unlock", middleware.JWTAuth(http.HandlerFunc(rideHandler.Unlock)))
	mux.Handle("POST /rides/{id}/end", middleware.JWTAuth(http.HandlerFunc(rideHandler.End)))
	mux.Handle("POST /payment-methods", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.Create)))
	mux.Handle("GET /payment-methods", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.List)))
	mux.Handle("DELETE /payment-methods/{id}", middleware.JWTAuth(http.HandlerFunc(paymentMethodHandler.Delete)))

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
