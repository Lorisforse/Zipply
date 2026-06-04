// Package database gestisce la connessione al database PostgreSQL tramite lib/pq.
//
// Espone una funzione Connect() che legge le variabili d'ambiente (DB_HOST, DB_PORT,
// DB_NAME, DB_USER, DB_PASSWORD) e restituisce un *sql.DB pronto all'uso.
//
// TODO: implementare la connessione con retry e connection pool.
package database
