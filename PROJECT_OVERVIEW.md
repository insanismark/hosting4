# Обзор проекта hosting4

## Описание

Минимальный хостинг-фреймворк для VPS с поддержкой HTTPS через Let's Encrypt. Каждый сайт работает в отдельном PHP-FPM контейнере, что обеспечивает изоляцию и гибкость настройки.

## Архитектура

### Компоненты инфраструктуры

1. **Nginx** (контейнер `hosting_nginx`)
   - Reverse proxy для всех сайтов
   - Обработка HTTP/HTTPS запросов
   - Проксирование PHP запросов в соответствующие PHP-FPM контейнеры
   - Порты: 80 (HTTP), 443 (HTTPS)

2. **Certbot** (контейнер `hosting_certbot`)
   - Автоматическое получение SSL сертификатов Let's Encrypt
   - Обновление сертификатов

3. **SSH Server** (контейнер `hosting_ssh`)
   - LinuxServer.io openssh-server
   - Доступ клиентов к файлам сайтов через SFTP/SSH
   - Порт: 2222

4. **Portainer** (контейнер `portainer`)
   - Web UI для управления Docker контейнерами
   - Порты: 9000 (HTTP), 9443 (HTTPS)

5. **PHP-FPM контейнеры** (по одному на сайт)
   - Отдельный контейнер для каждого сайта
   - Имя: `php_<домен_без_точек>`
   - Версии PHP: 7.4, 8.0, 8.1, 8.2
   - Порт: 9000 (внутри Docker сети)

### Docker сеть

Все контейнеры подключены к bridge-сети `web`, что позволяет им общаться по именам контейнеров.

## Структура директорий

```
/srv/hosting4/
├── config/                      # Конфигурационные файлы
│   ├── nginx/
│   │   ├── nginx.conf          # Основной конфиг nginx
│   │   └── conf.d/             # Виртуальные хосты (по одному на сайт)
│   │       └── .gitkeep
│   └── php-fpm/                # Конфиги PHP-FPM (по директории на сайт)
│       └── .gitkeep
│
├── sites/                       # Файлы сайтов
│   ├── .gitkeep
│   └── <домен>/                # Директория сайта
│       ├── docker-compose.yml  # Docker Compose для PHP-FPM контейнера
│       ├── www/                # Корневая директория сайта
│       └── logs/               # Логи сайта
│
├── templates/                   # Шаблоны для создания сайтов
│   ├── php-fpm/
│   │   ├── php.ini             # Шаблон настроек PHP
│   │   └── www.conf            # Шаблон настроек PHP-FPM пула
│   ├── nginx/
│   │   └── site.conf.template  # Пример конфига nginx
│   ├── site/
│   │   └── docker-compose.yml  # Шаблон Docker Compose
│   └── README.md
│
├── infra/                       # Скрипты управления инфраструктурой
│   ├── docker-compose.yml      # Основная инфраструктура
│   ├── start.sh                # Запуск всей инфраструктуры
│   ├── create_site.sh          # Создание нового сайта
│   ├── delete_site.sh          # Удаление сайта
│   ├── restart_nginx.sh        # Перезапуск nginx
│   ├── check_status.sh         # Проверка статуса контейнеров
│   └── README.md
│
├── ssh/                         # Данные SSH сервера (создаётся автоматически)
│   └── config/
│
├── letsencrypt/                 # SSL сертификаты (создаётся автоматически)
│   └── etc/
│
├── ARCHITECTURE.md              # Детальная архитектура
├── SETUP.md                     # Инструкция по установке
└── README.md                    # Основная документация
```

## Основные операции

### 1. Запуск инфраструктуры

```bash
cd /srv/hosting4/infra
sudo ./start.sh
```

Опции:
- `--force` - пересоздать контейнеры
- `--stop` - остановить всё
- `--status` - показать статус
- `--no-sites` - запустить только инфраструктуру без сайтов

### 2. Создание сайта

```bash
cd /srv/hosting4/infra
sudo ./create_site.sh [домен]
```

Скрипт интерактивно запросит:
- Домен (если не указан в аргументе)
- SSH логин (по умолчанию генерируется из домена)
- Пароль SSH (генерация/ручной ввод/без пароля)
- Версию PHP (7.4, 8.0, 8.1, 8.2)
- Email для Let's Encrypt (опционально)

Процесс создания:
1. Создание директорий и копирование конфигов из шаблонов
2. Создание HTTP-only конфига nginx
3. Генерация красивой welcome-страницы
4. Запуск PHP-FPM контейнера
5. Перезапуск nginx
6. Получение SSL сертификата (если DNS настроен)
7. Добавление HTTPS блока в nginx конфиг
8. Создание SSH пользователя

### 3. Удаление сайта

```bash
cd /srv/hosting4/infra
sudo ./delete_site.sh <домен> [--keep-data]
```

Опции:
- `--keep-data` - сохранить файлы сайта (удалить только контейнеры и конфиги)

### 4. Перезапуск nginx

```bash
cd /srv/hosting4/infra
sudo ./restart_nginx.sh
```

### 5. Проверка статуса

```bash
cd /srv/hosting4/infra
sudo ./check_status.sh
```

## Workflow создания сайта

1. **Подготовка DNS**: Настроить A-запись домена на IP сервера
2. **Создание сайта**: Запустить `create_site.sh`
3. **Проверка HTTP**: Убедиться что сайт доступен по HTTP
4. **Получение SSL**: Скрипт автоматически получит сертификат если DNS настроен
5. **Проверка HTTPS**: Убедиться что сайт доступен по HTTPS
6. **Загрузка файлов**: Клиент может загружать файлы через SFTP на порт 2222

## Технические детали

### Nginx конфигурация

Для каждого сайта создаётся конфиг в `config/nginx/conf.d/<домен>.conf`:

**HTTP блок** (создаётся сразу):
- Обслуживает HTTP запросы
- Обрабатывает ACME challenge для Let's Encrypt
- Проксирует PHP запросы в PHP-FPM контейнер

**HTTPS блок** (добавляется после получения сертификата):
- SSL сертификаты из `/etc/letsencrypt/live/<домен>/`
- TLS 1.2 и 1.3
- HTTP/2 поддержка

### PHP-FPM контейнер

Каждый сайт имеет свой контейнер:
- Имя: `php_<домен_без_точек>` (максимум 32 символа)
- Образ: `php:<версия>-fpm`
- Сеть: `web`
- Volumes:
  - `./www` → `/var/www` (файлы сайта)
  - `./logs` → `/var/www/logs` (логи)
  - Конфиги PHP из `config/php-fpm/<домен>/`

### SSH доступ

Клиенты подключаются через SFTP:
```bash
sftp -P 2222 username@server-ip
```

Файлы сайта доступны в `/config/sites/<домен>/www/`

### SSL сертификаты

Certbot получает сертификаты через HTTP-01 challenge:
1. Nginx обслуживает `/.well-known/acme-challenge/` из `/var/www/letsencrypt`
2. Certbot создаёт challenge файл
3. Let's Encrypt проверяет файл по HTTP
4. Сертификат сохраняется в `/etc/letsencrypt/live/<домен>/`

## Безопасность

- Каждый сайт изолирован в своём контейнере
- PHP-FPM работает от пользователя `www-data`
- SSH доступ ограничен chroot окружением
- SSL сертификаты обновляются автоматически
- Логи ошибок PHP не отображаются клиентам

## Мониторинг

### Portainer
Web UI доступен на `http://server-ip:9000` или `https://server-ip:9443`

### Логи

**Nginx логи**:
```bash
docker logs hosting_nginx
```

**PHP-FPM логи сайта**:
```bash
docker logs php_<домен>
# или
cat /srv/hosting4/sites/<домен>/logs/php_errors.log
```

**Логи доступа nginx**:
```bash
cat /srv/hosting4/sites/<домен>/logs/access.log
```

## Troubleshooting

### Nginx не запускается

Проверить логи:
```bash
docker logs hosting_nginx --tail 50
```

Частые причины:
- Порты 80/443 заняты (остановить Apache/nginx на хосте)
- Ошибка в конфиге (проверить синтаксис)
- Несуществующие SSL сертификаты (закомментировать HTTPS блок)

### PHP-FPM контейнер не запускается

```bash
docker logs php_<домен>
```

Проверить:
- Правильность путей в docker-compose.yml
- Наличие конфигов в `config/php-fpm/<домен>/`

### Сайт не доступен

1. Проверить DNS: `dig <домен>`
2. Проверить nginx конфиг: `docker exec hosting_nginx nginx -t`
3. Проверить логи: `docker logs hosting_nginx`
4. Проверить PHP-FPM: `docker ps | grep php_<домен>`

### SSL сертификат не получается

1. Проверить DNS настроен правильно
2. Проверить порт 80 доступен извне
3. Проверить ACME challenge работает: `curl http://<домен>/.well-known/acme-challenge/test`
4. Проверить логи certbot: `docker logs hosting_certbot`

## Масштабирование

Система поддерживает множество сайтов на одном сервере:
- Каждый сайт в отдельном контейнере
- Ресурсы распределяются Docker'ом
- Можно настроить лимиты ресурсов в docker-compose.yml

## Резервное копирование

Важные директории для бэкапа:
- `/srv/hosting4/sites/` - файлы всех сайтов
- `/srv/hosting4/config/` - конфигурации
- `/srv/hosting4/letsencrypt/` - SSL сертификаты

## Обновление

### Обновление PHP версии сайта

1. Остановить контейнер: `cd sites/<домен> && docker compose down`
2. Изменить версию в `docker-compose.yml`
3. Запустить: `docker compose up -d`

### Обновление nginx

1. Изменить версию образа в `infra/docker-compose.yml`
2. Пересоздать: `cd infra && docker compose up -d --force-recreate nginx`

## Дополнительная информация

- [ARCHITECTURE.md](ARCHITECTURE.md) - детальная архитектура
- [SETUP.md](SETUP.md) - пошаговая установка
- [README.md](README.md) - основная документация
- [templates/README.md](templates/README.md) - документация по шаблонам
- [infra/README.md](infra/README.md) - документация по скриптам
