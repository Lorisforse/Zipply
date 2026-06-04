package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/lorisforse/ziply_backend/internal/auth"
	"github.com/lorisforse/ziply_backend/pkg/database"
)

func main() {
	_ = godotenv.Load()

	db, err := database.Connect()
	if err != nil {
		log.Fatalf("connessione al database fallita: %v", err)
	}
	defer db.Close()

	repo := auth.NewRepository(db)
	svc := auth.NewService(repo)
	h := auth.NewHandler(svc)

	r := gin.Default()

	authGroup := r.Group("/auth")
	{
		authGroup.POST("/register", h.Register)
		authGroup.POST("/login", h.Login)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	if err := r.Run(":" + port); err != nil {
		log.Fatalf("avvio server fallito: %v", err)
	}
}
