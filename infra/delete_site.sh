#!/usr/bin/env bash
set -euo pipefail

##
## Скрипт удаления сайта
##
## Использование:
##   ./delete_site.sh <домен> [--keep-data]
##
## Опции:
##   --keep-data   Не удалять файлы сайта (только контейнеры и конфиги)
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Парсинг аргументов
KEEP_DATA=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --keep-data)
      KEEP_DATA=true
      shift
      ;;
    -h|--help)
      echo "Использование: $0 <домен> [опции]"
      echo ""
      echo "Опции:"
      echo "  --keep-data   Не удалять файлы сайта"
      echo "  -h, --help    Показать справку"
      exit 0
      ;;
    *)
      SITE_DOMAIN="$1"
      shift
      ;;
  esac
done

if [[ -z "${SITE_DOMAIN:-}" ]]; then
  echo "Использование: $0 <домен>" >&2
  exit 1
fi

# Проверка Docker
if ! docker ps &> /dev/null; then
  echo -e "${RED}Ошибка: нет прав доступа к Docker (запустите с sudo)${NC}" >&2
  exit 1
fi

SITE_DIR="$ROOT_DIR/sites/$SITE_DOMAIN"
PHP_CONF_DIR="$ROOT_DIR/config/php-fpm/$SITE_DOMAIN"
NGINX_VHOST="$ROOT_DIR/config/nginx/conf.d/$SITE_DOMAIN.conf"
SITE_CONTAINER_NAME="php_$(echo "$SITE_DOMAIN" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c1-32)"

echo -e "${RED}========================================${NC}"
echo -e "${RED}  Удаление сайта: $SITE_DOMAIN${NC}"
echo -e "${RED}========================================${NC}"
echo

# Проверка существования
if [[ ! -d "$SITE_DIR" ]]; then
  echo -e "${RED}Ошибка: сайт '$SITE_DOMAIN' не найден${NC}" >&2
  echo "Директория: $SITE_DIR"
  exit 1
fi

# Подтверждение
echo "Будут удалены:"
echo "  • Контейнер: $SITE_CONTAINER_NAME"
echo "  • nginx конфиг: $NGINX_VHOST"
echo "  • PHP-FPM конфиги: $PHP_CONF_DIR"
if [[ "$KEEP_DATA" == "false" ]]; then
  echo "  • Файлы сайта: $SITE_DIR/www"
  echo "  • Логи: $SITE_DIR/logs"
else
  echo "  • Файлы сайта: ${YELLOW}сохранены${NC}"
fi
echo

read -p "Продолжить удаление? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Отменено."
  exit 0
fi

# ========================================
# Удаление
# ========================================

echo
echo -e "${YELLOW}==> Остановка и удаление контейнера...${NC}"
cd "$SITE_DIR"
if docker compose ps -q &>/dev/null; then
  docker compose down --volumes --remove-orphans 2>/dev/null || true
  echo "  Контейнер удалён"
else
  echo "  Контейнер не запущен"
fi

# Удаление контейнера если остался
if docker ps -a --format '{{.Names}}' | grep -q "^${SITE_CONTAINER_NAME}$"; then
  echo "  Удаляю оставшийся контейнер..."
  docker rm -f "$SITE_CONTAINER_NAME" 2>/dev/null || true
fi

echo
echo -e "${YELLOW}==> Удаление конфигов nginx...${NC}"
if [[ -f "$NGINX_VHOST" ]]; then
  rm -f "$NGINX_VHOST"
  echo "  Удалён: $NGINX_VHOST"
else
  echo "  Конфиг не найден"
fi

echo
echo -e "${YELLOW}==> Удаление конфигов PHP-FPM...${NC}"
if [[ -d "$PHP_CONF_DIR" ]]; then
  rm -rf "$PHP_CONF_DIR"
  echo "  Удалено: $PHP_CONF_DIR"
else
  echo "  Конфиги не найдены"
fi

if [[ "$KEEP_DATA" == "false" ]]; then
  echo
  echo -e "${YELLOW}==> Удаление файлов сайта...${NC}"
  if [[ -d "$SITE_DIR/www" ]]; then
    rm -rf "$SITE_DIR/www"
    echo "  Удалено: $SITE_DIR/www"
  fi
  
  if [[ -d "$SITE_DIR/logs" ]]; then
    rm -rf "$SITE_DIR/logs"
    echo "  Удалено: $SITE_DIR/logs"
  fi
  
  # Удаляем пустую директорию сайта
  if [[ -d "$SITE_DIR" && -z "$(ls -A "$SITE_DIR" 2>/dev/null)" ]]; then
    rmdir "$SITE_DIR"
    echo "  Удалена пустая директория: $SITE_DIR"
  fi
fi

echo
echo -e "${YELLOW}==> Перезапуск nginx...${NC}"
cd "$ROOT_DIR/infra"
docker compose restart nginx

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Сайт удалён!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo "Контейнер: $SITE_CONTAINER_NAME"
echo "Конфиги: удалены"
if [[ "$KEEP_DATA" == "false" ]]; then
  echo "Файлы: удалены"
fi
