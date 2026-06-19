package domain

// Tipologie suggerite da UT.08 in base alla distanza del tragitto. Il
// suggerimento è incluso nella risposta del calcolo percorso (vedi RouteResult).
const (
	SuggestionCar   = "auto"         // percorsi lunghi: si consiglia l'auto
	SuggestionLight = "bici_scooter" // percorsi brevi: bici o monopattino
)
