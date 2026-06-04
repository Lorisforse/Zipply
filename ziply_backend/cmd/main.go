// Package main è il punto di ingresso del backend Ziply.
//
// Responsabilità:
//   - Caricamento variabili d'ambiente tramite godotenv
//   - Connessione al database PostgreSQL
//   - Configurazione del router Gin con i middleware globali
//   - Registrazione di tutti i gruppi di route (auth, vehicles, bookings, payments, users, reports)
//   - Avvio del server HTTP sulla porta configurata (default :8080)
//
// TODO: implementare il bootstrap dell'applicazione.
package main
