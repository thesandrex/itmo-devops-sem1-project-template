#!/bin/bash

set -e

REMOTE_USER="ubuntu"
REMOTE_HOST="18.215.151.225"

sudo apt-get update
sudo apt-get install -y postgresql-contrib

pg_isready -h localhost -p 5432 -U "$POSTGRES_USER"

echo "Checking and installing PostgreSQL Server on remote server ${REMOTE_HOST}..."

mkdir -p "$HOME/.ssh"
ssh-keyscan -H "$REMOTE_HOST" >> ~/.ssh/known_hosts

ssh -i test.pem "$REMOTE_USER"@"$REMOTE_HOST" bash -c "'
if ! command -v psql > /dev/null; then
    echo \"PostgreSQL Server is not installed. Installing...\"
    sudo apt-get update
    sudo apt-get install -y postgresql postgresql-contrib
    sudo service postgresql start
else
    echo \"PostgreSQL Server is already installed.\"
fi

if ! command -v go > /dev/null; then
    echo \"Installing Go via apt-get...\"
    sudo apt-get update
    sudo apt-get install -y git wget tar

    GO_VERSION="1.23.0"
    wget "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"

    if [ -d "/usr/local/go" ]; then
        sudo rm -rf /usr/local/go
    fi

    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"

    echo "export PATH=\$PATH:/usr/local/go/bin" >> ~/.bashrc
    source ~/.bashrc

    go version
else
    echo \"Go is already installed.\"
fi
'"
