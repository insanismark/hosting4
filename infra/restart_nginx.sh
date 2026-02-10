#!/usr/bin/env bash
set -euo pipefail

##
## Скрипт перезапуска nginx
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}==> Перезапуск nginx...${NC}"
cd "$ROOT_DIR/infra"
docker compose restart nginx

echo
echo -e "${GREEN}Nginx перезапущен!${NC}"
echo
echo "Проверка статуса:"
docker compose ps nginx
