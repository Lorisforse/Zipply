package domain

import "errors"

// OperatorVehicle rappresenta un mezzo della flotta dal punto di vista
// dell'operatore (OP.01): a differenza di Vehicle, esposto agli utenti finali
// con i soli mezzi disponibili, include lo stato operativo completo
// (disponibile, prenotato, in_uso, manutenzione, bloccato) per il monitoraggio
// in tempo reale della flotta.
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

// ParkingZoneCenter descrive il cerchio di una zona parcheggio designata:
// centro (Lat/Lng) e Radius in metri.
type ParkingZoneCenter struct {
	Lat    float64 `json:"lat"`
	Lng    float64 `json:"lng"`
	Radius float64 `json:"radius"`
}

// ParkingZone rappresenta un'area parcheggio designata (OP.04 / UC-27).
// Il campo Center viene serializzato nel DB come JSONB (polygon).
type ParkingZone struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Center      ParkingZoneCenter `json:"center"`
	BonusCredit float64           `json:"bonus_credit"`
	IsActive    bool              `json:"is_active"`
}

var ErrParkingZoneNotFound = errors.New("zona parcheggio non trovata")
