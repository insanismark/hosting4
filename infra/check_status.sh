#!/usr/bin/env bash

##
## Скрипт диагностики состояния хостинга
##

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "  Диагностика хостинг-инфраструктуры"
echo "=========================================="
echo

# Проверка Docker
if ! command -v docker &> /dev/null; then
  echo -e "${RED}✗ Docker не установлен${NC}"
  exit 1
fi

if ! docker ps &> /dev/null; then
  echo -e "${RED}✗ Нет прав доступа к Docker (запустите с sudo)${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Docker доступен${NC}"
echo

# Статус контейнеров
echo "==> Статус контейнеров:"
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'NAMES|hosting|php_'

echo
echo "==> Порты:"
ss -tlnp 2>/dev/null | grep -E ':(80|443|2222|9000|9443) ' || echo "Нет занятых портов"

echo
echo "==> Логи nginx (последние 20 строк):"
docker logs --tail 20 hosting_nginx 2>&1 || echo "Контейнер не запущен"

echo
echo "==> Проверка конфигурации nginx:"
docker exec hosting_nginx nginx -t 2>&1 || echo "Не удалось проверить конфигурацию"

echo
echo "==> Сайты:"
ls -1 ../sites/ 2>/dev/null | grep -v example.com || echo "Нет сайтов"

echo
echo "==> Конфиги nginx:"
ls -1 ../config/nginx/conf.d/ 2>/dev/null || echo "Нет конфигов"
