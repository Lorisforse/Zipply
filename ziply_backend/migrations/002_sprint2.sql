-- ============================================================
-- Ziply - Migration 002 (Sprint 2)
-- Nuove tabelle (sconti, promozioni, abbonamenti, segnalazioni,
-- pause corsa, link di pagamento, chat) e modifiche alle tabelle
-- esistenti (users, bookings, rides). Reinserisce lo stato 'paused'
-- per le corse.
--
-- Idempotente: usa IF NOT EXISTS / IF EXISTS, si può rieseguire
-- senza errori.
--
-- Uso (sul server, container Postgres 'ziply-postgres'):
--   docker exec -i ziply-postgres psql -U ziply -d ziply_db < 002_sprint2.sql
-- ============================================================

-- ---------- NUOVE TABELLE ----------

-- UT.09 - Codici sconto inseriti manualmente dall'utente
CREATE TABLE IF NOT EXISTS discount_codes (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    code        VARCHAR(50)  UNIQUE NOT NULL,
    percentage  DECIMAL(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 100),
    valid_from  TIMESTAMP    NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMP    NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    max_uses    INTEGER      NOT NULL DEFAULT 1,
    used_count  INTEGER      NOT NULL DEFAULT 0
);

-- UT.21 - Promozioni applicate automaticamente dal sistema
CREATE TABLE IF NOT EXISTS promotions (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    description VARCHAR(255) NOT NULL,
    percentage  DECIMAL(5,2) NOT NULL CHECK (percentage > 0 AND percentage <= 100),
    valid_from  TIMESTAMP    NOT NULL DEFAULT NOW(),
    valid_until TIMESTAMP    NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE
);

-- UT.22 - Abbonamenti per tipologia di mezzo
CREATE TABLE IF NOT EXISTS subscriptions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id),
    vehicle_type_id UUID        NOT NULL REFERENCES vehicle_types(id),
    start_date      TIMESTAMP   NOT NULL DEFAULT NOW(),
    end_date        TIMESTAMP   NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'active',
    CONSTRAINT subscription_status_valido CHECK (status IN ('active','expired','cancelled'))
);

-- UT.11 - Segnalazioni di malfunzionamento dei mezzi
CREATE TABLE IF NOT EXISTS malfunction_reports (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users(id),
    vehicle_id   UUID        NOT NULL REFERENCES vehicles(id),
    problem_type VARCHAR(50) NOT NULL,
    description  TEXT,
    created_at   TIMESTAMP   NOT NULL DEFAULT NOW(),
    status       VARCHAR(20) NOT NULL DEFAULT 'in_attesa',
    CONSTRAINT malfunction_status_valido CHECK (status IN ('in_attesa','preso_in_carico','risolto'))
);

-- UT.15 - Intervalli di pausa di una corsa
CREATE TABLE IF NOT EXISTS ride_pauses (
    id         UUID      PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id    UUID      NOT NULL REFERENCES rides(id),
    paused_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    resumed_at TIMESTAMP
);

-- UT.23 - Link di pagamento per dividere il costo di una corsa multipla
CREATE TABLE IF NOT EXISTS payment_links (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id         UUID         NOT NULL REFERENCES rides(id),
    total_amount    DECIMAL(8,2) NOT NULL,
    participants    INTEGER      NOT NULL CHECK (participants > 0),
    amount_per_head DECIMAL(8,2) NOT NULL,
    valid_until     TIMESTAMP    NOT NULL,
    status          VARCHAR(20)  NOT NULL DEFAULT 'active',
    CONSTRAINT payment_link_status_valido CHECK (status IN ('active','expired','paid'))
);

-- UT.10 - Sessioni di chat di assistenza
CREATE TABLE IF NOT EXISTS chat_sessions (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id),
    status     VARCHAR(20) NOT NULL DEFAULT 'bot',
    created_at TIMESTAMP   NOT NULL DEFAULT NOW(),
    CONSTRAINT chat_status_valido CHECK (status IN ('bot','operatore','chiusa'))
);

-- UT.10 - Messaggi della chat di assistenza
CREATE TABLE IF NOT EXISTS chat_messages (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID        NOT NULL REFERENCES chat_sessions(id),
    sender     VARCHAR(20) NOT NULL,
    text       TEXT        NOT NULL,
    sent_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    CONSTRAINT chat_sender_valido CHECK (sender IN ('utente','bot','operatore'))
);

-- ---------- MODIFICHE A TABELLE ESISTENTI ----------

-- UT.23 - credito utente accumulato dalle corse condivise
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS credit_balance DECIMAL(8,2) NOT NULL DEFAULT 0;

-- UT.09/UT.21 - sconti collegati alla prenotazione; UT.19 - prenotazione schedulata
ALTER TABLE bookings
    ADD COLUMN IF NOT EXISTS discount_code_id UUID REFERENCES discount_codes(id),
    ADD COLUMN IF NOT EXISTS promotion_id     UUID REFERENCES promotions(id),
    ADD COLUMN IF NOT EXISTS booking_type     VARCHAR(20) NOT NULL DEFAULT 'immediate',
    ADD COLUMN IF NOT EXISTS scheduled_start  TIMESTAMP;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS booking_type_valido;
ALTER TABLE bookings ADD CONSTRAINT booking_type_valido
    CHECK (booking_type IN ('immediate','scheduled'));

-- UT.09/UT.21 - sconto applicato al costo finale della corsa
ALTER TABLE rides
    ADD COLUMN IF NOT EXISTS applied_discount DECIMAL(8,2);

-- UT.15 - reinserisce lo stato 'paused' nel CHECK di rides.status.
-- Rimuove il vincolo di status esistente (qualunque sia il suo nome) e lo
-- ricrea includendo 'paused'.
DO $$
DECLARE c text;
BEGIN
    SELECT conname INTO c
      FROM pg_constraint
     WHERE conrelid = 'rides'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%attiva%';
    IF c IS NOT NULL THEN
        EXECUTE 'ALTER TABLE rides DROP CONSTRAINT ' || quote_ident(c);
    END IF;
END $$;

ALTER TABLE rides ADD CONSTRAINT status_valido
    CHECK (status IN ('attiva','paused','completata'));

-- ---------- SEED CODICI SCONTO (UT.09) ----------
-- Codici di esempio per la demo e i test. Idempotente: ON CONFLICT sul codice
-- evita duplicati alle riesecuzioni. Include un codice scaduto e uno esaurito
-- per verificare i casi non validi.
INSERT INTO discount_codes (code, percentage, valid_from, valid_until, is_active, max_uses, used_count)
VALUES
    ('ZIPLY10',     10.00, NOW() - INTERVAL '1 day',    NOW() + INTERVAL '1 year',  TRUE, 1000, 0),
    ('BENVENUTO20', 20.00, NOW() - INTERVAL '1 day',    NOW() + INTERVAL '1 year',  TRUE, 1000, 0),
    ('SCADUTO5',     5.00, NOW() - INTERVAL '2 months', NOW() - INTERVAL '1 month', TRUE, 1000, 0),
    ('ESAURITO15',  15.00, NOW() - INTERVAL '1 day',    NOW() + INTERVAL '1 year',  TRUE, 1,    1)
ON CONFLICT (code) DO NOTHING;
