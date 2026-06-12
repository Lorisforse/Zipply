# Deploy del backend Ziply con Jenkins

Deploy automatico a ogni push su `main`, con lo **stesso pattern del job Budget-bot**:
Jenkins gira in container sullo stesso server (Docker già accessibile) e fa
build + redeploy in loco. Niente registry, niente SSH.

## Come funziona

Pipeline inline (vedi `Jenkinsfile` in radice repo, da incollare nel job):

1. **Checkout** del repo `Lorisforse/Zipply` (`main`) con credenziale `github-token`.
2. **Prepare deploy dir** — copia **solo** la sottocartella `ziply_backend/` in `/opt/ziply/backend` (escludendo `.git` e `.env`).
3. **Copy env** — scrive `/opt/ziply/backend/.env` dalla file-credential Jenkins `ziply-backend-env`.
4. **Build and deploy** — `docker compose build` poi `docker compose up -d --force-recreate`.
5. **Verify** — il container `ziply-backend` deve essere `running` e `GET localhost:8081/vehicles` deve dare **401** (route protetta → prova che il nuovo build è online).

### Reti (importante)

Il container backend deve stare su **due** reti esterne:
- `db_ziply-net` → per raggiungere `ziply-postgres`;
- `nefta_webnet` → perché **nginx** (reverse proxy) raggiunga il backend.

Entrambe sono dichiarate `external` nel `docker-compose.yml`. Se mancasse
`nefta_webnet`, dopo un deploy nginx non troverebbe più il backend (502).

---

## Setup una tantum

### 1. Credenziale con il file `.env`

In Jenkins: **Manage Jenkins → Credentials → (global) → Add Credentials**
- Kind: **Secret file**
- ID: `ziply-backend-env`
- File: un `.env` con questo contenuto (valori attuali di produzione):

```dotenv
DB_HOST=ziply-postgres
DB_PORT=5432
DB_NAME=ziply_db
DB_USER=ziply
DB_PASSWORD=ziply_password
JWT_SECRET=ziply_jwt_secret_dev
SERVER_PORT=8080
```

> Questi sono i valori oggi in uso. Per rotazione di `JWT_SECRET`/`DB_PASSWORD`
> basta aggiornare questa credenziale e rilanciare il job (cambiare `JWT_SECRET`
> invalida i token già emessi → gli utenti dovranno rifare login).

La credenziale `github-token` esiste già (usata dagli altri job).

### 2. Creare il job

**New Item → Pipeline** → nome `ziply-backend-deploy` → OK. Poi:
- **Pipeline → Definition: Pipeline script** (inline, come Budget-bot)
- incolla il contenuto del `Jenkinsfile` di questo repo nello script
- Save

Il blocco `triggers { pollSCM('H/2 * * * *') }` attiva il polling (ogni 2 min)
dopo la prima esecuzione. **Build Now** per il primo run.

> In alternativa puoi usare **Pipeline script from SCM** (Git, repo Zipply,
> branch `main`, Script Path `Jenkinsfile`): funziona uguale. Budget-bot però usa
> inline, quindi per coerencza si consiglia inline.

---

## Prima di tutto: pushare le modifiche al repo

La pipeline distribuisce ciò che è nel repo. Le correzioni a
`ziply_backend/docker-compose.yml` (reti corrette + `.env`) e il `Jenkinsfile`
devono essere su `main` **prima** del primo run, altrimenti il deploy
userebbe il vecchio compose con la rete sbagliata.

---

## Troubleshooting

- **App a 404 su `/vehicles` dopo deploy ok** → lo smoke test su `localhost:8081`
  passa ma nginx no: il proxy non instrada `/ziply/api/vehicles`. Aggiungi al
  proxy una location catch-all `/ziply/api/` → `ziply-backend:8080` e ricarica.
- **502 dopo deploy** → il container non è su `nefta_webnet`. Verifica con
  `docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' ziply-backend`:
  devono comparire `db_ziply-net` e `nefta_webnet`.
- **`network nefta_webnet not found`** → la rete esterna non esiste con quel nome;
  controlla `docker network ls` e allinea il nome nel compose.
- **Backend non parte / errore DB** → `.env` mancante o errato: controlla la
  credenziale `ziply-backend-env` e `docker compose -p backend logs backend`.
```
