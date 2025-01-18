#!/bin/bash
set -e

REMOTE_USER="ssh-user"
REMOTE_HOST="remote-host-ip"
REMOTE_DIR="./app"
GITHUB_REPO="github-repo-url"
DEPLOYMENT_TYPE="local"

if [ "$DEPLOYMENT_TYPE" == "local" ]; then
  sudo apt-get update
  sudo apt-get install -y postgresql-contrib

  echo "Configuring PostgreSQL database and user..."
  pg_isready -h localhost -p 5432 -U "$POSTGRES_USER"
  sudo psql -h localhost -p 5432 -U ${POSTGRES_USER} --set=PGPASSWORD="${POSTGRES_PASSWORD}" -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};"
  sudo psql -h localhost -p 5432 -U ${POSTGRES_USER} --set=PGPASSWORD="${POSTGRES_PASSWORD}" -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};"
fi
