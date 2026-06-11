// Package middleware provides the HTTP middleware shared across the API.
package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/lorisforse/ziply_backend/pkg/jwt"
)

// contextKey is a private type that avoids context key collisions.
type contextKey string

// Context keys under which the authenticated identity is stored.
const (
	CtxUserID contextKey = "user_id"
	CtxEmail  contextKey = "email"
	CtxRuolo  contextKey = "ruolo"
)

// JWTAuth rejects requests without a valid Bearer token and stores the claims in the request context.
func JWTAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "token mancante")
			return
		}
		claims, err := jwt.ValidateToken(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			writeError(w, http.StatusUnauthorized, "token non valido")
			return
		}
		ctx := context.WithValue(r.Context(), CtxUserID, claims.Subject)
		ctx = context.WithValue(ctx, CtxEmail, claims.Email)
		ctx = context.WithValue(ctx, CtxRuolo, claims.Ruolo)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// RequireRole allows the request only when the authenticated role matches one of the given roles.
func RequireRole(roles ...string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ruolo, _ := r.Context().Value(CtxRuolo).(string)
			for _, role := range roles {
				if role == ruolo {
					next.ServeHTTP(w, r)
					return
				}
			}
			writeError(w, http.StatusForbidden, "permessi insufficienti")
		})
	}
}

// writeError serializes a JSON error payload with the given status code.
func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}
