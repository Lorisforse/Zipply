// Package jwt creates and validates the HS256 tokens used by the Ziply API.
package jwt

import (
	"errors"
	"os"
	"time"

	jwtlib "github.com/golang-jwt/jwt/v5"
)

// Claims carries the identity information embedded in every Ziply token.
type Claims struct {
	Email string `json:"email"`
	Ruolo string `json:"ruolo"`
	jwtlib.RegisteredClaims
}

// GenerateToken signs an HS256 JWT carrying sub, email, ruolo, iat and a 24h exp.
func GenerateToken(userID, email, ruolo string) (string, error) {
	now := time.Now()
	claims := Claims{
		Email: email,
		Ruolo: ruolo,
		RegisteredClaims: jwtlib.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwtlib.NewNumericDate(now),
			ExpiresAt: jwtlib.NewNumericDate(now.Add(24 * time.Hour)),
		},
	}
	token := jwtlib.NewWithClaims(jwtlib.SigningMethodHS256, claims)
	return token.SignedString([]byte(os.Getenv("JWT_SECRET")))
}

// ValidateToken parses the token string and returns its claims when the signature and expiry are valid.
func ValidateToken(tokenString string) (*Claims, error) {
	token, err := jwtlib.ParseWithClaims(tokenString, &Claims{}, func(t *jwtlib.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwtlib.SigningMethodHMAC); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return []byte(os.Getenv("JWT_SECRET")), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid token")
	}
	return claims, nil
}
