// Package middleware fornisce i middleware Gin per l'autenticazione e l'autorizzazione.
//
// JWTAuthMiddleware() verifica il token Bearer nell'header Authorization,
// lo valida tramite pkg/utils/jwt e inietta i claims nel contesto Gin.
// RoleMiddleware(roles ...string) restringe l'accesso ai ruoli specificati.
//
// TODO: implementare i middleware.
package middleware
