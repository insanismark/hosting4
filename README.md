## Хостинг-каркас на Docker

Минимальный каркас для тестов на ВМ, с поддержкой HTTPS через Let's Encrypt:

- **`infra/docker-compose.yml`** – nginx + SSH + общая сеть `web` (позже сюда можно добавить FTP).
- **`sites/example.com/docker-compose.yml`** – контейнер PHP-FPM для тестового сайта.
- **`config/nginx/*`** – конфиги nginx (общий и виртуальный хост).
- **`config/php-fpm/example.com/*`** – конфиги PHP-FPM для тестового сайта.
- **`sites/example.com/www`** – web-root примера.

### Требования

- Docker и Docker Compose (v2, встроенный в `docker`) — установка описана в `SETUP.md`.

### Быстрый старт (тест на одной ВМ)

Из корня проекта (`hosting4`):

```bash
# 1. Поднять инфраструктуру (nginx + сеть web)
cd infra
docker compose up -d

# 2. Поднять тестовый сайт example.com (PHP-FPM)
cd ../sites/example.com
docker compose up -d
```

После этого:

- Nginx слушает порты **80** и **443** на хосте.
- Тестовый сайт доступен по `http://<IP_вашей_ВМ>/` и `https://<IP_вашей_ВМ>/` (для HTTPS нужны реальные сертификаты, см. `SETUP.md`).

### Проверка

В браузере или через `curl`:

```bash
curl http://localhost/
```

Должен отобразиться простой `phpinfo()` из `sites/example.com/www/index.php`.

После получения реальных сертификатов через Let's Encrypt (`SETUP.md`) сайт будет доступен и по HTTPS.

### Структура

- `infra/` – docker-compose для общих сервисов (сейчас только nginx + сеть `web`).
- `config/nginx/` – nginx-конфиги.
- `config/php-fpm/` – конфиги php-fpm по сайтам.
- `sites/<домен>/docker-compose.yml` – сервисы конкретного сайта.
- `sites/<домен>/www` – web-root сайта.
- `sites/<домен>/logs` – логи сайта (для nginx/fastcgi, если захотите туда писать).
- `scripts/create_site.sh` – скрипт автоматического создания сайта + PHP-контейнера + SSH-пользователя.
- `ARCHITECTURE.md` – описание взаимодействия контейнеров и логики работы.

### Как добавить первый (или следующий) сайт

Есть два варианта:

- вручную, по шагам ниже;
- автоматически, через скрипт `scripts/create_site.sh` (рекомендуется).

#### Вариант 1. Скрипт `scripts/create_site.sh` (рекомендуется)

```bash
cd /srv/hosting4

./scripts/create_site.sh mysite.local
# или с явным логином:
# ./scripts/create_site.sh mysite.local client1
```

Скрипт:

- создаст директории `sites/mysite.local/{www,logs}`;
- скопирует и поправит конфиги php-fpm и nginx из шаблона `example.com`;
- поднимет PHP-контейнер сайта;
- перезапустит nginx;
- создаст SSH-пользователя в контейнере `hosting_ssh` и выведет логин/пароль.

После этого:

- добавьте DNS-запись на домен (`A` → IP сервера) и (при необходимости) получите сертификат Let’s Encrypt по инструкции в `SETUP.md`;
- проверьте сайт по `http://mysite.local` (через `/etc/hosts`) или по IP c заголовком `Host`.

#### Вариант 2. Вручную, по шагам

Допустим, хотим добавить сайт `mysite.local` с контейнером `php_mysite_local` и PHP 8.2.

1. **Создать директории сайта:**

   ```bash
   mkdir -p sites/mysite.local/www
   mkdir -p sites/mysite.local/logs
   ```

2. **Создать `docker-compose.yml` для сайта (по аналогии с `sites/example.com/docker-compose.yml`):**

   Пример:

   ```yaml
   version: "3.9"

   networks:
     web:
       external: true

   services:
     php_mysite_local:
       image: php:8.2-fpm         # один из вашего пула образов
       container_name: php_mysite_local
       restart: unless-stopped
       networks:
         - web
       working_dir: /var/www/html
       volumes:
         - ./www:/var/www/html:rw
         - ../../config/php-fpm/mysite.local/php.ini:/usr/local/etc/php/conf.d/site.ini:ro
         - ../../config/php-fpm/mysite.local/www.conf:/usr/local/etc/php-fpm.d/www.conf:ro
   ```

3. **Добавить конфиги php-fpm для сайта:**

   ```bash
   mkdir -p config/php-fpm/mysite.local
   cp config/php-fpm/example.com/php.ini config/php-fpm/mysite.local/php.ini
   cp config/php-fpm/example.com/www.conf config/php-fpm/mysite.local/www.conf
   ```

   Затем в `php.ini` и `www.conf` при необходимости:

   - поправить пути к логам на `mysite.local` (например, `/var/www/mysite.local/logs/php-error.log`);
   - настроить лимиты (`memory_limit`, `max_children` и т.д.).

4. **Добавить виртуальный хост nginx:**

   Создать файл `config/nginx/conf.d/mysite.local.conf` по аналогии с `example.com.conf`:

   ```nginx
   server {
       listen 80;
       server_name mysite.local;

       root /var/www/mysite.local/www;
       index index.php index.html;

       access_log /var/www/mysite.local/logs/access.log;
       error_log  /var/www/mysite.local/logs/error.log;

       location / {
           try_files $uri $uri/ /index.php?$query_string;
       }

       location ~ \.php$ {
           include fastcgi_params;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           fastcgi_pass php_mysite_local:9000;
       }
   }
   ```

5. **Положить начальный код сайта:**

   ```bash
   echo "<?php phpinfo();" > sites/mysite.local/www/index.php
   ```

6. **Поднять контейнер нового сайта и перегрузить nginx:**

   ```bash
   # поднять PHP-FPM контейнер сайта
   cd sites/mysite.local
   docker compose up -d

   # вернутьcя в infra и перегрузить nginx (чтобы подхватил новый vhost)
   cd ../../infra
   docker compose restart nginx
   ```

7. **Проверить сайт:**

   - добавить в `/etc/hosts` на своей машине строку `IP_ВМ mysite.local`, либо
   - обратиться по IP: `curl -H "Host: mysite.local" http://<IP_ВМ>/`.

### Пул образов PHP

Сейчас пример использует образ `php:8.2-fpm`, но идея в том, чтобы иметь ограниченный пул образов:

- `php:7.4-fpm`
- `php:8.0-fpm`
- `php:8.1-fpm`
- `php:8.2-fpm`

и т.д. (или свои образы из приватного реестра). Для каждого сайта вы в его `docker-compose.yml` просто выбираете нужный образ из пула, не собирая клиентам персональные образы.

### Чего пока нет и что можно добавить

- **FTP:** каркас сейчас покрывает nginx + PHP-FPM, многосайтовость через общую сеть `web`, HTTPS через Let's Encrypt и SSH-доступ через контейнер `hosting_ssh`. Логичный следующий шаг — добавить FTP-контейнер и настроить для него маппинг `sites/*` с jail по пользователям/сайтам.
- **Ротация логов:** nginx и PHP логируют в каталоги сайтов (`sites/<домен>/logs`), но ротация (logrotate / отдельный контейнер) не настроена.
- **Мониторинг/метрики:** можно добавить exporters (nginx, node, docker) и связать с Prometheus/Grafana.
- **Автоматизация создания сайтов:** скрипт/утилита, которая по домену генерирует директории, `docker-compose.yml`, nginx/php-fpm-конфиги и сразу поднимает контейнер.

Базовый каркас уже позволяет:

- поднять инфраструктуру (`infra/nginx` + сеть `web`);
- запускать отдельные PHP-FPM контейнеры по сайту;
- добавлять новые сайты, просто создавая им свой `docker-compose.yml`, php-fpm и nginx-конфиги.

