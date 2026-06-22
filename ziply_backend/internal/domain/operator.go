package domain

// OperatorVehicle rappresenta un mezzo della flotta dal punto di vista
// dell'operatore (OP.01): a differenza di Vehicle, esposto agli utenti finali
// con i soli mezzi disponibili, include lo stato operativo completo
// (disponibile, prenotato, in_uso, manutenzione) per il monitoraggio in tempo
// reale della flotta.
type OperatorVehicle struct {
	ID              string  `json:"id"`
	Type            string  `json:"type"`
	QrCode          string  `json:"qr_code"`
	Latitude        float64 `json:"latitude"`
	Longitude       float64 `json:"longitude"`
	BatteryLevel    int     `json:"battery_level"`
	TariffaAlMinuto float64 `json:"tariffa_al_minuto"`
	Status          string  `json:"status"`
}
