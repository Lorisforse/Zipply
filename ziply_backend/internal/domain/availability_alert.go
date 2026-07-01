package domain

import "time"

// Tipologie di avviso ospitate da availability_alerts (OP.02 / OP.07).
const (
	AlertTypeScarsita  = "scarsita"
	AlertTypeBatteria  = "batteria"
	AlertTypeMovimento = "movimento"
)

// Soglie usate dal worker di rilevamento anomalie.
const (
	// LowBatteryThreshold: sotto questa percentuale un mezzo disponibile o
	// prenotato genera un avviso batteria scarica.
	LowBatteryThreshold = 20
	// IllicitMovementMeters: spostamento oltre questa distanza per un mezzo
	// non in uso viene considerato un movimento illecito.
	IllicitMovementMeters = 200.0
	// AlertDedupeWindow: non si genera un nuovo avviso batteria/scarsita' per
	// lo stesso mezzo/area se ne esiste gia' uno piu' recente di questa finestra,
	// per evitare di spammare il log ad ogni ciclo del worker.
	AlertDedupeWindow = 30 * time.Minute
)

// AvailabilityAlert rappresenta una riga di availability_alerts. A seconda di
// Type e' popolato ServiceAreaID+AvailableCount (scarsita) oppure VehicleID
// (batteria, movimento); l'avviso e' un log di sola lettura, senza stato di
// risoluzione (nessuna azione operatore prevista, vedi UC-25).
type AvailabilityAlert struct {
	ID             string
	Type           string
	ServiceAreaID  *string
	VehicleID      *string
	AvailableCount *int
	Message        string
	CreatedAt      time.Time
}

// ServiceAreaCenter descrive l'area di servizio come cerchio (centro + raggio
// in metri), la stessa convenzione di ParkingZoneCenter: riusa la formula di
// Haversine invece di richiedere un vero point-in-polygon.
type ServiceAreaCenter struct {
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
	Radius float64 `json:"radius"`
}

// ServiceArea rappresenta un'area di servizio con soglia minima di mezzi
// disponibili (UC-25 / OP.02).
type ServiceArea struct {
	ID          string
	Name        string
	Center      ServiceAreaCenter
	MinVehicles int
	IsActive    bool
}

// VehicleBatteryStatus e' la proiezione di un mezzo necessaria al controllo
// batteria scarica, con QR code e tipologia per un messaggio leggibile.
type VehicleBatteryStatus struct {
	VehicleID    string
	BatteryLevel int
	QrCode       string
	VehicleType  string
}
