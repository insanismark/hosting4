## Хостинг-каркас на Docker

Минимальный каркас для тестов на ВМ, с поддержкой HTTPS через Let's Encrypt:

- **`infra/docker-compose.yml`** – nginx + SSH + Portainer + общая сеть `web`.
- **`sites/example.com/docker-compose.yml`** – контейнер PHP-FPM для тестового сайта.
- **`config/nginx/*`** – конфиги nginx (общий и виртуальный хост).
- **`config/php-fpm/example.com/*`** – конфиги PHP-FPM для тестового сайта.
- **`sites/example.com/www`** – web-root примера.

### Требования

- Docker и Docker Compose (v2, встроенный в `docker`) — установка описана в `SETUP.md`.

### Быстрый старт (тест на одной ВМ)

#### Вариант 1: Через скрипт start.sh (рекомендуется)

```bash
cd /srv/hosting4/infra
./start.sh
```

Скрипт автоматически:
- создаст необходимые директории (letsencrypt, ssh/config);
- запустит все инфраструктурные сервисы (nginx, ssh, portainer, certbot);
- найдёт и запустит все сайты из `sites/*/docker-compose.yml`.

Опции:
- `./start.sh --no-sites` — запустить только инфраструктуру без сайтов.

#### Вариант 2: Вручную

```bash
# 1. Поднять инфраструктуру (nginx + ssh + portainer + сеть web)
cd infra
docker compose up -d

# 2. Поднять тестовый сайт example.com (PHP-FPM)
cd ../sites/example.com
docker compose up -d
```

После этого:

- Nginx слушает порты **80** и **443** на хосте.
- Portainer доступен по `https://<IP_вашей_ВМ>:9443/`.
- Тестовый сайт доступен по `http://<IP_вашей_ВМ>/` и `https://<IP_вашей_ВМ>/` (для HTTPS нужны реальные сертификаты, см. `SETUP.md`).

### Проверка

В браузере или через `curl`:

```bash
curl http://localhost/
```

Должен отобразиться простой `phpinfo()` из `sites/example.com/www/index.php`.

После получения реальных сертификатов через Let's Encrypt (`SETUP.md`) сайт будет доступен и по HTTPS.

### Структура

- `infra/` – docker-compose для общих сервисов (nginx + ssh + portainer + certbot + сеть `web`).
- `infra/start.sh` – скрипт запуска всей инфраструктуры одним командой.
- `infra/create_site.sh` – интерактивный скрипт создания сайта + PHP-контейнера + SSH-пользователя + SSL.
- `config/nginx/` – nginx-конфиги.
- `config/php-fpm/` – конфиги php-fpm по сайтам.
- `sites/<домен>/docker-compose.yml` – сервисы конкретного сайта.
- `sites/<домен>/www` – web-root сайта.
- `sites/<домен>/logs` – логи сайта (для nginx/fastcgi, если захотите туда писать).
- `ARCHITECTURE.md` – описание взаимодействия контейнеров и логики работы.

### Порты сервисов

| Порт | Сервис | Назначение |
|------|--------|------------|
| 80 | nginx | HTTP |
| 443 | nginx | HTTPS |
| 2222 | ssh | SSH-доступ для клиентов |
| 9443 | portainer | Web UI для управления Docker (HTTPS) |
| 9000 | portainer | Web UI для управления Docker (HTTP, опционально) |

### Как добавить первый (или следующий) сайт

Есть два варианта:

- автоматически, через интерактивный скрипт `infra/create_site.sh` (рекомендуется);
- вручную, по шагам ниже.

#### Вариант 1. Скрипт `infra/create_site.sh` (рекомендуется)

```bash
cd /srv/hosting4
sudo ./infra/create_site.sh
# или с указанием домена:
# sudo ./infra/create_site.sh mysite.local
```

Скрипт интерактивно запросит:
- **Домен** — если не указан в аргументах
- **SSH-логин** — с предложением по умолчанию
- **Пароль SSH** — сгенерировать / ввести вручную / без пароля
- **Версию PHP** — 7.4, 8.0, 8.1 или 8.2
- **Email для Let's Encrypt** — для получения SSL-сертификата

Скрипт автоматически:
- создаст директории `sites/<домен>/{www,logs}`;
- скопирует и настроит конфиги php-fpm и nginx;
- создаст приветственную заглушку;
- поднимет PHP-контейнер сайта;
- перезапустит nginx;
- создаст SSH-пользователя;
- проверит DNS и получит SSL-сертификат (если DNS указывает на сервер).

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

