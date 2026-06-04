// Package users gestisce i profili utente (utenti finali e operatori).
//
// Handler espone gli endpoint HTTP:
//   GET  /users/:id        — profilo utente
//   PUT  /users/:id        — aggiornamento profilo
//   GET  /users            — lista utenti (solo admin)
//   PUT  /users/:id/role   — cambio ruolo (solo admin)
//
// TODO: implementare gli handler.
package users
