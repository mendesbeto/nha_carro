#!/usr/bin/env bash

# Build e execução da API NestJS com PM2.
set -Eeuo pipefail

: "${NHACARRO_API_DIR:=/opt/nhacarro/backend}"
: "${NHACARRO_PM2_APP_NAME:=nhacarro-backend}"

if [[ ! -d "${NHACARRO_API_DIR}" ]]; then
  echo "Diretório da API não encontrado: ${NHACARRO_API_DIR}" >&2
  exit 1
fi

if [[ ! -f "${NHACARRO_API_DIR}/package.json" ]]; then
  echo "package.json não encontrado em ${NHACARRO_API_DIR}" >&2
  exit 1
fi

cd "${NHACARRO_API_DIR}"

echo ">>> Instalando dependências da API..."
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi

echo ">>> Compilando o projeto NestJS..."
npm run build

if [[ ! -f dist/main.js ]]; then
  echo "Build concluído, mas dist/main.js não foi encontrado." >&2
  exit 1
fi

echo ">>> Atualizando processo PM2..."
if pm2 describe "${NHACARRO_PM2_APP_NAME}" >/dev/null 2>&1; then
  pm2 restart "${NHACARRO_PM2_APP_NAME}" --update-env
else
  pm2 start dist/main.js --name "${NHACARRO_PM2_APP_NAME}"
fi

pm2 save

echo ">>> API ${NHACARRO_PM2_APP_NAME} publicada com sucesso."
echo ">>> Para ativar o boot automático, execute uma vez o comando emitido por:"
echo "    pm2 startup"
