## Взаимодействие сервисов и логика работы

Этот файл описывает, как связаны контейнеры и скрипты, по каким каналам они общаются и как устроен поток запросов.

---

### Сервисы и их роли

- **`nginx` (контейнер `hosting_nginx`, файл `infra/docker-compose.yml`)**
  - Единственная точка входа HTTP/HTTPS снаружи.
  - Слушает порты **80** и **443** на хосте.
  - По `server_name` определяет, к какому сайту и какому PHP-контейнеру пробрасывать запрос.
  - Обслуживает HTTP-01 challenge для Let's Encrypt.
  - Пишет логи сайтов в `sites/<домен>/logs` (маппинг `../sites:/var/www`).

- **`certbot` (контейнер `hosting_certbot`)**
  - Используется по требованию, через `docker compose run`.
  - Пишет challenge-файлы в `letsencrypt/www`, которые nginx отдаёт по `/.well-known/acme-challenge/...`.
  - Получает/обновляет TLS-сертификаты в `letsencrypt/etc`, которые nginx монтирует как `/etc/letsencrypt`.

- **`ssh` (контейнер `hosting_ssh`)**
  - Обеспечивает SSH-доступ клиентам.
  - Слушает порт **2222** на хосте.
  - Имеет volume `../sites:/srv/sites:rw`, чтобы пользователи видели свои каталоги сайтов.
  - Пользователи создаются скриптом `scripts/create_site.sh` (команда `docker exec`), их `home` указывает на `/srv/sites/<домен>`.

- **`portainer` (контейнер `hosting_portainer`)**
  - Web-интерфейс для управления Docker.
  - Слушает порты **9443** (HTTPS) и **9000** (HTTP) на хосте.
  - Имеет доступ к Docker socket (`/var/run/docker.sock`) для управления контейнерами.
  - Позволяет мониторить статусы контейнеров, просматривать логи, запускать/останавливать сервисы.
  - Первичный вход: `https://<IP_сервера>:9443/` (потребуется создать пароль администратора при первом входе).

- **`php_*` (по одному контейнеру на сайт, например `php_example_com`)**
  - Запускаются из `sites/<домен>/docker-compose.yml`.
  - Работают в сети `web` и принимают FastCGI-запросы на порту `9000`.
  - Видят код сайта через volume `./www:/var/www/html`.
  - Конфигурируются per-site через `config/php-fpm/<домен>/{php.ini,www.conf}`.

---

### Сети и каналы связи

- **Docker-сеть `web`**
  - Определена в `infra/docker-compose.yml` как:
    - `networks.web.name = web`
  - Сервисы в этой сети:
    - `hosting_nginx`
    - все `php_*` контейнеры сайтов (через `networks: web` в `sites/<домен>/docker-compose.yml`).
  - Nginx обращается к PHP-контейнерам по DNS-имени сервиса:
    - `fastcgi_pass php_example_com:9000;`
    - для новых сайтов имя контейнера задаёт скрипт `create_site.sh` (`php_<нормализованный_домен>`).

- **Внешние порты**
  - `80/tcp` → `nginx` (HTTP).
  - `443/tcp` → `nginx` (HTTPS).
  - `2222/tcp` → `hosting_ssh` (SSH-доступ клиентам).
  - `9443/tcp` → `hosting_portainer` (Web UI HTTPS).
  - `9000/tcp` → `hosting_portainer` (Web UI HTTP, опционально).

- **Volumes (общие данные)**
  - `../sites:/var/www` в nginx:
    - путь внутри контейнера: `/var/www/<домен>/www` и `/var/www/<домен>/logs`.
    - используется как `root` для сайтов и место для логов.
  - `../sites:/srv/sites` в `hosting_ssh`:
    - каждый пользователь получает `home = /srv/sites/<домен>`.
  - `/var/run/docker.sock` в `hosting_portainer`:
    - позволяет Portainer управлять Docker-демоном.
  - `portainer_data` — именованный volume для хранения настроек Portainer.
  - `../letsencrypt/etc`, `../letsencrypt/lib`, `../letsencrypt/logs`, `../letsencrypt/www`:
    - разделены между `nginx` и `certbot` для выдачи/обновления сертификатов.

---

### Поток HTTP/HTTPS-запроса

1. Клиент обращается к `http://example.com/`:
   - запрос приходит на `nginx` (порт 80).
   - серверный блок `server_name example.com`:
     - если путь `/.well-known/acme-challenge/*`, nginx отдаёт статический файл из `/var/www/letsencrypt` (нужно для Let's Encrypt).
     - все остальные пути редиректятся на `https://example.com/...`.

2. Клиент переходит на `https://example.com/`:
   - запрос снова приходит в `nginx` (порт 443).
   - используется сертификат из `/etc/letsencrypt/live/example.com/`.
   - `root /var/www/example.com/www`.
   - для статических файлов (`.css`, `.js`, картинки) nginx отдаёт файлы напрямую.
   - для `*.php`:
     - nginx формирует FastCGI-запрос.
     - `fastcgi_pass php_example_com:9000` отправляет его в соответствующий PHP-FPM контейнер по сети `web`.

3. PHP-контейнер (`php_example_com`):
   - исполняет PHP-код из `/var/www/html` (смонтирован `sites/example.com/www`).
   - отдаёт ответ обратно nginx.

---

### Поток SSH-доступа

1. Клиент подключается к `ssh -p 2222 user@host`:
   - соединение приходит в контейнер `hosting_ssh`.

2. Пользователь `user`:
   - создан скриптом `scripts/create_site.sh`.
   - имеет `home = /srv/sites/<домен>` (volume с хоста).
   - после логина попадает в каталог своего сайта:
     - может редактировать файлы в `www/`, смотреть логи в `logs/` и т.д.

3. Изоляция:
   - у каждого сайта свой пользователь и свой каталог в `/srv/sites`.
   - доступ к чужим сайтам ограничен правами файловой системы (настройка прав остаётся за админом).

---

### Логика работы скрипта `scripts/create_site.sh`

Скрипт автоматизирует создание сайта, PHP-контейнера и SSH-пользователя.

Входные параметры:

- `<домен>` — обязательный (например, `client1.example.com`).
- `[логин_пользователя]` — необязательный. Если не задан, логин генерируется из домена (буквы/цифры, остальное → `_`).

Основные шаги:

1. **Подготовка директорий и конфигов**
   - Создаёт:
     - `sites/<домен>/www`
     - `sites/<домен>/logs`
     - `config/php-fpm/<домен>/`
   - Копирует шаблоны из `example.com`:
     - `config/php-fpm/example.com/php.ini` → `config/php-fpm/<домен>/php.ini`
     - `config/php-fpm/example.com/www.conf` → `config/php-fpm/<домен>/www.conf`
     - `sites/example.com/docker-compose.yml` → `sites/<домен>/docker-compose.yml`
     - `config/nginx/conf.d/example.com.conf` → `config/nginx/conf.d/<домен>.conf`
   - Генерирует имя контейнера: `php_<нормализованный_домен>`.

2. **Правка конфигов под новый домен**
   - В `sites/<домен>/docker-compose.yml` и `config/nginx/conf.d/<домен>.conf`:
     - заменяет все вхождения `example.com` на `<домен>` (в `root`, путях логов, TLS-конфигах и т.д.).
     - заменяет `php_example_com` на новое имя контейнера `php_<нормализованный_домен>`.

3. **Начальный код сайта**
   - Если `sites/<домен>/www/index.php` отсутствует, создаёт `phpinfo()`:
     - удобно для первичной проверки.

4. **Запуск PHP-контейнера сайта**
   - Заходит в `sites/<домен>` и выполняет:
     - `docker compose up -d`
   - В результате:
     - запускается контейнер `php_<нормализованный_домен>`,
     - подключён к сети `web`,
     - видит код сайта в `./www`.

5. **Перезапуск nginx**
   - Заходит в `infra` и выполняет:
     - `docker compose restart nginx`
   - nginx подхватывает новый vhost-файл `config/nginx/conf.d/<домен>.conf`.

6. **Создание SSH-пользователя**
   - Проверяет, что контейнер `hosting_ssh` запущен.
   - Генерирует случайный пароль (16 символов).
   - Внутри `hosting_ssh` выполняет:
     - `useradd -d /srv/sites/<домен> -M -s /bin/bash <логин>`
     - `echo '<логин>:<пароль>' | chpasswd`
   - В итоге:
     - SSH-пользователь привязан к каталогу сайта.
     - Скрипт выводит логин, пароль и подсказки по SSH-подключению.

---

### Возможные точки отказа и как их избежать

- **`hosting_ssh` не запущен**:
  - скрипт явно проверяет это и выводит понятную ошибку:
    - «Подними его через `cd infra && docker compose up -d ssh`».

- **домены/пути в конфигах**:
  - все новые сайты генерируются из проверенного шаблона `example.com.conf` + sed-подстановки домена.
  - при изменении шаблона достаточно обновить только его, скрипт останется рабочим.

- **конфликты имён контейнеров**:
  - имя контейнера всегда `php_<нормализованный_домен>`; при повторном запуске скрипта для того же домена он откажется, если директория уже существует.

- **сертификаты Let's Encrypt**:
  - nginx и certbot разделяют `letsencrypt/www` и `letsencrypt/etc`.
  - HTTP-01 challenge обслуживается отдельным `location /.well-known/acme-challenge/` с `root /var/www/letsencrypt`.
  - перезапуск nginx после выдачи сертификата описан в `SETUP.md`.

