// Package main boots the Ziply REST API server.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

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

	// OP.02 / OP.07 — Rilevamento anomalie e avvisi: batteria scarica,
	// movimento illecito e scarsita' mezzi, persistiti in availability_alerts.
	availabilityAlertRepo := repository.NewAvailabilityAlertRepository(pool)
	availabilityAlertUsecase := usecase.NewAvailabilityAlertUsecase(availabilityAlertRepo)
	availabilityAlertHandler := handler.NewAvailabilityAlertHandler(availabilityAlertUsecase)
	availabilityAlertUsecase.StartWorker(ctx, 30*time.Second)

	vehicleRepo := repository.NewVehicleRepository(pool)
	vehicleUsecase := usecase.NewVehicleUsecase(vehicleRepo, availabilityAlertRepo)
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

	// OP.01 — Area operatore: monitoraggio in tempo reale della flotta.
	operatorRepo := repository.NewOperatorRepository(pool)
	operatorUsecase := usecase.NewOperatorUsecase(operatorRepo)
	operatorHandler := handler.NewOperatorHandler(operatorUsecase)

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

	// OP.01 — Mappa flotta in tempo reale. Riservata a operatori e amministrazione
	// pubblica: JWT valido + ruolo autorizzato (RequireRole).
	mux.Handle("GET /operator/vehicles", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.ListVehicles)),
	))

	// OP.11 — Blocco/sblocco remoto del mezzo (UC-32).
	mux.Handle("PATCH /operator/vehicles/{id}/block", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.BlockVehicle)),
	))
	mux.Handle("PATCH /operator/vehicles/{id}/unblock", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.UnblockVehicle)),
	))

	// OP.04 — Zone parcheggio designate (UC-27): lista e creazione/rimozione.
	mux.Handle("GET /operator/parking-zones", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.ListParkingZones)),
	))
	mux.Handle("POST /operator/parking-zones", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.CreateParkingZone)),
	))
	mux.Handle("DELETE /operator/parking-zones/{id}", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(operatorHandler.DeleteParkingZone)),
	))

	// OP.02 / OP.07 — Avvisi di anomalia (batteria, movimento, scarsita') e
	// simulazione telemetria GPS (non esiste hardware IoT reale, UC-25).
	mux.Handle("GET /operator/availability-alerts", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(availabilityAlertHandler.List)),
	))
	mux.Handle("PATCH /operator/vehicles/{id}/report-position", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(vehicleHandler.ReportPosition)),
	))

	// OP.03 — Gestione segnalazioni malfunzionamento (UC-26). Lista e
	// aggiornamento stato; riservati a operatore/amministrazione.
	mux.Handle("GET /operator/malfunction-reports", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(malfunctionHandler.ListForOperator)),
	))
	mux.Handle("PATCH /operator/malfunction-reports/{id}", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(malfunctionHandler.UpdateStatus)),
	))

	// UT.10 — Chat di assistenza ibrida bot/operatore
	chatRepo := repository.NewChatRepository(pool)
	chatUsecase := usecase.NewChatUsecase(chatRepo)
	chatHandler := handler.NewChatHandler(chatUsecase)
	mux.Handle("POST /chat/sessions", middleware.JWTAuth(http.HandlerFunc(chatHandler.GetOrCreateSession)))
	mux.Handle("POST /chat/sessions/{id}/messages", middleware.JWTAuth(http.HandlerFunc(chatHandler.SendMessage)))
	mux.Handle("GET /chat/sessions/{id}/messages", middleware.JWTAuth(http.HandlerFunc(chatHandler.GetMessages)))

	// OP.08 — Console operatore per l'escalation della chat di assistenza.
	// Coda condivisa: qualsiasi operatore/amministrazione collegato vede le
	// stesse sessioni scalate e puo' risponderne una qualsiasi.
	mux.Handle("GET /operator/chat/sessions", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(chatHandler.ListOperatorSessions)),
	))
	mux.Handle("GET /operator/chat/sessions/{id}/messages", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(chatHandler.GetOperatorMessages)),
	))
	mux.Handle("POST /operator/chat/sessions/{id}/messages", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(chatHandler.SendOperatorMessage)),
	))
	mux.Handle("PATCH /operator/chat/sessions/{id}/close", middleware.JWTAuth(
		middleware.RequireRole("operatore", "amministrazione")(http.HandlerFunc(chatHandler.CloseSession)),
	))

	// UT.22 — Abbonamenti per tipologia di mezzo
	subscriptionRepo := repository.NewSubscriptionRepository(pool)
	subscriptionUsecase := usecase.NewSubscriptionUsecase(subscriptionRepo)
	subscriptionHandler := handler.NewSubscriptionHandler(subscriptionUsecase)
	mux.Handle("GET /subscriptions", middleware.JWTAuth(http.HandlerFunc(subscriptionHandler.List)))
	mux.Handle("POST /subscriptions", middleware.JWTAuth(http.HandlerFunc(subscriptionHandler.Subscribe)))

	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "8080"
	}

	// Middleware attorno all'intero mux: CORS all'esterno (gestisce il preflight
	// OPTIONS per la dashboard web cross-origin, es. `flutter run -d chrome`),
	// poi Logging (una riga di log per chiamata: metodo, path, status, durata).
	handler := middleware.CORS(middleware.Logging(mux))

	log.Printf("[AUTH] server listening on :%s", port)
	if err := http.ListenAndServe(":"+port, handler); err != nil {
		log.Fatalf("[AUTH] server stopped: %v", err)
	}
}
