// Package bookings gestisce le prenotazioni e le corse degli utenti.
//
// Handler espone gli endpoint HTTP:
//   POST /bookings           — creazione prenotazione
//   GET  /bookings/:id       — dettaglio prenotazione
//   PUT  /bookings/:id/start — avvio corsa (sblocco veicolo)
//   PUT  /bookings/:id/end   — fine corsa (blocco veicolo + calcolo costo)
//   GET  /users/:id/bookings — storico corse utente
//
// TODO: implementare gli handler.
package bookings
