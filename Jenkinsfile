// Deploy del backend Ziply — stesso pattern del job Budget-bot.
// Jenkins gira sullo stesso server (Docker già accessibile dal container Jenkins).
// Il job in Jenkins è una Pipeline con questo script inline (sandbox).
pipeline {
    agent any

    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        DEPLOY_DIR        = '/opt/ziply/backend'
        REPO_URL          = 'https://github.com/Lorisforse/Zipply.git'
        BRANCH            = 'main'
        APP_SUBDIR        = 'ziply_backend'
        ENV_CREDENTIAL_ID = 'ziply-backend-env'
        // URL interno del backend (porta del container). La verifica gira da un
        // container effimero che condivide la rete del backend: Jenkins è isolato
        // e NON vedrebbe la porta 8081 pubblicata sull'host.
        SMOKE_URL         = 'http://localhost:8080/vehicles'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: "${BRANCH}",
                    credentialsId: 'github-token',
                    url: "${REPO_URL}"
            }
        }

        stage('Prepare deploy dir') {
            steps {
                sh '''
                mkdir -p $DEPLOY_DIR

                rm -rf /tmp/ziply-backend-deploy
                mkdir -p /tmp/ziply-backend-deploy

                # Copia SOLO la sottocartella del backend dal monorepo.
                cp -a $APP_SUBDIR/. /tmp/ziply-backend-deploy/

                rm -rf /tmp/ziply-backend-deploy/.git
                rm -f  /tmp/ziply-backend-deploy/.env

                cp -a /tmp/ziply-backend-deploy/. $DEPLOY_DIR/
                rm -rf /tmp/ziply-backend-deploy
                '''
            }
        }

        stage('Copy env') {
            steps {
                withCredentials([file(credentialsId: "${ENV_CREDENTIAL_ID}", variable: 'ENV_FILE')]) {
                    sh '''
                    cp "$ENV_FILE" "$DEPLOY_DIR/.env"
                    chmod 600 "$DEPLOY_DIR/.env"
                    '''
                }
            }
        }

        stage('Build and deploy') {
            steps {
                sh '''
                cd $DEPLOY_DIR
                # Build prima del recreate: il vecchio container continua a servire
                # finché la nuova immagine non è pronta (minimizza il downtime dietro nginx).
                docker compose build
                docker compose up -d --force-recreate
                '''
            }
        }

        stage('Verify') {
            steps {
                sh '''
                sleep 5
                cd $DEPLOY_DIR

                CONTAINER_ID=$(docker compose ps -q backend)
                if [ -z "$CONTAINER_ID" ]; then
                  echo "ERRORE: container backend non trovato"
                  docker compose logs --tail=50
                  exit 1
                fi

                STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_ID")
                echo "Stato container: $STATUS"
                if [ "$STATUS" != "running" ]; then
                  echo "ERRORE: container non in esecuzione"
                  docker compose logs --tail=80
                  exit 1
                fi

                # La route /vehicles è protetta da JWT: 401 senza token prova che
                # il nuovo build è online e la route registrata (un 404 = codice vecchio).
                # Il curl gira in un container che CONDIVIDE la rete del backend
                # (--network container:ziply-backend) → localhost:8080 è il backend.
                for i in $(seq 1 10); do
                  CODE=$(docker run --rm --network "container:ziply-backend" curlimages/curl:latest -s -o /dev/null -w '%{http_code}' "$SMOKE_URL" || true)
                  echo "Tentativo $i: HTTP $CODE su /vehicles"
                  if [ "$CODE" = "401" ]; then
                    echo "OK: /vehicles registrata."
                    exit 0
                  fi
                  sleep 3
                done
                echo "ERRORE: /vehicles non risponde 401."
                docker compose logs --tail=80
                exit 1
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
