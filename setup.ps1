# ===========================================
# 3X-UI + Nginx Proxy Setup Script (Windows PowerShell)
# ===========================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Blue
Write-Host "║                    3X-UI + Nginx Setup                       ║" -ForegroundColor Blue
Write-Host "║              Автоматическая установка панели                 ║" -ForegroundColor Blue
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Blue
Write-Host ""

# Запрос данных
Write-Host "Введите ваш домен (например: panel.example.com):" -ForegroundColor Yellow
$DOMAIN = Read-Host

Write-Host "Введите email для SSL сертификата:" -ForegroundColor Yellow
$EMAIL = Read-Host

Write-Host "Введите желаемый логин для 3x-ui (по умолчанию: admin):" -ForegroundColor Yellow
$PANEL_USER = Read-Host
if ([string]::IsNullOrEmpty($PANEL_USER)) { $PANEL_USER = "admin" }

Write-Host "Введите желаемый пароль для 3x-ui (по умолчанию: admin):" -ForegroundColor Yellow
$PANEL_PASS = Read-Host
if ([string]::IsNullOrEmpty($PANEL_PASS)) { $PANEL_PASS = "admin" }

Write-Host "Введите порт панели (по умолчанию: 2053):" -ForegroundColor Yellow
$PANEL_PORT = Read-Host
if ([string]::IsNullOrEmpty($PANEL_PORT)) { $PANEL_PORT = "2053" }

# Проверка
if ([string]::IsNullOrEmpty($DOMAIN)) {
    Write-Host "Ошибка: домен не указан!" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrEmpty($EMAIL)) {
    Write-Host "Ошибка: email не указан!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Конфигурация:" -ForegroundColor Green
Write-Host "  Домен: $DOMAIN" -ForegroundColor Cyan
Write-Host "  Email: $EMAIL" -ForegroundColor Cyan
Write-Host "  Логин: $PANEL_USER" -ForegroundColor Cyan
Write-Host "  Порт:  $PANEL_PORT" -ForegroundColor Cyan
Write-Host ""

# Создание директорий
Write-Host "[1/7] Создание директорий..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "nginx\conf.d" | Out-Null
New-Item -ItemType Directory -Force -Path "3x-ui\db" | Out-Null
New-Item -ItemType Directory -Force -Path "3x-ui\cert" | Out-Null
New-Item -ItemType Directory -Force -Path "certbot\www" | Out-Null
New-Item -ItemType Directory -Force -Path "certbot\conf" | Out-Null

# Настройка Nginx
Write-Host "[2/7] Настройка Nginx..." -ForegroundColor Yellow

$nginxConfig = @"
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://3x-ui:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
    }
}
"@

$nginxConfig | Out-File -FilePath "nginx\conf.d\default.conf" -Encoding UTF8

# Обновляем docker-compose
$composeContent = Get-Content "docker-compose.yml" -Raw
$composeContent = $composeContent -replace "2053:2053", "${PANEL_PORT}:${PANEL_PORT}"
$composeContent | Out-File -FilePath "docker-compose.yml" -Encoding UTF8

# Запуск контейнеров
Write-Host "[3/7] Запуск Docker контейнеров..." -ForegroundColor Yellow
docker-compose up -d nginx 3x-ui

# Ожидание
Write-Host "[4/7] Ожидание запуска сервисов..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# SSL сертификат
Write-Host "[5/7] Получение SSL сертификата..." -ForegroundColor Yellow
docker-compose run --rm certbot certonly --webroot `
    --webroot-path=/var/www/certbot `
    --email $EMAIL `
    --agree-tos `
    --no-eff-email `
    -d $DOMAIN

# Полная конфигурация с SSL
Write-Host "[6/7] Настройка SSL в Nginx..." -ForegroundColor Yellow

$nginxSSLConfig = @"
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://`$host`$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        proxy_pass http://3x-ui:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto `$scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location /ws {
        proxy_pass http://3x-ui:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location ^~ /xray {
        proxy_pass http://3x-ui:$PANEL_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade `$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
        proxy_set_header X-Forwarded-For `$proxy_add_x_forwarded_for;
    }
}
"@

$nginxSSLConfig | Out-File -FilePath "nginx\conf.d\default.conf" -Encoding UTF8

# Перезапуск
Write-Host "[7/7] Перезапуск Nginx..." -ForegroundColor Yellow
docker-compose restart nginx
docker-compose up -d

# Сохранение данных
$credentials = @"
===========================================
3X-UI Panel Credentials
===========================================
URL: https://$DOMAIN
Логин: $PANEL_USER
Пароль: $PANEL_PASS
Порт панели: $PANEL_PORT

Доступные порты для Xray (TCP):
- 10000-10050
- 20000-20050
- 30000-30050
- 40000-40050
- 8443, 8080, 9443
- 2083, 2087, 2096

Доступные порты для Hysteria 2 (UDP):
- 50000-50050
- 51000-51050
- 52000-52050
- 443, 8443, 4433, 5443, 6443, 7443
- 10080, 10443

Управление:
- Запуск: docker-compose up -d
- Остановка: docker-compose down
- Логи: docker-compose logs -f
- Обновление: docker-compose pull; docker-compose up -d
===========================================
"@

$credentials | Out-File -FilePath "credentials.txt" -Encoding UTF8

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    Установка завершена!                      ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Панель доступна по адресу: https://$DOMAIN" -ForegroundColor Cyan
Write-Host "Логин: $PANEL_USER" -ForegroundColor Cyan
Write-Host "Пароль: $PANEL_PASS" -ForegroundColor Cyan
Write-Host ""
Write-Host "Данные сохранены в файл: credentials.txt" -ForegroundColor Yellow
Write-Host ""
Write-Host "ВАЖНО: После первого входа обязательно смените пароль!" -ForegroundColor Yellow
