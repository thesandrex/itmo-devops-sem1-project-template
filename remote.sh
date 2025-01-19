#!/bin/bash

echo "Setting up PostgreSQL user and database on remote server..."
sudo -u postgres psql -c "CREATE ROLE  WITH LOGIN PASSWORD \'\';"

sudo -u postgres psql -c "CREATE DATABASE  OWNER ;"

sudo -u postgres psql -d "" -c "GRANT ALL PRIVILEGES ON DATABASE  TO ;"

export PGPASSWORD=

psql -h "" -p "" -U "" -d "" -c ""

if [ ! -d \'test\' ]; then
    echo \'Репозиторий не найден. Клонируем...\'
    git clone  test
else
    echo \'Репозиторий уже существует. Обновляем.\'
    cd test
    git pull
fi

go mod tidy
go build -o app main.go

nohup ./app > app.log 2>&1 &
echo "Application started"

sleep 5
curl -s http://localhost:8080/api/v0/prices || echo "Application is unavailable"

echo "Application successfully deployed on "

