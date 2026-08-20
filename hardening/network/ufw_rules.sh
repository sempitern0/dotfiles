#!/bin/bash


if [ "$EUID" -ne 0 ]; then
  echo "ERROR: You need to be root to run this script"
  exit 1
fi

ufw default deny incoming
ufw default allow outgoing
ufw default deny routed # Evita que el equipo actue como enrutador

ufw allow http
ufw allow https
ufw allow ssh
ufw limit ssh

# Permitir tráfico en la interfaz loopback, necesario para servicios internos
ufw allow in on lo
ufw allow out on lo

ufw logging on

ufw --force enable

echo "----------------------------------------"
echo "UFW CURRENT STATUS:"
echo "----------------------------------------"
ufw status verbose