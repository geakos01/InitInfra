#!/bin/bash
# A postgres image ezt CSAK az elso inditaskor futtatja (ures adatkonyvtarnal).
# Ha a volume mar letezik, ez a szkript NEM fut le ujra.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER "$APP_USER" WITH PASSWORD '$APP_PASSWORD';
    CREATE DATABASE "$APP_DB" OWNER "$APP_USER";
EOSQL

echo "initdb: a(z) $APP_DB adatbazis letrehozva, tulajdonos: $APP_USER"
