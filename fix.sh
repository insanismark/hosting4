#!/bin/bash
set -e

echo "=== Fixing hosting infrastructure ==="

# 1. Fix templates/php-fpm/www.conf (template for new sites)
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

; Логирование - используем относительный путь с доменом
access.log = /var/www/${DOMAIN}/logs/php-fpm-access.log
slowlog = /var/www/${DOMAIN}/logs/php-fpm-slow.log
request_slowlog_timeout = 10s

; Переменные окружения
clear_env = no

; Безопасность
php_admin_value[error_log] = /var/www/${DOMAIN}/logs/php_errors.log
php_admin_flag[log_errors] = on
EOF
echo "✓ Fixed templates/php-fpm/www.conf"

# 2. Fix config/php-fpm/blablatest3.tagan.ru/www.conf (existing site)
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

# 3. Fix config/php-fpm/blablatest2.tagan.ru/www.conf (existing site)
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

# 4. Check and create logs directories for sites if they don't exist
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
        # Set proper permissions
        chmod 755 "$logs_dir"
    fi
done

# 5. Recreate PHP containers to apply config changes
echo ""
echo "=== Recreating PHP containers ==="
for site_dir in sites/*; do
    if [[ -f "$site_dir/docker-compose.yml" ]]; then
        site_name=$(basename "$site_dir")
        echo "  Recreating container for: $site_name"
        cd "$site_dir" && docker compose down && docker compose up -d
    fi
done
echo "✓ PHP containers recreated"

# 6. Reload nginx to ensure configuration is up to date
echo ""
echo "=== Reloading nginx ==="
sudo docker exec hosting_nginx nginx -s reload
echo "✓ Nginx reloaded"

# 7. Test sites
echo ""
echo "=== Testing sites ==="
for site_dir in sites/*; do
    if [[ -d "$site_dir" ]]; then
        site_name=$(basename "$site_dir")
        echo "  Testing: $site_name"
        curl -s "http://$site_name/" | head -20 || echo "  Warning: Failed to connect to $site_name"
    fi
done

echo ""
echo "=== Done ==="
