package domain

// Tipologie suggerite da UT.08 in base al tragitto verso la destinazione.
const (
	SuggestionCar   = "auto"         // percorsi lunghi: si consiglia l'auto
	SuggestionLight = "bici_scooter" // percorsi brevi: bici o monopattino
)

// VehicleSuggestion è il suggerimento di tipologia di mezzo per un tragitto
// (UT.08): la categoria consigliata e la distanza su cui si basa il consiglio.
type VehicleSuggestion struct {
	Type           string // SuggestionCar | SuggestionLight
	DistanceMeters float64
}
