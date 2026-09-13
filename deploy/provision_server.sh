#!/usr/bin/env bash

# Provisionamento de servidor Ubuntu 22.04/24.04 LTS para o NhaCarro.
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute este script como root (sudo)." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

: "${NHACARRO_DB_USER:=nhacarro_user}"
: "${NHACARRO_DB_NAME:=nhacarro_db}"
: "${NHACARRO_DOMAIN:=api.nhacarro.com}"

if [[ -z "${NHACARRO_DB_PASSWORD:-}" ]]; then
  read -r -s -p "Senha do usuário PostgreSQL ${NHACARRO_DB_USER}: " NHACARRO_DB_PASSWORD
  echo
fi

if [[ -z "${NHACARRO_DB_PASSWORD}" ]]; then
  echo "A senha do banco não pode ser vazia." >&2
  exit 1
fi

echo ">>> 1. Atualizando pacotes do sistema..."
apt-get update
apt-get upgrade -y

echo ">>> 2. Instalando utilitários essenciais e Nginx..."
apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  git \
  nginx \
  software-properties-common \
  ufw

echo ">>> 3. Instalando PostgreSQL + PostGIS..."
apt-get install -y postgresql postgresql-contrib postgis

echo ">>> 4. Instalando Node.js (v20 LTS) e PM2..."
curl --fail --silent --show-error --location https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install --global pm2

echo ">>> 5. Configurando o banco de dados PostgreSQL..."
runuser -u postgres -- psql -v ON_ERROR_STOP=1 \
  --set=db_user="${NHACARRO_DB_USER}" \
  --set=db_password="${NHACARRO_DB_PASSWORD}" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') THEN
    CREATE ROLE :"db_user" LOGIN PASSWORD :'db_password';
  ELSE
    ALTER ROLE :"db_user" WITH PASSWORD :'db_password';
  END IF;
END
$$;
SQL

if ! runuser -u postgres -- psql -Atqc \
  "SELECT 1 FROM pg_database WHERE datname = '${NHACARRO_DB_NAME}'" | grep -q 1; then
  runuser -u postgres -- createdb --owner="${NHACARRO_DB_USER}" "${NHACARRO_DB_NAME}"
fi

runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d "${NHACARRO_DB_NAME}" <<'SQL'
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SQL

echo ">>> 6. Configurando firewall (UFW)..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo ">>> 7. Ativando configuração do Nginx..."
install -m 0644 "$(dirname "$0")/nginx/nhacarro" /etc/nginx/sites-available/nhacarro
ln -sfn /etc/nginx/sites-available/nhacarro /etc/nginx/sites-enabled/nhacarro
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

echo ">>> 8. Instalando Certbot..."
apt-get install -y certbot python3-certbot-nginx

if [[ -n "${NHACARRO_CERTBOT_EMAIL:-}" ]]; then
  echo ">>> 9. Gerando certificado SSL para ${NHACARRO_DOMAIN}..."
  certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "${NHACARRO_CERTBOT_EMAIL}" \
    --domain "${NHACARRO_DOMAIN}"
else
  echo ">>> Certificado SSL não emitido: defina NHACARRO_CERTBOT_EMAIL e execute novamente."
  echo "    Exemplo: NHACARRO_CERTBOT_EMAIL=admin@${NHACARRO_DOMAIN} $0"
fi

unset NHACARRO_DB_PASSWORD
echo ">>> Servidor provisionado com sucesso para o NhaCarro!"
