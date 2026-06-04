// Package vehicles gestisce il parco veicoli della flotta Ziply.
//
// Handler espone gli endpoint HTTP:
//   GET    /vehicles          — lista veicoli (con filtri: tipo, zona, disponibilità)
//   GET    /vehicles/:id      — dettaglio singolo veicolo
//   POST   /vehicles          — aggiunta veicolo (solo operatori)
//   PUT    /vehicles/:id      — aggiornamento stato veicolo
//   DELETE /vehicles/:id      — rimozione veicolo (solo admin)
//
// TODO: implementare gli handler.
package vehicles
