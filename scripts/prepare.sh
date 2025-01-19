#!/bin/bash

set -e

REMOTE_USER="ubuntu"
REMOTE_HOST="18.215.151.225"

sudo apt-get update
sudo apt-get install -y postgresql-contrib

pg_isready -h localhost -p 5432 -U "$POSTGRES_USER"

echo "Checking and installing PostgreSQL Server on remote server ${REMOTE_HOST}..."

echo "${{ secrets.HOST_KEY }}" > test.pem

ssh -i test.pem "${REMOTE_USER}@${REMOTE_HOST}" bash -c "'
if ! command -v psql > /dev/null; then
    echo \"PostgreSQL Server is not installed. Installing...\"
    sudo apt-get update
    sudo apt-get install -y postgresql postgresql-contrib
else
    echo \"PostgreSQL Server is already installed.\"
fi

if ! command -v go > /dev/null; then
    echo \"Installing Go via apt-get...\"
    sudo apt-get update
    sudo apt-get install -y golang
else
    echo \"Go is already installed.\"
fi
'"
