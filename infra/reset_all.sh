#!/usr/bin/env bash
set -euo pipefail

##
## Полный сброс инфраструктуры и пересоздание nginx
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

echo "========================================"
echo "  ПОЛНЫЙ СБРОС ИНФРАСТРУКТУРЫ"
echo "========================================"
echo

# Шаг 1: Остановить и удалить nginx
echo "==> Шаг 1: Остановка nginx..."
cd "$INFRA_DIR"
docker compose stop nginx
docker compose rm -f nginx
echo "  Nginx остановлен и удалён"

# Шаг 2: Удалить ВСЕ конфиги nginx
echo
echo "==> Шаг 2: Удаление всех конфигов nginx..."
rm -f "$ROOT_DIR/config/nginx/conf.d/"*.conf
echo "  Все конфиги удалены"

# Шаг 3: Остановить и удалить ВСЕ контейнеры PHP-FPM
echo
echo "==> Шаг 3: Удаление всех PHP-FPM контейнеров..."
docker ps -a --format '{{.Names}}' | grep '^php_' | while read container; do
  echo "  Удаляю: $container"
  docker rm -f "$container" 2>/dev/null || true
done
echo "  Все PHP-FPM контейнеры удалены"

# Шаг 4: Удалить старые директории сайтов blablatest
echo
echo "==> Шаг 4: Удаление старых сайтов blablatest*..."
rm -rf "$ROOT_DIR/sites/blablatest.tagan.ru" 2>/dev/null || true
rm -rf "$ROOT_DIR/sites/blablatest1.tagan.ru" 2>/dev/null || true
rm -rf "$ROOT_DIR/sites/blablatest2.tagan.ru" 2>/dev/null || true
echo "  Старые сайты удалены"

# Шаг 5: Удалить конфиги PHP-FPM
echo
echo "==> Шаг 5: Удаление конфигов PHP-FPM..."
rm -rf "$ROOT_DIR/config/php-fpm/blablatest.tagan.ru" 2>/dev/null || true
rm -rf "$ROOT_DIR/config/php-fpm/blablatest1.tagan.ru" 2>/dev/null || true
rm -rf "$ROOT_DIR/config/php-fpm/blablatest2.tagan.ru" 2>/dev/null || true
echo "  Конфиги PHP-FPM удалены"

# Шаг 6: Пересоздать и запустить nginx "чистым"
echo
echo "==> Шаг 6: Пересоздание nginx..."
docker compose up -d nginx
sleep 3

# Шаг 7: Проверка
echo
echo "==> Шаг 7: Проверка статуса..."
docker compose ps nginx

# Шаг 8: Получить логи
echo
echo "==> Логи nginx:"
docker logs hosting_nginx --tail 15 2>&1 || true

# Шаг 9: Если nginx запустился, показать результат
echo
echo "========================================"
echo "  РЕЗУЛЬТАТ"
echo "========================================"

STATUS=$(docker inspect -f '{{.State.Status}}' hosting_nginx 2>/dev/null || echo "unknown")
if [[ "$STATUS" == "running" ]]; then
  echo -e "${GREEN}✓ Nginx запущен и работает!${NC}"
  echo
  echo "Теперь можно создать сайт:"
  echo "  cd $INFRA_DIR"
  echo "  sudo ./create_site.sh mydomain.com"
else
  echo -e "${RED}✗ Nginx НЕ запущен (статус: $STATUS)${NC}"
  echo
  echo "Проверьте логи:"
  echo "  sudo docker logs hosting_nginx --tail 30"
fi
