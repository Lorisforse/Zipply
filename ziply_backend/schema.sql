-- ============================================================
-- Ziply - Schema completo del database (PostgreSQL)
-- Crea tutte le tabelle usate dal backend e inserisce alcuni
-- dati di esempio (mezzi e una zona vietata) per popolare la mappa.
--
-- Uso:  psql -U postgres -d ziply -f schema.sql
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Utenti
CREATE TABLE IF NOT EXISTS users (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nome          VARCHAR(100) NOT NULL,
    cognome       VARCHAR(100) NOT NULL,
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    ruolo         VARCHAR(20)  NOT NULL DEFAULT 'utente',
    created_at    TIMESTAMP    DEFAULT NOW(),
    updated_at    TIMESTAMP    DEFAULT NOW(),
    CONSTRAINT ruolo_valido CHECK (ruolo IN ('utente', 'operatore', 'amministrazione'))
);

-- Tipologie di mezzo (tariffa e CO2)
CREATE TABLE IF NOT EXISTS vehicle_types (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nome                   VARCHAR(50)  NOT NULL,
    tariffa_al_minuto      DECIMAL(5,2) NOT NULL,
    co2_risparmiata_per_km DECIMAL(6,2) NOT NULL
);

-- Mezzi della flotta
CREATE TABLE IF NOT EXISTS vehicles (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    type_id       UUID         NOT NULL REFERENCES vehicle_types(id),
    qr_code       VARCHAR(100) UNIQUE NOT NULL,
    battery_level INTEGER      NOT NULL CHECK (battery_level BETWEEN 0 AND 100),
    latitude      DECIMAL(9,6) NOT NULL,
    longitude     DECIMAL(9,6) NOT NULL,
    status        VARCHAR(20)  NOT NULL DEFAULT 'disponibile',
    updated_at    TIMESTAMP    DEFAULT NOW(),
    CONSTRAINT status_valido CHECK (status IN ('disponibile', 'prenotato', 'in_uso', 'manutenzione'))
);

-- Prenotazioni
CREATE TABLE IF NOT EXISTS bookings (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id),
    vehicle_id UUID        NOT NULL REFERENCES vehicles(id),
    created_at TIMESTAMP   DEFAULT NOW(),
    expires_at TIMESTAMP   NOT NULL,
    status     VARCHAR(20) NOT NULL DEFAULT 'attiva',
    CONSTRAINT status_valido CHECK (status IN ('attiva', 'scaduta', 'utilizzata', 'annullata'))
);

-- Corse
CREATE TABLE IF NOT EXISTS rides (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id       UUID         NOT NULL REFERENCES bookings(id),
    user_id          UUID         NOT NULL REFERENCES users(id),
    vehicle_id       UUID         NOT NULL REFERENCES vehicles(id),
    started_at       TIMESTAMP    NOT NULL DEFAULT NOW(),
    ended_at         TIMESTAMP,
    duration_minutes INTEGER,
    total_cost       DECIMAL(8,2),
    co2_saved        DECIMAL(8,2),
    status           VARCHAR(20)  NOT NULL DEFAULT 'attiva',
    CONSTRAINT status_valido CHECK (status IN ('attiva', 'paused', 'completata'))
);

-- Metodi di pagamento (solo ultime 4 cifre + scadenza)
CREATE TABLE IF NOT EXISTS payment_methods (
    id             UUID       PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID       NOT NULL REFERENCES users(id),
    card_last_four VARCHAR(4) NOT NULL,
    card_expiry    VARCHAR(5) NOT NULL,
    is_default     BOOLEAN    NOT NULL DEFAULT FALSE,
    created_at     TIMESTAMP  DEFAULT NOW()
);

-- Zone (vietate / designate). Il backend legge le zone vietate da qui.
CREATE TABLE IF NOT EXISTS zones (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nome          VARCHAR(100) NOT NULL,
    polygon       JSONB        NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    tipo          VARCHAR(20)  NOT NULL DEFAULT 'vietata',
    bonus_credito NUMERIC(6,2),
    created_at    TIMESTAMP    DEFAULT NOW(),
    CONSTRAINT tipo_valido CHECK (tipo IN ('vietata', 'designata')),
    CONSTRAINT bonus_solo_designata CHECK (tipo = 'designata' OR bonus_credito IS NULL)
);

-- ----- DATI DI ESEMPIO -----
-- Mezzi posizionati attorno al centro mappa di default (45.4654, 9.1859).

INSERT INTO vehicle_types (id, nome, tariffa_al_minuto, co2_risparmiata_per_km) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Bicicletta',            0.15, 120.00),
  ('22222222-2222-2222-2222-222222222222', 'Monopattino elettrico', 0.20, 100.00),
  ('33333333-3333-3333-3333-333333333333', 'Automobile elettrica',  0.45,  90.00);

INSERT INTO vehicles (type_id, qr_code, battery_level, latitude, longitude, status) VALUES
  ('11111111-1111-1111-1111-111111111111', 'ZP-BIKE-001',    92, 45.4660, 9.1862, 'disponibile'),
  ('22222222-2222-2222-2222-222222222222', 'ZP-SCOOTER-001', 78, 45.4648, 9.1850, 'disponibile'),
  ('22222222-2222-2222-2222-222222222222', 'ZP-SCOOTER-002', 65, 45.4665, 9.1845, 'disponibile'),
  ('33333333-3333-3333-3333-333333333333', 'ZP-CAR-001',     88, 45.4642, 9.1870, 'disponibile');

INSERT INTO zones (nome, polygon, tipo) VALUES
  ('Centro storico (ZTL)',
   '{"type":"Polygon","coordinates":[[[9.183,45.468],[9.189,45.468],[9.189,45.463],[9.183,45.463],[9.183,45.468]]]}',
   'vietata');
