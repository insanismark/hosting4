#!/usr/bin/env bash
set -euo pipefail

##
## Скрипт создания сайта + PHP-контейнера + SSH-пользователя
##
## Использование:
##   ./scripts/create_site.sh <домен> [логин_пользователя]
##
## Примеры:
##   ./scripts/create_site.sh example.org
##   ./scripts/create_site.sh client1.example.com client1
##
## Предполагается, что:
## - вы уже подняли инфраструктуру: `cd infra && docker compose up -d`
## - контейнер `hosting_ssh` запущен и видит volume `../sites` как `/srv/sites`
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <domain> [username]" >&2
  exit 1
fi

SITE_DOMAIN="$1"

normalize_username() {
  local s="$1"
  # заменить всё, кроме [a-zA-Z0-9] на _
  s="${s//[^a-zA-Z0-9]/_}"
  # обрезать до 32 символов
  echo "${s:0:32}"
}

SITE_USER="${2:-$(normalize_username "$SITE_DOMAIN")}"

SITE_DIR="$ROOT_DIR/sites/$SITE_DOMAIN"
PHP_CONF_DIR="$ROOT_DIR/config/php-fpm/$SITE_DOMAIN"
NGINX_VHOST="$ROOT_DIR/config/nginx/conf.d/$SITE_DOMAIN.conf"

PHP_TEMPLATE_SITE="example.com"
PHP_TEMPLATE_CONTAINER="php_example_com"

SITE_CONTAINER_NAME="php_$(normalize_username "$SITE_DOMAIN")"

echo "==> Создаём сайт '$SITE_DOMAIN'"
echo "    Пользователь SSH: $SITE_USER"
echo "    PHP-контейнер:    $SITE_CONTAINER_NAME"
echo

if [[ -d "$SITE_DIR" ]]; then
  echo "Ошибка: директория сайта уже существует: $SITE_DIR" >&2
  exit 1
fi

mkdir -p "$SITE_DIR/www" "$SITE_DIR/logs"
mkdir -p "$PHP_CONF_DIR"

echo "==> Копируем базовые конфиги PHP-FPM и docker-compose"

cp "$ROOT_DIR/config/php-fpm/$PHP_TEMPLATE_SITE/php.ini" "$PHP_CONF_DIR/php.ini"
cp "$ROOT_DIR/config/php-fpm/$PHP_TEMPLATE_SITE/www.conf" "$PHP_CONF_DIR/www.conf"

cp "$ROOT_DIR/sites/$PHP_TEMPLATE_SITE/docker-compose.yml" "$SITE_DIR/docker-compose.yml"
cp "$ROOT_DIR/config/nginx/conf.d/$PHP_TEMPLATE_SITE.conf" "$NGINX_VHOST"

echo "==> Правим конфиги под домен и имя контейнера"

# Заменяем example.com на новый домен
sed -i "s/$PHP_TEMPLATE_SITE/$SITE_DOMAIN/g" "$SITE_DIR/docker-compose.yml"
sed -i "s/$PHP_TEMPLATE_SITE/$SITE_DOMAIN/g" "$NGINX_VHOST"

# Заменяем имя контейнера php_example_com на новое
sed -i "s/$PHP_TEMPLATE_CONTAINER/$SITE_CONTAINER_NAME/g" "$SITE_DIR/docker-compose.yml"
sed -i "s/$PHP_TEMPLATE_CONTAINER/$SITE_CONTAINER_NAME/g" "$NGINX_VHOST"

echo "==> Создаём начальный index.php (если его ещё нет)"

if [[ ! -f "$SITE_DIR/www/index.php" ]]; then
  cat > "$SITE_DIR/www/index.php" <<'PHP'
<?php
phpinfo();
PHP
fi

echo "==> Поднимаем PHP-контейнер сайта"

(
  cd "$SITE_DIR"
  docker compose up -d
)

echo "==> Перезапускаем nginx, чтобы подхватить новый vhost"

(
  cd "$ROOT_DIR/infra"
  docker compose restart nginx
)

echo "==> Создаём SSH-пользователя внутри контейнера hosting_ssh"

if ! docker ps --format '{{.Names}}' | grep -q '^hosting_ssh$'; then
  echo "Ошибка: контейнер hosting_ssh не запущен. Подними его через 'cd infra && docker compose up -d ssh'." >&2
  exit 1
fi

# Генерируем случайный пароль (16 символов, только безопасные)
PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"

SITE_DIR_IN_CONTAINER="/srv/sites/$SITE_DOMAIN"

docker exec hosting_ssh bash -lc "
  id '$SITE_USER' >/dev/null 2>&1 || useradd -d '$SITE_DIR_IN_CONTAINER' -M -s /bin/bash '$SITE_USER'
  echo '$SITE_USER:$PASSWORD' | chpasswd
"

echo
echo "================================================================"
echo "Сайт создан."
echo
echo "Домен:        $SITE_DOMAIN"
echo "PHP-контейнер: $SITE_CONTAINER_NAME"
echo
echo "SSH-доступ:"
echo "  Хост:     <IP_сервера>"
echo "  Порт:     2222"
echo "  Логин:    $SITE_USER"
echo "  Пароль:   $PASSWORD"
echo
echo "Каталог сайта на хосте: $SITE_DIR"
echo "================================================================"

