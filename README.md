# Ziply - Smart Mobility Zootropolis

Ziply è un sistema di **smart mobility urbana** (bici / monopattini / auto elettriche in
sharing). Il progetto è composto da due parti:

| Componente | Tecnologia | Cartella |
|------------|-----------|----------|
| **Frontend** | Flutter (mobile iOS/Android + web) | [`ziply_app/`](ziply_app/) |
| **Backend**  | Go (API REST) + PostgreSQL | [`ziply_backend/`](ziply_backend/) |

L'app comunica con il backend via API REST e disegna la mappa con `flutter_map`
(tile Stadia Maps). Il backend espone le API, gestisce la logica di business e persiste i
dati su PostgreSQL.

```
Flutter App  --REST/JSON-->  Backend Go  --SQL-->  PostgreSQL
```

---

## Indice

1. [Prerequisiti](#1-prerequisiti)
2. [Database PostgreSQL](#2-database-postgresql)
3. [Backend Go](#3-backend-go)
4. [Frontend Flutter](#4-frontend-flutter)
5. [Variabili d'ambiente del backend](#5-variabili-dambiente-del-backend)
6. [Endpoint API](#6-endpoint-api)

---

## 1. Prerequisiti

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **≥ 3.19** (Dart ≥ 3.3)
- [Go](https://go.dev/dl/) **≥ 1.22**
- [PostgreSQL](https://www.postgresql.org/download/) **≥ 14**
- Un dispositivo o emulatore (Android/iOS) **oppure** Google Chrome (per la versione web)

Verifica delle installazioni:

```bash
flutter --version
go version
psql --version
```

L'ordine di avvio consigliato è: prima il database, poi il backend e infine il frontend.

---

## 2. Database PostgreSQL

Lo schema completo è nello script [`ziply_backend/schema.sql`](ziply_backend/schema.sql): crea
tutte le tabelle e inserisce alcuni dati di esempio (mezzi e una zona vietata) per popolare
la mappa.

1. Creare il database:

   ```bash
   psql -U postgres -c "CREATE DATABASE ziply;"
   ```

2. Eseguire lo script:

   ```bash
   psql -U postgres -d ziply -f ziply_backend/schema.sql
   ```

<details>
<summary>Contenuto di <code>schema.sql</code> (clicca per espandere)</summary>

```sql
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
    CONSTRAINT status_valido CHECK (status IN ('attiva', 'completata'))
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

-- Zone vietate (lette dal backend per l'overlay sulla mappa).
CREATE TABLE IF NOT EXISTS forbidden_zones (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    nome       VARCHAR(100) NOT NULL,
    polygon    JSONB        NOT NULL,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP    DEFAULT NOW()
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

INSERT INTO forbidden_zones (nome, polygon) VALUES
  ('Centro storico (ZTL)',
   '{"type":"Polygon","coordinates":[[[9.183,45.468],[9.189,45.468],[9.189,45.463],[9.183,45.463],[9.183,45.468]]]}');
```
</details>

---

## 3. Backend Go

1. Posizionarsi nella cartella del backend e scaricare le dipendenze:

   ```bash
   cd ziply_backend
   go mod download
   ```

2. Impostare le variabili d'ambiente (vedi [sezione 5](#5-variabili-dambiente-del-backend)).

   **Windows (PowerShell):**
   ```powershell
   $env:DB_HOST="localhost"; $env:DB_PORT="5432"; $env:DB_USER="postgres"
   $env:DB_PASSWORD="postgres"; $env:DB_NAME="ziply"
   $env:JWT_SECRET="8fK2pQ9mZx4Lt7"
   ```

   **Linux / macOS (bash):**
   ```bash
   export DB_HOST=localhost DB_PORT=5432 DB_USER=postgres \
          DB_PASSWORD=postgres DB_NAME=ziply \
          JWT_SECRET="8fK2pQ9mZx4Lt7"
   ```

3. Avviare il server:

   ```bash
   go run ./cmd/server
   ```

   Il server si avvia su **http://localhost:8080** (output atteso: `server listening on :8080`).

---

## 4. Frontend Flutter

```bash
cd ziply_app
flutter pub get
flutter run            # selezionare il dispositivo/emulatore quando richiesto
```

Per la versione **web**:

```bash
flutter run -d chrome
```

Di default l'app usa il backend locale (`http://localhost:8080`). Per puntarla a un altro
backend (ad esempio un proprio server) basta cambiare il valore di `kBaseUrl` nel file
[`ziply_app/lib/constants.dart`](ziply_app/lib/constants.dart).

---

## 5. Variabili d'ambiente del backend

Si impostano come variabili d'ambiente del sistema operativo, nello stesso terminale da cui
si avvia il backend e **prima** di lanciare `go run` (vedi i comandi nella
[sezione 3](#3-backend-go)). Restano valide solo per quella sessione del terminale.

| Variabile | Obbligatoria | Default | Descrizione |
|-----------|:---:|---------|-------------|
| `DB_HOST` | Sì | - | Host PostgreSQL (es. `localhost`) |
| `DB_PORT` | Sì | - | Porta PostgreSQL (es. `5432`) |
| `DB_USER` | Sì | - | Utente del database |
| `DB_PASSWORD` | Sì | - | Password del database |
| `DB_NAME` | Sì | - | Nome del database (es. `ziply`) |
| `JWT_SECRET` | Sì | - | Segreto per firmare i token JWT |
| `JWT_TTL_HOURS` | No | `720` (30 giorni) | Durata del token in ore |
| `SERVER_PORT` | No | `8080` | Porta su cui il server ascolta |

---

## 6. Endpoint API

| Metodo | Path | Auth | Descrizione |
|--------|------|:----:|-------------|
| POST | `/auth/register` | - | Registrazione utente |
| POST | `/auth/login` | - | Login (restituisce JWT) |
| GET | `/forbidden-zones` | - | Zone vietate attive |
| GET | `/vehicles` | JWT | Mezzi disponibili (filtro opzionale `?lat=&lng=&radius=`) |
| POST | `/bookings` | JWT | Prenota un mezzo (15 min) |
| POST | `/bookings/{id}/cancel` | JWT | Annulla la prenotazione |
| POST | `/rides/unlock` | JWT | Sblocca il mezzo e avvia la corsa (prossimità o QR) |
| POST | `/rides/{id}/end` | JWT | Termina la corsa |
| POST | `/payment-methods` | JWT | Aggiunge un metodo di pagamento |
| GET | `/payment-methods` | JWT | Elenca i metodi di pagamento |
| DELETE | `/payment-methods/{id}` | JWT | Elimina un metodo di pagamento |

Le richieste autenticate richiedono l'header `Authorization: Bearer <token>`.

Esempio di registrazione con `curl`:

```bash
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"nome":"Mario","cognome":"Rossi","email":"mario@test.it","password":"password123"}'
```
