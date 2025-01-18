#!/bin/bash
set -e

REMOTE_USER="ssh-user"
REMOTE_HOST="remote-host-ip"
APP_BINARY="app"
DEPLOYMENT_TYPE="local"

if [ "$DEPLOYMENT_TYPE" == "local" ]; then
  set -e

  export PGPASSWORD=$POSTGRES_PASSWORD

  go mod tidy
  go build -o app main.go

  nohup ./app > app.log 2>&1 &
  echo "Application started"

  sleep 5
  curl -s http://localhost:8080/api/v0/prices || echo "Application is unavailable"

  echo "Application deployed successfully on ${REMOTE_HOST}."
  echo ${REMOTE_HOST}
fi
