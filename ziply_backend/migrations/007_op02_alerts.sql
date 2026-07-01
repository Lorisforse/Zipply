-- ============================================================
-- Ziply - Migration 007 (OP.02 / OP.07)
-- Rilevamento anomalie e avvisi: estende availability_alerts (creata in
-- 006_sprint3.sql per la sola scarsita' mezzi, UC-25) per ospitare anche gli
-- avvisi di batteria scarica e movimento illecito, entrambi legati a un
-- singolo mezzo invece che a un'area di servizio.
-- ============================================================

ALTER TABLE availability_alerts
    ALTER COLUMN service_area_id DROP NOT NULL,
    ALTER COLUMN available_count DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS type       VARCHAR(20) NOT NULL DEFAULT 'scarsita',
    ADD COLUMN IF NOT EXISTS vehicle_id UUID REFERENCES vehicles(id),
    ADD COLUMN IF NOT EXISTS message    TEXT;

ALTER TABLE availability_alerts DROP CONSTRAINT IF EXISTS availability_alert_type_valido;
ALTER TABLE availability_alerts ADD CONSTRAINT availability_alert_type_valido
    CHECK (type IN ('scarsita', 'batteria', 'movimento'));

-- service_areas e' modellata come cerchio (centro + raggio in metri), stessa
-- convenzione gia' usata da parking_zones (ParkingZoneCenter): il campo
-- polygon JSONB contiene {"lat":..,"lng":..,"radius":..} invece di una vera
-- geometria GeoJSON, per riusare la formula di Haversine gia' presente in
-- VehicleRepository.ListAvailable.
INSERT INTO service_areas (name, polygon, min_vehicles, is_active)
SELECT 'Centro citta'' (demo)', '{"lat":45.4654,"lng":9.1859,"radius":1000}', 3, true
WHERE NOT EXISTS (SELECT 1 FROM service_areas);
