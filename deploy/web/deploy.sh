#!/usr/bin/env bash
# Construit la version web (Supabase Cloud) et la déploie sur le VPS.
# Usage : deploy/web/deploy.sh   (depuis n'importe où, alias SSH « oracle »)
set -euo pipefail

HOST="${FINFLOW_HOST:-oracle}"
REMOTE_DIR="finflow-web"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$ROOT"
flutter build web --release --dart-define-from-file=env/prod.json

ssh "$HOST" "mkdir -p $REMOTE_DIR/site"
rsync -az --delete build/web/ "$HOST:$REMOTE_DIR/site/"
rsync -az deploy/web/compose.yaml deploy/web/Caddyfile "$HOST:$REMOTE_DIR/"
ssh "$HOST" "cd $REMOTE_DIR && docker compose up -d --remove-orphans && docker compose ps --format '{{.Name}} {{.Status}}'"
