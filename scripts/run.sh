#!/bin/bash
set -e

REMOTE_USER="ssh-user"
REMOTE_HOST="remote-host-ip"
REMOTE_DIR="./app"
APP_BINARY="app"
DEPLOYMENT_TYPE="local"

if [ "$DEPLOYMENT_TYPE" == "local" ]; then
  set -e
  cd ${REMOTE_DIR}

  export PGPASSWORD=$POSTGRES_PASSWORD
  psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB;" || echo "Database $POSTGRES_DB already exists"

  go mod tidy
  go build -o app main.go

  nohup ./app > app.log 2>&1 &
  echo "Application started"

  sleep 5
  curl -s http://localhost:8080/api/v0/prices || echo "Application is unavailable"

elif [ "$DEPLOYMENT_TYPE" == "remote" ]; then

  echo "Connecting to the remote server to set up and run the application..."
  ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
    set -e
    cd ${REMOTE_DIR}

    export PGPASSWORD=$POSTGRES_PASSWORD
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB;" || echo "Database $POSTGRES_DB already exists"

    go mod tidy
    go build -o app main.go

    nohup ./app > app.log 2>&1 &
    echo "Application started"

    sleep 5
    curl -s http://localhost:8080/api/v0/prices || echo "Application is unavailable"
  EOF

  echo "Application deployed successfully on ${REMOTE_HOST}."
  echo ${REMOTE_HOST}
fi
