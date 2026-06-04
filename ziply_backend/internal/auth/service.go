package auth

import (
	"errors"

	"github.com/lorisforse/ziply_backend/pkg/utils"
	"golang.org/x/crypto/bcrypt"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

type RegisterInput struct {
	Nome     string `json:"nome"     binding:"required"`
	Cognome  string `json:"cognome"  binding:"required"`
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

type LoginInput struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (s *Service) Register(in RegisterInput) (string, error) {
	if _, err := s.repo.FindByEmail(in.Email); err == nil {
		return "", errors.New("email già registrata")
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), 12)
	if err != nil {
		return "", err
	}

	u := &User{
		Nome:         in.Nome,
		Cognome:      in.Cognome,
		Email:        in.Email,
		PasswordHash: string(hash),
		Ruolo:        "utente",
	}
	if err := s.repo.Create(u); err != nil {
		return "", err
	}

	return utils.GenerateToken(u.ID, u.Email, u.Ruolo)
}

func (s *Service) Login(in LoginInput) (string, error) {
	u, err := s.repo.FindByEmail(in.Email)
	if err != nil {
		return "", errors.New("credenziali non valide")
	}

	if err := bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(in.Password)); err != nil {
		return "", errors.New("credenziali non valide")
	}

	return utils.GenerateToken(u.ID, u.Email, u.Ruolo)
}
