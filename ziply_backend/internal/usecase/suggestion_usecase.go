package usecase

import "github.com/lorisforse/ziply_backend/internal/domain"

// suggestDistanceThresholdM è la soglia (in metri, distanza in linea d'aria)
// oltre la quale si consiglia l'auto e sotto la quale bici/monopattino.
// Euristica semplice di UT.08 basata sulla distanza dal mezzo alla destinazione.
const suggestDistanceThresholdM = 3000.0

// SuggestionUsecase implementa il suggerimento di tipologia mezzo (UT.08).
type SuggestionUsecase struct{}

// NewSuggestionUsecase crea un SuggestionUsecase.
func NewSuggestionUsecase() *SuggestionUsecase { return &SuggestionUsecase{} }

// Suggest consiglia la tipologia di mezzo in base alla distanza dal punto di
// partenza (la posizione del mezzo) alla destinazione: percorsi lunghi → auto,
// brevi → bici/monopattino. Riusa haversineMeters del package usecase.
func (uc *SuggestionUsecase) Suggest(fromLat, fromLng, destLat, destLng float64) domain.VehicleSuggestion {
	dist := haversineMeters(fromLat, fromLng, destLat, destLng)
	t := domain.SuggestionLight
	if dist >= suggestDistanceThresholdM {
		t = domain.SuggestionCar
	}
	return domain.VehicleSuggestion{Type: t, DistanceMeters: dist}
}
