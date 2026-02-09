## Базовая настройка сервера для хостинга

Этот файл описывает, какой софт нужен на чистой ВМ (Ubuntu/Debian) и какие команды выполнить, чтобы подготовить систему к запуску каркаса из `README.md`.

### 1. Обновление системы

```bash
sudo apt update
sudo apt upgrade -y
```

### 2. Установка Docker и Docker Compose (Ubuntu/Debian)

Официальный способ с репозитория Docker:

```bash
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Проверка:

```bash
docker --version
docker compose version
```

### 3. Добавить текущего пользователя в группу docker (не обязательно, но удобно)

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

После этого можно запускать `docker`/`docker compose` без `sudo`.

### 4. Установка дополнительных утилит (опционально)

- **`git`** — нужен для клонирования/обновления репозитория с конфигами:

  ```bash
  sudo apt install -y git
  ```

- **`curl`**, **`htop`**, **`vim`** и т.п. — по вкусу.

### 5. Развёртывание каркаса хостинга

1. Скопировать (или клонировать) директорию проекта, например в `/srv/hosting4`:

   ```bash
   sudo mkdir -p /srv
   sudo chown "$USER":"$USER" /srv
   cd /srv

   # вариант 1: копировать локально
   cp -r /home/mark/Документы/hosting4 ./hosting4

   # вариант 2: если проект уже в git-репозитории
   # git clone <url> hosting4
   ```

2. Перейти в каталог проекта:

   ```bash
   cd /srv/hosting4
   ```

3. Создать директории для Let's Encrypt (если ещё нет):

   ```bash
   mkdir -p letsencrypt/etc letsencrypt/lib letsencrypt/logs letsencrypt/www
   ```

4. Поднять инфраструктуру и тестовый сайт — см. раздел **«Быстрый старт»** в `README.md`.

### 6. Работа с git

#### 6.1. Инициализация и первый пуш (делать один раз на основной машине)

```bash
cd /home/mark/Документы/hosting4   # или путь к проекту

git init
git add .
git commit -m "Initial hosting4 framework"

# привязать к удалённому репозиторию (пример для GitHub по SSH)
git remote add origin git@github.com:<your_login>/hosting4.git
git branch -M main
git push -u origin main
```

После этого проект хранится в удалённом репозитории.

#### 6.2. Клонирование на новую ВМ

```bash
cd /srv
git clone git@github.com:<your_login>/hosting4.git
cd hosting4
```

Дальше следуйте шагам из этого файла (создание директорий, запуск `infra`, и т.д.).

#### 6.3. Обновление конфигов с основной машины

На основной машине (где вы редактируете конфиги):

```bash
cd /home/mark/Документы/hosting4
git status
git add .
git commit -m "Описание изменений"
git push
```

На любой другой ВМ, где развёрнут хостинг:

```bash
cd /srv/hosting4
git pull
```

После `git pull` при необходимости перезапустите контейнеры, чтобы они подхватили новые конфиги, например:

```bash
cd /srv/hosting4/infra
docker compose up -d
docker compose restart nginx ssh
```

### 7. Права на скрипты

Убедитесь, что скрипт создания сайта исполняемый:

```bash
cd /srv/hosting4
chmod +x scripts/create_site.sh
```

### 8. Получение сертификатов Let's Encrypt (webroot, через Docker)

Предполагается, что:

- DNS-домен (например, `example.com`) уже смотрит на IP вашей ВМ;
- порт 80 открыт наружу;
- nginx уже запущен через `infra/docker-compose.yml`;
- в nginx-конфиге домена настроен `location /.well-known/acme-challenge/` на `root /var/www/letsencrypt;` (см. `config/nginx/conf.d/example.com.conf`).

Команды (из каталога `infra`):

```bash
cd /srv/hosting4/infra

# Получить/обновить сертификат для одного домена
docker compose run --rm certbot certonly \
  --webroot -w /var/www/letsencrypt \
  -d example.com \
  --email your-email@example.com \
  --agree-tos \
  --no-eff-email
```

Сертификаты будут сохранены в `../letsencrypt/etc` (на хосте: `letsencrypt/etc`), а nginx уже монтирует их в `/etc/letsencrypt` внутри контейнера.

После успешного получения сертификата:

```bash
cd /srv/hosting4/infra
docker compose restart nginx
```

### 9. Автообновление сертификатов (крон)

Можно периодически вызывать `certbot renew` через cron на хосте:

```bash
crontab -e
```

Добавить строку, например:

```cron
0 3 * * * cd /srv/hosting4/infra && docker compose run --rm certbot renew && docker compose restart nginx
```

Это будет раз в сутки проверять необходимость продления сертификатов и перезапускать nginx при обновлении.

