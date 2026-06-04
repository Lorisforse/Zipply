// Package reports genera i report di utilizzo per l'amministrazione pubblica.
//
// Handler espone gli endpoint HTTP:
//   GET /reports/usage      — utilizzo flotta per periodo
//   GET /reports/revenue    — ricavi per periodo e zona
//   GET /reports/heatmap    — dati mappa calore per le corse
//   GET /reports/vehicles   — stato flotta e manutenzioni
//
// TODO: implementare gli handler (solo ruolo admin/operator).
package reports
