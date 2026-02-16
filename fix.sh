#!/bin/bash
set -e

echo "=== Fixing hosting infrastructure ==="

# 1. Fix templates/php-fpm/www.conf (template for new sites) - use {{DOMAIN}} placeholder
cat > templates/php-fpm/www.conf << 'EOF'
[www]
user = www-data
group = www-data

listen = 9000

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500

; Логирование - используем плейсхолдер для домена
access.log = /var/www/{{DOMAIN}}/logs/php-fpm-access.log
slowlog = /var/www/{{DOMAIN}}/logs/php-fpm-slow.log
request_slowlog_timeout = 10s

; Переменные окружения
clear_env = no

; Безопасность
php_admin_value[error_log] = /var/www/{{DOMAIN}}/logs/php_errors.log
php_admin_flag[log_errors] = on
EOF
echo "✓ Fixed templates/php-fpm/www.conf"

# 2. Fix templates/site/docker-compose.yml - use {{DOMAIN}} {{CONTAINER_NAME}} {{PHP_VERSION}} placeholders
cat > templates/site/docker-compose.yml << 'EOF'
services:
  php:
    image: php:{{PHP_VERSION}}-fpm
    container_name: {{CONTAINER_NAME}}
    restart: unless-stopped
    working_dir: /var/www/{{DOMAIN}}
    volumes:
      - ./www:/var/www/{{DOMAIN}}/www:rw
      - ./logs:/var/www/{{DOMAIN}}/logs:rw
      - ../../config/php-fpm/{{DOMAIN}}/php.ini:/usr/local/etc/php/php.ini:ro
      - ../../config/php-fpm/{{DOMAIN}}/www.conf:/usr/local/etc/php-fpm.d/www.conf:ro
    networks:
      - web

networks:
  web:
    external: true
EOF
echo "✓ Fixed templates/site/docker-compose.yml"

# 3. Fix templates/nginx/site.conf.template - use {{DOMAIN}} {{CONTAINER_NAME}} placeholders
cat > templates/nginx/site.conf.template << 'EOF'
# {{DOMAIN}} - HTTP only
# HTTPS will be added after certbot certificate generation

server {
    listen 80;
    server_name {{DOMAIN}};
    root /var/www/{{DOMAIN}}/www;
    index index.php index.html;

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    access_log /var/www/{{DOMAIN}}/logs/access.log;
    error_log /var/www/{{DOMAIN}}/logs/error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_pass {{CONTAINER_NAME}}:9000;
    }
}
EOF
echo "✓ Fixed templates/nginx/site.conf.template"

# 4. Fix infra/create_site.sh - add proper replacement for {{DOMAIN}} in www.conf
cat > infra/create_site.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

##
## Интерактивный скрипт создания сайта
##
## Использование:
##   ./scripts/create_site.sh [домен]
##
## Если домен не указан, скрипт запросит его интерактивно.
##

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/infra"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция нормализации имени для контейнера/пользователя
normalize_username() {
  local s="$1"
  # заменить всё, кроме [a-zA-Z0-9] на _
  s="${s//[^a-zA-Z0-9]/_}"
  # обрезать до 32 символов
  echo "${s:0:32}"
}

# Функция генерации случайного пароля
generate_password() {
  tr -dc 'A-Za-z0-9!@#$%^&*=' </dev/urandom | head -c 16 || true
}

# Функция проверки валидности домена
validate_domain() {
  local domain="$1"
  if [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$ ]]; then
    return 0
  fi
  return 1
}

# Функция проверки доступности Docker
check_docker() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Ошибка: Docker не установлен${NC}" >&2
    exit 1
  fi
  
  if ! docker ps &> /dev/null; then
    echo -e "${RED}Ошибка: нет прав доступа к Docker. Запустите с sudo.${NC}" >&2
    exit 1
  fi
}

# Функция проверки запущена ли инфраструктура
check_infra() {
  if ! docker ps --format '{{.Names}}' | grep -q '^hosting_nginx$'; then
    echo -e "${YELLOW}Внимание: инфраструктура не запущена.${NC}"
    echo "Запустите её командой: sudo ./infra/start.sh"
    echo

    read -p "Запустить сейчас? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      cd "$ROOT_DIR/infra"
      ./start.sh
      cd "$ROOT_DIR"
    else
      echo -e "${RED}Без инфраструктуры создание сайта невозможно.${NC}"
      exit 1
    fi
  fi
}

# Функция ожидания готовности контейнера
wait_for_container() {
  local container_name="$1"
  local max_attempts=30
  local attempt=1
  
  echo -n "    Ожидание запуска $container_name"
  while [[ $attempt -le $max_attempts ]]; do
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
      echo " - ${GREEN}готово${NC}"
      return 0
    fi
    echo -n "."
    sleep 1
    attempt=$((attempt + 1))
  done
  echo " - ${YELLOW}таймаут${NC}"
  return 1
}

# Функция безопасного reload nginx
reload_nginx() {
  echo -e "${YELLOW}==> Перезагрузка конфигурации nginx...${NC}"
  
  # Проверяем конфиг перед reload
  if ! docker exec hosting_nginx nginx -t 2>&1; then
    echo -e "${RED}Ошибка: конфигурация nginx некорректна${NC}"
    echo "Проверьте лог: docker exec hosting_nginx nginx -T"
    return 1
  fi
  
  # Используем reload вместо restart (graceful)
  docker exec hosting_nginx nginx -s reload
  echo -e "${GREEN}Nginx перезагружен${NC}"
}

echo -e "${BLUE}========================================"
echo "  Создание нового сайта"
echo -e "========================================${NC}"
echo

# Проверка Docker
check_docker

# Запрос домена
if [[ $# -ge 1 ]]; then
  SITE_DOMAIN="$1"
else
  read -p "Введите домен сайта (например, example.com): " SITE_DOMAIN
fi

# Валидация домена
if ! validate_domain "$SITE_DOMAIN"; then
  echo -e "${RED}Ошибка: некорректный домен '$SITE_DOMAIN'${NC}" >&2
  exit 1
fi

SITE_DIR="$ROOT_DIR/sites/$SITE_DOMAIN"
PHP_CONF_DIR="$ROOT_DIR/config/php-fpm/$SITE_DOMAIN"
NGINX_VHOST="$ROOT_DIR/config/nginx/conf.d/$SITE_DOMAIN.conf"

# Проверка существования сайта
if [[ -d "$SITE_DIR" ]]; then
  echo -e "${RED}Ошибка: сайт '$SITE_DOMAIN' уже существует.${NC}" >&2
  echo "Директория: $SITE_DIR"
  exit 1
fi

# Проверка инфраструктуры
check_infra

# Генерация имени пользователя по умолчанию
DEFAULT_USER=$(normalize_username "$SITE_DOMAIN")

echo
echo -e "${YELLOW}Настройка SSH-доступа:${NC}"

# Запрос логина пользователя
read -p "Логин SSH-пользователя [$DEFAULT_USER]: " SITE_USER
SITE_USER="${SITE_USER:-$DEFAULT_USER}"

# Запрос пароля
echo
echo -e "Выберите способ задания пароля:"
echo "  1) Сгенерировать автоматически"
echo "  2) Ввести вручную"
echo "  3) Без пароля (только по ключам)"
read -p "Ваш выбор [1]: " PASSWORD_CHOICE
PASSWORD_CHOICE="${PASSWORD_CHOICE:-1}"

case "$PASSWORD_CHOICE" in
  1)
    PASSWORD=$(generate_password)
    echo -e "Сгенерированный пароль: ${GREEN}$PASSWORD${NC}"
    ;;
  2)
    while true; do
      read -s -p "Введите пароль: " PASSWORD
      echo
      read -s -p "Повторите пароль: " PASSWORD_CONFIRM
      echo
      if [[ "$PASSWORD" == "$PASSWORD_CONFIRM" ]]; then
        break
      fi
      echo -e "${RED}Пароли не совпадают. Попробуйте снова.${NC}"
    done
    ;;
  3)
    PASSWORD=""
    echo -e "${YELLOW}Пароль не будет установлен. Доступ только по SSH-ключам.${NC}"
    ;;
  *)
    echo -e "${RED}Неверный выбор. Использую автоматическую генерацию.${NC}"
    PASSWORD=$(generate_password)
    echo -e "Сгенерированный пароль: ${GREEN}$PASSWORD${NC}"
    ;;
esac

# Выбор версии PHP
echo
echo -e "${YELLOW}Выбор версии PHP:${NC}"
echo "  1) PHP 8.2 (рекомендуется)"
echo "  2) PHP 8.1"
echo "  3) PHP 8.0"
echo "  4) PHP 7.4"
read -p "Ваш выбор [1]: " PHP_CHOICE
PHP_CHOICE="${PHP_CHOICE:-1}"

case "$PHP_CHOICE" in
  1) PHP_VERSION="8.2" ;;
  2) PHP_VERSION="8.1" ;;
  3) PHP_VERSION="8.0" ;;
  4) PHP_VERSION="7.4" ;;
  *) PHP_VERSION="8.2" ;;
esac

echo
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Параметры создания сайта:${NC}"
echo -e "  Домен:          ${GREEN}$SITE_DOMAIN${NC}"
echo -e "  PHP:            ${GREEN}$PHP_VERSION${NC}"
echo -e "  SSH логин:      ${GREEN}$SITE_USER${NC}"
if [[ -n "$PASSWORD" ]]; then
  echo -e "  SSH пароль:     ${GREEN}$PASSWORD${NC}"
else
  echo -e "  SSH пароль:     ${YELLOW}не установлен${NC}"
fi
echo -e "${BLUE}========================================${NC}"
echo

read -p "Продолжить создание? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
  echo "Отменено."
  exit 0
fi

# ========================================
# Создание сайта
# ========================================

SITE_CONTAINER_NAME="php_$(normalize_username "$SITE_DOMAIN")"

echo
echo -e "${YELLOW}==> Создание директорий...${NC}"
mkdir -p "$SITE_DIR/www" "$SITE_DIR/logs"
mkdir -p "$PHP_CONF_DIR"

# Создаём пустые файлы логов с правильными правами
touch "$SITE_DIR/logs/access.log"
touch "$SITE_DIR/logs/error.log"
chmod 666 "$SITE_DIR/logs/access.log" "$SITE_DIR/logs/error.log"

echo -e "${YELLOW}==> Копирование конфигов PHP-FPM из шаблонов...${NC}"
cp "$ROOT_DIR/templates/php-fpm/php.ini" "$PHP_CONF_DIR/php.ini"
cp "$ROOT_DIR/templates/php-fpm/www.conf" "$PHP_CONF_DIR/www.conf"
# Replace {{DOMAIN}} placeholder in www.conf
sed -i "s/{{DOMAIN}}/$SITE_DOMAIN/g" "$PHP_CONF_DIR/www.conf"

echo -e "${YELLOW}==> Создание конфига nginx из шаблона...${NC}"
# Копируем шаблон и заменяем плейсхолдеры
cp "$ROOT_DIR/templates/nginx/site.conf.template" "$NGINX_VHOST"
sed -i "s/{{DOMAIN}}/$SITE_DOMAIN/g" "$NGINX_VHOST"
sed -i "s/{{CONTAINER_NAME}}/$SITE_CONTAINER_NAME/g" "$NGINX_VHOST"

echo -e "${YELLOW}==> Создание docker-compose.yml для сайта...${NC}"
cp "$ROOT_DIR/templates/site/docker-compose.yml" "$SITE_DIR/docker-compose.yml"
# Заменяем плейсхолдеры в docker-compose.yml
sed -i "s/{{DOMAIN}}/$SITE_DOMAIN/g" "$SITE_DIR/docker-compose.yml"
sed -i "s/{{CONTAINER_NAME}}/$SITE_CONTAINER_NAME/g" "$SITE_DIR/docker-compose.yml"
sed -i "s/{{PHP_VERSION}}/$PHP_VERSION/g" "$SITE_DIR/docker-compose.yml"

echo -e "${YELLOW}==> Создание приветственной страницы...${NC}"
cat > "$SITE_DIR/www/index.php" << PHP
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$SITE_DOMAIN</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container {
            background: white;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .domain {
            color: #667eea;
            font-size: 1.5em;
        }
        .info {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin-top: 20px;
        }
        .info dt {
            font-weight: bold;
            color: #555;
            margin-top: 10px;
        }
        .info dd {
            margin-left: 0;
            color: #333;
        }
        .success {
            color: #28a745;
            font-size: 1.2em;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 Сайт успешно создан!</h1>
        <p class="domain">$SITE_DOMAIN</p>
        
        <p class="success">✓ Сервер настроен и работает</p>
        
        <div class="info">
            <dl>
                <dt>PHP версия:</dt>
                <dd><?php echo PHP_VERSION; ?></dd>
                
                <dt>Документальный корень:</dt>
                <dd>/var/www/$SITE_DOMAIN/www</dd>
                
                <dt>Дата создания:</dt>
                <dd><?php echo date('d.m.Y H:i'); ?></dd>
            </dl>
        </div>
        
        <div class="footer">
            <p>Замените этот файл на свой сайт</p>
            <p><small>hosting4 — Docker-хостинг</small></p>
        </div>
    </div>
</body>
</html>
PHP

echo -e "${YELLOW}==> Запуск PHP-контейнера...${NC}"
cd "$SITE_DIR"
docker compose up -d

# Ждём запуска PHP-контейнера
wait_for_container "$SITE_CONTAINER_NAME"

# Перезагружаем конфигурацию nginx (graceful reload)
reload_nginx

# Создание SSH-пользователя
echo -e "${YELLOW}==> Создание SSH-пользователя...${NC}"
if docker ps --format '{{.Names}}' | grep -q '^hosting_ssh$'; then
  SITE_DIR_IN_CONTAINER="/srv/sites/$SITE_DOMAIN"
  
  docker exec hosting_ssh bash -lc "
    id '$SITE_USER' >/dev/null 2>&1 || useradd -d '$SITE_DIR_IN_CONTAINER' -M -s /bin/bash '$SITE_USER'
  "
  
  if [[ -n "$PASSWORD" ]]; then
    docker exec hosting_ssh bash -lc "
      echo '$SITE_USER:$PASSWORD' | chpasswd
    "
  fi
  
  SSH_STATUS="${GREEN}Создан${NC}"
else
  SSH_STATUS="${RED}Контейнер SSH не запущен${NC}"
fi

# ========================================
# Получение SSL-сертификата
# ========================================

echo
echo -e "${YELLOW}==> Проверка DNS и получение SSL-сертификата...${NC}"

# Проверка DNS
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "unknown")
DOMAIN_IP=$(dig +short "$SITE_DOMAIN" A | tail -1 || true)

if [[ -z "$DOMAIN_IP" ]]; then
  echo -e "${RED}DNS-запись для $SITE_DOMAIN не найдена.${NC}"
  echo "Создайте A-запись: $SITE_DOMAIN → $SERVER_IP"
  SSL_STATUS="${YELLOW}Отложено (нет DNS)${NC}"
elif [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
  echo -e "${YELLOW}DNS указывает на другой IP: $DOMAIN_IP (сервер: $SERVER_IP)${NC}"
  SSL_STATUS="${YELLOW}Отложено (DNS не указывает на сервер)${NC}"
else
  echo -e "${GREEN}DNS корректен: $SITE_DOMAIN → $DOMAIN_IP${NC}"
  
  # Запрос email для Let's Encrypt
  echo
  read -p "Введите email для Let's Encrypt: " CERT_EMAIL
  
  if [[ -n "$CERT_EMAIL" ]]; then
    echo "Получение сертификата..."
    
    cd "$ROOT_DIR/infra"
    if docker compose run --rm certbot certonly \
      --webroot -w /var/www/letsencrypt \
      -d "$SITE_DOMAIN" \
      --email "$CERT_EMAIL" \
      --agree-tos \
      --no-eff-email 2>&1; then
      
      echo -e "${GREEN}Сертификат успешно получен!${NC}"
      
      # Обновляем конфиг добавляя HTTPS
      echo -e "${YELLOW}==> Обновление конфига nginx с HTTPS...${NC}"
      cat > "$NGINX_VHOST" << NGINX
server {
   listen 80;
   server_name $SITE_DOMAIN;
   root /var/www/$SITE_DOMAIN/www;
   index index.php index.html;

   # ACME-challenge для Let's Encrypt
   location /.well-known/acme-challenge/ {
       root /var/www/letsencrypt;
   }

   # Редирект на HTTPS
   location / {
       return 301 https://\$host\$request_uri;
   }
}

server {
   listen 443 ssl;
   http2;
   server_name $SITE_DOMAIN;

   ssl_certificate /etc/letsencrypt/live/$SITE_DOMAIN/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$SITE_DOMAIN/privkey.pem;
   ssl_protocols TLSv1.2 TLSv1.3;
   ssl_prefer_server_ciphers on;

   root /var/www/$SITE_DOMAIN/www;
   index index.php index.html;

   access_log /var/www/$SITE_DOMAIN/logs/access.log;
   error_log /var/www/$SITE_DOMAIN/logs/error.log;

   location / {
       try_files \$uri \$uri/ /index.php?\$query_string;
   }

   location ~ \.php\$ {
       include fastcgi_params;
       fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
       fastcgi_pass $SITE_CONTAINER_NAME:9000;
   }
}
NGINX
      
      reload_nginx
      SSL_STATUS="${GREEN}Получен${NC}"
    else
      echo -e "${RED}Не удалось получить сертификат.${NC}"
      echo "Возможно, DNS ещё не обновился. Попробуйте позже:"
      echo "  cd infra && docker compose run --rm certbot certonly --webroot -w /var/www/letsencrypt -d $SITE_DOMAIN --email $CERT_EMAIL --agree-tos"
      SSL_STATUS="${RED}Ошибка${NC}"
    fi
  else
    SSL_STATUS="${YELLOW}Пропущено${NC}"
  fi
fi

# ========================================
# Итоговый вывод
# ========================================

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Сайт успешно создан!${NC}"
echo -e "${GREEN}========================================${NC}"
echo
echo -e "  Домен:        ${GREEN}$SITE_DOMAIN${NC}"
echo -e "  PHP:          ${GREEN}$PHP_VERSION${NC}"
echo -e "  Контейнер:    ${GREEN}$SITE_CONTAINER_NAME${NC}"
echo -e "  SSL:          $SSL_STATUS"
echo

echo -e "${YELLOW}SSH-доступ:${NC}"
echo -e "  Хост:         ${GREEN}<IP_сервера>${NC}"
echo -e "  Порт:         ${GREEN}2222${NC}"
echo -e "  Логин:        ${GREEN}$SITE_USER${NC}"
if [[ -n "$PASSWORD" ]]; then
  echo -e "  Пароль:       ${GREEN}$PASSWORD${NC}"
fi
EOF
chmod +x infra/create_site.sh
echo "✓ Fixed infra/create_site.sh"

# 5. Fix config/php-fpm/blablatest3.tagan.ru/www.conf (existing site)
cat > config/php-fpm/blablatest3.tagan.ru/www.conf << 'EOF'
[www]
user = www-data
group = www-data

listen = 9000

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500

; Логирование - используем конкретный путь для сайта
access.log = /var/www/blablatest3.tagan.ru/logs/php-fpm-access.log
slowlog = /var/www/blablatest3.tagan.ru/logs/php-fpm-slow.log
request_slowlog_timeout = 10s

; Переменные окружения
clear_env = no

; Безопасность
php_admin_value[error_log] = /var/www/blablatest3.tagan.ru/logs/php_errors.log
php_admin_flag[log_errors] = on
EOF
echo "✓ Fixed config/php-fpm/blablatest3.tagan.ru/www.conf"

# 6. Fix config/php-fpm/blablatest2.tagan.ru/www.conf (existing site)
cat > config/php-fpm/blablatest2.tagan.ru/www.conf << 'EOF'
[www]
user = www-data
group = www-data

listen = 9000

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500

; Логирование - используем конкретный путь для сайта
access.log = /var/www/blablatest2.tagan.ru/logs/php-fpm-access.log
slowlog = /var/www/blablatest2.tagan.ru/logs/php-fpm-slow.log
request_slowlog_timeout = 10s

; Переменные окружения
clear_env = no

; Безопасность
php_admin_value[error_log] = /var/www/blablatest2.tagan.ru/logs/php_errors.log
php_admin_flag[log_errors] = on
EOF
echo "✓ Fixed config/php-fpm/blablatest2.tagan.ru/www.conf"

# 7. Check and create logs directories for sites if they don't exist
echo ""
echo "=== Checking logs directories ==="
for site_dir in sites/*; do
    if [[ -d "$site_dir" ]]; then
        logs_dir="$site_dir/logs"
        if [[ ! -d "$logs_dir" ]]; then
            mkdir -p "$logs_dir"
            echo "✓ Created logs directory: $logs_dir"
        else
            echo "✓ Logs directory exists: $logs_dir"
        fi
        # Create log files if they don't exist
        touch "$logs_dir/access.log" "$logs_dir/error.log" "$logs_dir/php_errors.log" "$logs_dir/php-fpm-access.log" "$logs_dir/php-fpm-slow.log"
        # Set proper permissions
        chmod 755 "$logs_dir" 2>/dev/null || true
        chmod 666 "$logs_dir"/* 2>/dev/null || true
    fi
done

# 8. Skip Docker commands for now - will run separately from terminal
echo ""
echo "=== Configuration updates completed ==="
echo ""
echo "To apply the changes to existing sites:"
echo "1. Run the following commands from your terminal (with sudo):"
echo "   cd /srv/hosting4"
echo "   sudo docker stop php_blablatest3_tagan_ru php_blablatest4_tagan_ru"
echo "   sudo docker rm php_blablatest3_tagan_ru php_blablatest4_tagan_ru"
echo "   cd sites/blablatest3.tagan.ru && sudo docker compose up -d"
echo "   cd ../blablatest4.tagan.ru && sudo docker compose up -d"
echo ""
echo "2. Then test your sites:"
echo "   curl -s http://blablatest3.tagan.ru/"
echo "   curl -s http://blablatest4.tagan.ru/"
