#!/bin/bash
set -e

REMOTE_USER="ssh-user"
REMOTE_HOST="remote-host-ip"
APP_BINARY="app"
DEPLOYMENT_TYPE="local"

if [ "$DEPLOYMENT_TYPE" == "local" ]; then
  set -e

  export PGPASSWORD=$POSTGRES_PASSWORD

  SQL_QUERY="
    CREATE TABLE IF NOT EXISTS prices (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255),
      category VARCHAR(255),
      price DECIMAL,
      create_date DATE
    );
  "

  psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$SQL_QUERY"

  go mod tidy
  go build -o app main.go

  nohup ./app > app.log 2>&1 &
  echo "Application started"

  sleep 5
  curl -s http://localhost:8080/api/v0/prices || echo "Application is unavailable"

  bash test_reqs.sh 1
  bash test_reqs.sh 2

  echo "Application deployed successfully on ${REMOTE_HOST}."
  echo ${REMOTE_HOST}
fi
