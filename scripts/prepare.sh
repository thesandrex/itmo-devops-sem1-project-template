#!/bin/bash
set -e

REMOTE_USER="ssh-user"
REMOTE_HOST="remote-host-ip"
REMOTE_DIR="./app"
GITHUB_REPO="github-repo-url"
DEPLOYMENT_TYPE="local"

if [ "$DEPLOYMENT_TYPE" == "local" ]; then
  sudo apt-get update
  sudo apt-get install -y postgres-contrib

  echo "Configuring PostgreSQL database and user..."
  sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" || true
  sudo -u postgres psql -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};" || true
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};"

elif [ "$DEPLOYMENT_TYPE" == "remote" ]; then
  echo "Preparing the environment on the remote server..."

  ssh ${REMOTE_USER}@${REMOTE_HOST} << EOF
    set -e

    echo "Checking if application code exists..."
    if [ ! -d "${REMOTE_DIR}" ]; then
      echo "Cloning the application code from GitHub..."
      git clone ${GITHUB_REPO} ${REMOTE_DIR}
    else
      echo "Updating application code from GitHub..."
      cd ${REMOTE_DIR}
      git pull origin main
    fi

    echo "Changing directory to the application folder..."
    cd ${REMOTE_DIR}

    echo "Installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y postgresql postgresql-contrib golang

    echo "Starting PostgreSQL service..."
    sudo service postgresql start

    echo "Configuring PostgreSQL database and user..."
    sudo -u postgres psql -c "CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';" || true
    sudo -u postgres psql -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};" || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};"

    echo "Environment preparation on the remote server is complete." EOF

  echo "Remote environment prepared successfully."
fi
