#!/usr/bin/env bash
set -euo pipefail

##
## Скрипт исправления проблем с nginx
##
## Удаляет старые конфиги и перезапускает nginx
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Исправление nginx..."

echo
echo "==> Удаление старых конфигов nginx..."
find "$ROOT_DIR/config/nginx/conf.d" -name "*.conf" -type f | while read conf; do
  domain=$(basename "$conf" .conf)
  site_dir="$ROOT_DIR/sites/$domain"
  
  if [[ ! -d "$site_dir" ]]; then
    echo "  Удаляю: $conf (сайт $domain не существует)"
    rm -f "$conf"
  fi
done

echo
echo "==> Создание директорий logs для существующих сайтов..."
find "$ROOT_DIR/sites" -mindepth 1 -maxdepth 1 -type d | while read site_dir; do
  if [[ -d "$site_dir/www" ]]; then
    domain=$(basename "$site_dir")
    logs_dir="$site_dir/logs"
    
    if [[ ! -d "$logs_dir" ]]; then
      echo "  Создаю: $logs_dir"
      mkdir -p "$logs_dir"
    fi
  fi
done

echo
echo "==> Перезапуск nginx..."
cd "$ROOT_DIR/infra"
docker compose restart nginx

echo
echo "==> Проверка статуса..."
docker compose ps nginx
