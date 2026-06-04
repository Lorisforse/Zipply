// Package payments gestisce i pagamenti e la fatturazione.
//
// Handler espone gli endpoint HTTP:
//   POST /payments           — avvio pagamento per una corsa
//   GET  /payments/:id       — dettaglio transazione
//   GET  /users/:id/payments — storico pagamenti utente
//
// TODO: implementare gli handler (integrazione con gateway di pagamento).
package payments
