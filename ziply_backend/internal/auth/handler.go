// Package auth gestisce l'autenticazione degli utenti.
//
// Handler espone gli endpoint HTTP:
//   POST /auth/register  — registrazione nuovo utente
//   POST /auth/login     — login e rilascio JWT
//   POST /auth/refresh   — rinnovo del token
//   POST /auth/logout    — invalidazione del token
//
// TODO: implementare gli handler.
package auth
