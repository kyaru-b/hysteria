#!/bin/bash

# ===========================================
# 3X-UI + Nginx Proxy Setup Script
# ===========================================

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    3X-UI + Nginx Setup                       ║"
echo "║              Автоматическая установка панели                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Запрос данных
echo -e "${YELLOW}Введите ваш домен (например: panel.example.com):${NC}"
read -r DOMAIN

echo -e "${YELLOW}Введите email для SSL сертификата:${NC}"
read -r EMAIL

echo -e "${YELLOW}Введите желаемый логин для 3x-ui (по умолчанию: admin):${NC}"
read -r PANEL_USER
PANEL_USER=${PANEL_USER:-admin}

echo -e "${YELLOW}Введите желаемый пароль для 3x-ui (по умолчанию: admin):${NC}"
read -r PANEL_PASS
PANEL_PASS=${PANEL_PASS:-admin}

echo -e "${YELLOW}Введите порт панели (по умолчанию: 2053):${NC}"
read -r PANEL_PORT
PANEL_PORT=${PANEL_PORT:-2053}

# Проверка домена
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Ошибка: домен не указан!${NC}"
    exit 1
fi

if [ -z "$EMAIL" ]; then
    echo -e "${RED}Ошибка: email не указан!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Конфигурация:${NC}"
echo -e "  Домен: ${BLUE}$DOMAIN${NC}"
echo -e "  Email: ${BLUE}$EMAIL${NC}"
echo -e "  Логин: ${BLUE}$PANEL_USER${NC}"
echo -e "  Порт:  ${BLUE}$PANEL_PORT${NC}"
echo ""

# Создание директорий
echo -e "${YELLOW}[1/7] Создание директорий...${NC}"
mkdir -p nginx/conf.d
mkdir -p 3x-ui/db
mkdir -p 3x-ui/cert
mkdir -p certbot/www
mkdir -p certbot/conf

# Обновление конфигурации nginx
echo -e "${YELLOW}[2/7] Настройка Nginx...${NC}"

# Создаём временную конфигурацию без SSL
cat > nginx/conf.d/default.conf << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        proxy_pass http://3x-ui:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Обновляем docker-compose.yml с правильным портом
sed -i "s/2053:2053/${PANEL_PORT}:${PANEL_PORT}/g" docker-compose.yml

# Запуск контейнеров
echo -e "${YELLOW}[3/7] Запуск Docker контейнеров...${NC}"
docker-compose up -d nginx 3x-ui

# Ждём запуска
echo -e "${YELLOW}[4/7] Ожидание запуска сервисов...${NC}"
sleep 10

# Получение SSL сертификата
echo -e "${YELLOW}[5/7] Получение SSL сертификата...${NC}"
docker-compose run --rm certbot certonly --webroot \
    --webroot-path=/var/www/certbot \
    --email ${EMAIL} \
    --agree-tos \
    --no-eff-email \
    -d ${DOMAIN}

# Создаём полную конфигурацию с SSL
echo -e "${YELLOW}[6/7] Настройка SSL в Nginx...${NC}"
cat > nginx/conf.d/default.conf << EOF
# HTTP - редирект на HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        proxy_pass http://3x-ui:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }

    location /ws {
        proxy_pass http://3x-ui:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400;
    }

    location ^~ /xray {
        proxy_pass http://3x-ui:${PANEL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Перезапуск nginx
echo -e "${YELLOW}[7/7] Перезапуск Nginx...${NC}"
docker-compose restart nginx
docker-compose up -d

# Сохранение информации
cat > credentials.txt << EOF
===========================================
3X-UI Panel Credentials
===========================================
URL: https://${DOMAIN}
Логин: ${PANEL_USER}
Пароль: ${PANEL_PASS}
Порт панели: ${PANEL_PORT}

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
- Обновление: docker-compose pull && docker-compose up -d
===========================================
EOF

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Установка завершена!                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Панель доступна по адресу: https://${DOMAIN}${NC}"
echo -e "${BLUE}Логин: ${PANEL_USER}${NC}"
echo -e "${BLUE}Пароль: ${PANEL_PASS}${NC}"
echo ""
echo -e "${YELLOW}Данные сохранены в файл: credentials.txt${NC}"
echo ""
echo -e "${YELLOW}ВАЖНО: После первого входа обязательно смените пароль!${NC}"
