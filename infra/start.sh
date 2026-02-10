#!/usr/bin/env bash
set -euo pipefail

##
## Скрипт запуска всей инфраструктуры хостинга
##
## Использование:
##   ./start.sh [опции]
##
## Опции:
##   --no-sites    Не запускать контейнеры сайтов (только infra)
##   --force       Остановить конфликтующие контейнеры перед запуском
##   --stop        Остановить все сервисы вместо запуска
##   --status      Показать статус всех контейнеров
##

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NO_SITES=false
FORCE=false
ACTION="start"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-sites)
      NO_SITES=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --stop)
      ACTION="stop"
      shift
      ;;
    --status)
      ACTION="status"
      shift
      ;;
    -h|--help)
      echo "Использование: $0 [опции]"
      echo ""
      echo "Опции:"
      echo "  --no-sites    Не запускать контейнеры сайтов (только infra)"
      echo "  --force       Остановить конфликтующие контейнеры перед запуском"
      echo "  --stop        Остановить все сервисы"
      echo "  --status      Показать статус контейнеров"
      echo "  -h, --help    Показать эту справку"
      exit 0
      ;;
    *)
      echo -e "${RED}Неизвестный аргумент: $1${NC}" >&2
      exit 1
      ;;
  esac
done

# Функция проверки занятости порта (системная)
check_port_system() {
  local port="$1"
  if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    return 0  # Порт занят
  fi
  return 1  # Порт свободен
}

# Функция получения контейнера, занимающего порт
get_container_by_port() {
  local port="$1"
  docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null | grep ":${port}->" | cut -f1 | head -1 || true
}

# Функция проверки и освобождения портов
check_and_free_ports() {
  local conflict_found=false
  local system_conflict=false

  echo -e "${YELLOW}==> Проверка занятости портов...${NC}"
  
  # Проверяем все Docker-порты: 80/443 (nginx), 2222 (ssh), 9000/9443 (portainer)
  for port in 80 443 2222 9443 9000; do
    # Сначала проверяем Docker-контейнеры
    container=$(get_container_by_port "$port")
    if [[ -n "$container" ]]; then
      if [[ "$FORCE" == "true" ]]; then
        echo -e "  Порт $port занят контейнером $container — ${YELLOW}будет остановлен${NC}"
      else
        echo -e "  ${RED}Порт $port занят контейнером: $container${NC}"
        conflict_found=true
      fi
    # Затем проверяем системные процессы
    elif check_port_system "$port"; then
      echo -e "  ${RED}Порт $port занят системным процессом${NC}"
      system_conflict=true
      conflict_found=true
    else
      echo -e "  ${GREEN}Порт $port свободен${NC}"
    fi
  done

  if [[ "$system_conflict" == "true" ]]; then
    echo ""
    echo -e "${RED}Ошибка: некоторые порты заняты системными процессами.${NC}"
    echo ""
    echo "Проверьте какие процессы занимают порты:"
    echo "  sudo ss -tlnp | grep -E ':(80|443|2222|9443|9000) '"
    echo ""
    echo "Возможные причины:"
    echo "  • Системный nginx/apache на портах 80/443"
    echo "  • SSH-сервер на порту 2222"
    echo "  • Portainer на портах 9000/9443"
    echo "  • Старые контейнеры (проверьте: docker ps -a)"
    echo ""
    echo "Решения:"
    echo "  • Остановите системный nginx: sudo systemctl stop nginx"
    echo "  • Остановите конфликтующие контейнеры: docker rm -f <имя>"
    echo "  • Измените порты в docker-compose.yml"
    echo ""
    echo "После этого запустите: sudo $0 --force"
    exit 1
    fi
  
    if [[ "$conflict_found" == "true" && "$FORCE" == "false" ]]; then
      echo ""
      echo -e "${RED}Ошибка: некоторые порты заняты Docker-контейнерами.${NC}"
      echo "Варианты решения:"
      echo "  1. Остановите конфликтующие контейнеры: docker rm -f <имя_контейнера>"
      echo "  2. Используйте --force для автоматической остановки"
      echo ""
      echo "Пример: sudo $0 --force"
      exit 1
    fi
  
    # Останавливаем конфликтующие контейнеры если --force
    if [[ "$FORCE" == "true" ]]; then
      echo ""
      echo "==> Остановка конфликтующих контейнеров..."
      for port in 80 443 2222 9443 9000; do
      container=$(get_container_by_port "$port")
      if [[ -n "$container" ]]; then
        echo "  Остановка: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
      fi
    done
  fi
}

# Функция остановки всех сервисов
stop_all() {
  echo -e "${YELLOW}==> Остановка инфраструктурных сервисов...${NC}"
  cd "$SCRIPT_DIR"
  docker compose down
  
  echo ""
  echo -e "${YELLOW}==> Остановка сайтов...${NC}"
  for site_compose in "$ROOT_DIR"/sites/*/docker-compose.yml; do
    if [[ -f "$site_compose" ]]; then
      site_dir="$(dirname "$site_compose")"
      site_name="$(basename "$site_dir")"
      echo "  Остановка: $site_name"
      cd "$site_dir"
      docker compose down
    fi
  done
  
  echo ""
  echo -e "${GREEN}Все сервисы остановлены.${NC}"
}

# Функция показа статуса
show_status() {
  echo -e "${YELLOW}==> Статус инфраструктурных сервисов:${NC}"
  cd "$SCRIPT_DIR"
  docker compose ps 2>/dev/null || echo "  Инфраструктура не запущена"
  
  echo ""
  echo -e "${YELLOW}==> Статус сайтов:${NC}"
  local found=false
  for site_compose in "$ROOT_DIR"/sites/*/docker-compose.yml; do
    if [[ -f "$site_compose" ]]; then
      site_dir="$(dirname "$site_compose")"
      site_name="$(basename "$site_dir")"
      cd "$site_dir"
      status=$(docker compose ps -q 2>/dev/null | head -1 || true)
      if [[ -n "$status" ]]; then
        echo "  ${GREEN}●${NC} $site_name — запущен"
      else
        echo "  ${RED}○${NC} $site_name — остановлен"
      fi
      found=true
    fi
  done
  
  if [[ "$found" == "false" ]]; then
    echo "  Сайтов не найдено"
  fi
}

echo "=========================================="
echo "  Хостинг-инфраструктура"
echo "=========================================="
echo

# Проверка наличия Docker
if ! command -v docker &> /dev/null; then
  echo -e "${RED}Ошибка: Docker не установлен${NC}" >&2
  echo "Установите Docker по инструкции в SETUP.md" >&2
  exit 1
fi

# Проверка прав доступа к Docker
if ! docker ps &> /dev/null; then
  echo -e "${RED}Ошибка: нет прав доступа к Docker${NC}" >&2
  echo ""
  echo "Варианты решения:"
  echo "  1. Запустите с sudo: sudo $0 $*"
  echo "  2. Добавьте пользователя в группу docker: sudo usermod -aG docker \$USER"
  echo "     (после этого нужно перелогиниться)"
  exit 1
fi

if ! docker compose version &> /dev/null; then
  echo -e "${RED}Ошибка: Docker Compose не установлен${NC}" >&2
  exit 1
fi

# Обработка действий
case "$ACTION" in
  stop)
    stop_all
    exit 0
    ;;
  status)
    show_status
    exit 0
    ;;
esac

# Проверка портов перед запуском
check_and_free_ports

# Создание директорий
echo ""
echo "==> Проверка директорий..."
mkdir -p "$ROOT_DIR/letsencrypt/etc"
mkdir -p "$ROOT_DIR/letsencrypt/lib"
mkdir -p "$ROOT_DIR/letsencrypt/logs"
mkdir -p "$ROOT_DIR/letsencrypt/www"
mkdir -p "$ROOT_DIR/ssh/config"
mkdir -p "$ROOT_DIR/sites"

# Запуск инфраструктуры (nginx, ssh, portainer, certbot)
echo ""
echo "==> Запуск инфраструктурных сервисов (nginx, ssh, portainer, certbot)..."
cd "$SCRIPT_DIR"
docker compose up -d

echo ""
echo "==> Проверка статуса контейнеров инфраструктуры:"
docker compose ps

# Запуск сайтов
if [[ "$NO_SITES" == "false" ]]; then
  echo ""
  echo "==> Поиск и запуск сайтов..."
  
  SITES_COUNT=0
  
  for site_compose in "$ROOT_DIR"/sites/*/docker-compose.yml; do
    if [[ -f "$site_compose" ]]; then
      site_dir="$(dirname "$site_compose")"
      site_name="$(basename "$site_dir")"
      
      echo "    -> Запуск сайта: $site_name"
      cd "$site_dir"
      docker compose up -d
      
      SITES_COUNT=$((SITES_COUNT + 1))
    fi
  done
  
  if [[ $SITES_COUNT -eq 0 ]]; then
    echo "    Сайтов не найдено. Создайте сайт через scripts/create_site.sh"
  else
    echo ""
    echo "==> Запущено сайтов: $SITES_COUNT"
  fi
fi

# Проверка и запуск nginx ПОСЛЕ создания контейнеров
# Nginx запускается через docker compose (hosting_nginx)
echo ""
echo "=========================================="
echo -e "  ${GREEN}Инфраструктура запущена!${NC}"
echo "=========================================="
echo
echo "Сервисы:"
echo "  • Nginx:      http://localhost/  или  https://localhost/"
echo "  • Portainer:  https://localhost:9443/"
echo "  • SSH:        ssh -p 2222 admin@localhost"
echo
echo "Docker-контейнеры:"
echo "  • 80/443 — Nginx (hosting_nginx)"
echo "  • 2222   — SSH (hosting_ssh)"
echo "  • 9443   — Portainer Web UI (HTTPS)"
echo "  • 9000   — Portainer Web UI (HTTP)"
echo
echo "Управление:"
echo "  • Сайты:      sudo ./create_site.sh"
echo "  • Nginx:      cd infra && docker compose restart nginx"
echo "  • Остановить:  sudo $0 --stop"
echo "  • Статус:      sudo $0 --status"
echo
