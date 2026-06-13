package domain

// Vehicle represents a shared vehicle joined with its type, as exposed by the
// availability listing. TariffaAlMinuto is the per-minute fare taken from
// vehicle_types; the hourly rate shown to clients is derived from it.
type Vehicle struct {
	ID              string
	Type            string // vehicle_types.nome (es. 'Bicicletta')
	QrCode          string // codice stampato sul mezzo, usato per lo sblocco via QR
	Latitude        float64
	Longitude       float64
	BatteryLevel    int
	TariffaAlMinuto float64
}

// GeoFilter restricts the vehicle search to a circular area, expressed as a
// center (Lat, Lng) and a Radius in kilometers.
type GeoFilter struct {
	Lat    float64
	Lng    float64
	Radius float64
}
