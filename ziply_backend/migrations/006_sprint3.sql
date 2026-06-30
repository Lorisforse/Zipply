-- ============================================================
-- Ziply - Migration 006 (Sprint 3)
-- Nuove tabelle (aree di servizio, zone parcheggio, zone manutenzione,
-- segnalazioni incidenti, piani abbonamento, avvisi disponibilità)
-- e modifiche alle tabelle esistenti (users, subscriptions, rides,
-- vehicle_types, vehicles).
--
-- Preso direttamente da: Documentazione_2026 v1_Finale (Sprint 3)
-- ============================================================

-- ---------- NUOVE TABELLE ----------

CREATE TABLE IF NOT EXISTS service_areas (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(120) NOT NULL,
    polygon      JSONB        NOT NULL,
    min_vehicles INTEGER      NOT NULL CHECK (min_vehicles >= 0),
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS parking_zones (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(120) NOT NULL,
    polygon      JSONB        NOT NULL,
    bonus_credit DECIMAL(8,2) NOT NULL DEFAULT 0 CHECK (bonus_credit >= 0),
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS maintenance_zones (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(120) NOT NULL,
    polygon     JSONB        NOT NULL,
    type        VARCHAR(20)  NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT maintenance_type_valido CHECK (type IN ('bloccante','rallentante'))
);

CREATE TABLE IF NOT EXISTS incident_reports (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_id  UUID         NOT NULL REFERENCES vehicles(id),
    ride_id     UUID         REFERENCES rides(id),
    user_id     UUID         NOT NULL REFERENCES users(id),
    type        VARCHAR(20)  NOT NULL,
    description TEXT,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT incident_type_valido CHECK (type IN ('furto','incidente'))
);

CREATE TABLE IF NOT EXISTS subscription_plans (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    vehicle_type_id UUID         NOT NULL REFERENCES vehicle_types(id),
    name            VARCHAR(100) NOT NULL,
    price           DECIMAL(8,2) NOT NULL CHECK (price >= 0),
    duration_days   INTEGER      NOT NULL CHECK (duration_days > 0),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS availability_alerts (
    id              UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    service_area_id UUID      NOT NULL REFERENCES service_areas(id),
    available_count INTEGER   NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------- MODIFICHE A TABELLE ESISTENTI ----------

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS status          VARCHAR(20) NOT NULL DEFAULT 'attivo',
    ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMP,
    ADD COLUMN IF NOT EXISTS suspend_reason  TEXT;

ALTER TABLE users DROP CONSTRAINT IF EXISTS user_status_valido;
ALTER TABLE users ADD CONSTRAINT user_status_valido CHECK (status IN ('attivo','sospeso','bloccato'));

ALTER TABLE subscriptions
    ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES subscription_plans(id);

ALTER TABLE rides
    ADD COLUMN IF NOT EXISTS parking_bonus DECIMAL(8,2) NOT NULL DEFAULT 0;

ALTER TABLE vehicle_types
    ADD COLUMN IF NOT EXISTS costo_sblocco DECIMAL(8,2) NOT NULL DEFAULT 0;

-- Reinserimento dello stato 'bloccato' per i mezzi
ALTER TABLE vehicles DROP CONSTRAINT IF EXISTS vehicle_status_valido;
ALTER TABLE vehicles DROP CONSTRAINT IF EXISTS vehicles_status_valido;
ALTER TABLE vehicles ADD CONSTRAINT vehicle_status_valido
    CHECK (status IN ('disponibile','prenotato','in_uso','manutenzione','bloccato'));
