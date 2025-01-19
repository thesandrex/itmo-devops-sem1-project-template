#!/bin/bash

set -e

REMOTE_USER="ubuntu"
REMOTE_HOST="18.215.151.225"
APP_BINARY="app"

export PGPASSWORD=$POSTGRES_PASSWORD

SQL_QUERY="
  CREATE TABLE IF NOT EXISTS prices (
    _id SERIAL PRIMARY KEY,
    id INT,
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

echo "Application successfully deployed in workflow."

ssh -i test.pem "${REMOTE_USER}@${REMOTE_HOST}" bash -c "'
  echo \"Setting up PostgreSQL user and database on remote server...\"
  sudo -u postgres psql -c \"CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD \'${POSTGRES_PASSWORD}\';\"

  sudo -u postgres psql -c \"CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};\"

  sudo -u postgres psql -d \"${POSTGRES_DB}\" -c \"GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};\"
  
  export PGPASSWORD=${POSTGRES_PASSWORD}

  psql -h \"$POSTGRES_HOST\" -p \"$POSTGRES_PORT\" -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -c \"$SQL_QUERY\"

  if [ ! -d 'test' ]; then
      echo 'Репозиторий не найден. Клонируем...'
      git clone ${REPO_URL} test
  else
      echo 'Репозиторий уже существует. Обновляем.'
      cd test
      git pull
  fi

  go mod tidy
  go build -o app main.go

  nohup ./app > app.log 2>&1 &
  echo \"Application started\"

  sleep 5
  curl -s http://localhost:8080/api/v0/prices || echo \"Application is unavailable\"

  echo \"Application successfully deployed on ${REMOTE_HOST}\"
'"

echo "$REMOTE_HOST"
