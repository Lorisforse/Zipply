// Package utils fornisce funzioni di utilità per la gestione dei JWT
// tramite github.com/golang-jwt/jwt/v5.
//
// GenerateToken(userID, role string) — genera un access token con scadenza configurabile.
// ValidateToken(tokenString string) — verifica firma e scadenza, restituisce i claims.
// GenerateRefreshToken(userID string) — genera un refresh token a lunga scadenza.
//
// TODO: implementare le funzioni JWT.
package utils
