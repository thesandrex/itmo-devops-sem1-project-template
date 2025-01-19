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
  psql -h \"$POSTGRES_HOST\" -p \"$POSTGRES_PORT\" -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -c \"$SQL_QUERY\"

  echo \"Setting up PostgreSQL user and database on remote server...\"
  psql -c \"DO \$\$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
          CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
      END IF;
  END \$\$;\"

  psql -c \"DO \$\$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}') THEN
          CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};
      END IF;
  END \$\$;\"

  psql -d \"${POSTGRES_DB}\" -c \"GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};\"
  
  if [ ! -d '/home/ubuntu/test/' ]; then
      echo 'Репозиторий не найден. Клонируем...'
      git clone ${REPO_URL} /home/ubuntu/test/
  else
      echo 'Репозиторий уже существует. Обновляем.'
      cd /home/ubuntu/test/
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
