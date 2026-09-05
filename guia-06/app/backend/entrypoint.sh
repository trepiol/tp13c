#!/usr/bin/env bash
set -Eeuo pipefail
for attempt in $(seq 1 60); do python3 -c 'import app; app.init_db()' && exec "$@"; echo "PostgreSQL aún no está listo ($attempt/60)"; sleep 1; done
echo "Timeout esperando PostgreSQL" >&2; exit 1

