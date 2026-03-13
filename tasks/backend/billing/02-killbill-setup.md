# 02. Установка и настройка Kill Bill

## Обзор

Документ описывает пошаговую установку Kill Bill в Docker для интеграции с платформой Coube.

**Kill Bill** — open-source биллинговая система на Java с поддержкой подписок, инвойсов, платежей и плагинов.

---

## Архитектура развёртывания

```
┌────────────────────────────────────────────────────────┐
│                    Docker Compose                       │
│                                                          │
│  ┌─────────────┐   ┌──────────────┐   ┌─────────────┐  │
│  │   Coube     │   │  Kill Bill   │   │  Kill Bill  │  │
│  │  Platform   │   │    Server    │   │   Admin UI  │  │
│  │ (Spring)    │   │  (Port 8080) │   │ (Port 3000) │  │
│  └─────────────┘   └──────────────┘   └─────────────┘  │
│         │                  │                   │         │
│         │                  │                   │         │
│  ┌──────▼──────────┐  ┌───▼───────────────────▼──────┐ │
│  │  PostgreSQL     │  │   PostgreSQL (Kill Bill DB)  │ │
│  │  (Platform DB)  │  │      (Port 5432)             │ │
│  └─────────────────┘  └──────────────────────────────┘ │
│                                                          │
│  ┌─────────────────────────────────────────────────┐    │
│  │               MinIO (File Storage)               │    │
│  │                 (Port 9000)                      │    │
│  └─────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────┘
```

---

## Предварительные требования

### Системные требования
- **Docker**: 20.10+
- **Docker Compose**: 2.0+
- **RAM**: минимум 4GB (рекомендуется 8GB)
- **Disk**: минимум 10GB свободного места

### Проверка установки
```bash
docker --version
# Docker version 20.10.x

docker-compose --version
# Docker Compose version 2.x.x
```

---

## Шаг 1: Создание структуры проекта

### 1.1. Создание директории для Kill Bill

```bash
cd /Users/ali/www/coube
mkdir -p killbill-docker
cd killbill-docker
```

### 1.2. Структура файлов

```
killbill-docker/
├── docker-compose.yml          # Основная конфигурация
├── .env                         # Переменные окружения
├── postgres-init/               # Скрипты инициализации БД
│   └── init-killbill-db.sql
├── killbill-config/             # Конфигурация Kill Bill
│   └── killbill.properties
└── README.md                    # Инструкции
```

---

## Шаг 2: Файл `docker-compose.yml`

```yaml
version: '3.8'

services:
  # PostgreSQL для Kill Bill
  killbill-db:
    image: postgres:14-alpine
    container_name: killbill-postgres
    environment:
      POSTGRES_USER: ${KB_DB_USER:-killbill}
      POSTGRES_PASSWORD: ${KB_DB_PASSWORD:-killbill}
      POSTGRES_DB: ${KB_DB_NAME:-killbill}
    volumes:
      - killbill-db-data:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d
    ports:
      - "5433:5432"  # Не конфликтует с основной БД Coube (5432)
    networks:
      - killbill-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U killbill"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Kill Bill Server
  killbill:
    image: killbill/killbill:0.24.11  # Последняя стабильная версия
    container_name: killbill-server
    environment:
      # Database
      KILLBILL_DB_URL: jdbc:postgresql://killbill-db:5432/killbill
      KILLBILL_DB_USER: ${KB_DB_USER:-killbill}
      KILLBILL_DB_PASSWORD: ${KB_DB_PASSWORD:-killbill}
      
      # Admin credentials
      KILLBILL_ADMIN_USER: ${KB_ADMIN_USER:-admin}
      KILLBILL_ADMIN_PASSWORD: ${KB_ADMIN_PASSWORD:-password}
      
      # Configuration
      KILLBILL_SERVER_REGION: kz-almaty
      KILLBILL_CURRENCY: KZT
      KILLBILL_LOCALE: ru_RU
      
      # JVM Options
      KILLBILL_JVM_OPTS: -Xmx2G -Xms512M
      
      # Plugins
      KILLBILL_PLUGIN_DIR: /var/tmp/bundles
    ports:
      - "8080:8080"  # API
      - "8443:8443"  # HTTPS (если настроен)
    volumes:
      - killbill-data:/var/tmp/bundles
      - ./killbill-config:/etc/killbill
    networks:
      - killbill-network
    depends_on:
      killbill-db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # Kill Bill Admin UI (Kaui)
  kaui:
    image: killbill/kaui:2.1.0
    container_name: killbill-kaui
    environment:
      KAUI_CONFIG_DAO_URL: jdbc:postgresql://killbill-db:5432/kaui
      KAUI_CONFIG_DAO_USER: ${KB_DB_USER:-killbill}
      KAUI_CONFIG_DAO_PASSWORD: ${KB_DB_PASSWORD:-killbill}
      
      KAUI_KILLBILL_URL: http://killbill:8080
      KAUI_KILLBILL_API_KEY: ${KB_API_KEY:-bob}
      KAUI_KILLBILL_API_SECRET: ${KB_API_SECRET:-lazar}
      
      KAUI_ROOT_USERNAME: ${KAUI_ADMIN_USER:-admin}
      KAUI_ROOT_PASSWORD: ${KAUI_ADMIN_PASSWORD:-password}
    ports:
      - "3000:3000"
    networks:
      - killbill-network
    depends_on:
      - killbill
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  killbill-db-data:
    driver: local
  killbill-data:
    driver: local

networks:
  killbill-network:
    driver: bridge
```

---

## Шаг 3: Файл `.env`

```bash
# Database
KB_DB_USER=killbill
KB_DB_PASSWORD=Str0ngP@ssw0rd!KB
KB_DB_NAME=killbill

# Kill Bill Admin
KB_ADMIN_USER=admin
KB_ADMIN_PASSWORD=Adm1nP@ss!KB

# API Keys (для интеграции с Coube)
KB_API_KEY=coube_api_key
KB_API_SECRET=coube_api_secret_12345

# Kaui Admin
KAUI_ADMIN_USER=admin
KAUI_ADMIN_PASSWORD=Kaui@dmin2025
```

⚠️ **Важно**: Добавьте `.env` в `.gitignore`!

---

## Шаг 4: Инициализация базы данных

### Файл `postgres-init/init-killbill-db.sql`

```sql
-- Создание дополнительной БД для Kaui (админка)
CREATE DATABASE kaui;

-- Расширения для Kill Bill
\c killbill;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c kaui;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

---

## Шаг 5: Конфигурация Kill Bill

### Файл `killbill-config/killbill.properties`

```properties
# Основные настройки
org.killbill.server.region=kz-almaty
org.killbill.catalog.currency=KZT
org.killbill.locale=ru_RU

# Database
org.killbill.dao.url=jdbc:postgresql://killbill-db:5432/killbill
org.killbill.dao.user=killbill
org.killbill.dao.password=Str0ngP@ssw0rd!KB

# Cache (Redis опционально)
org.killbill.cache.config.redis=false

# Notifications
org.killbill.notificationq.main.sleep=1000

# Payment
org.killbill.payment.retry.days=7

# Invoice
org.killbill.invoice.dryRunNotificationSchedule=0 0 * * *
org.killbill.invoice.maxDailyNumberOfItemsSafetyBound=50000

# Security
org.killbill.security.shiroResourcePath=/etc/killbill/shiro.ini
```

---

## Шаг 6: Запуск Kill Bill

### 6.1. Запуск контейнеров

```bash
cd /Users/ali/www/coube/killbill-docker

# Первый запуск (скачивание образов)
docker-compose up -d

# Проверка логов
docker-compose logs -f killbill
```

### 6.2. Ожидание инициализации

Kill Bill создаёт таблицы при первом запуске — это занимает ~2-3 минуты.

**Проверка статуса**:
```bash
# Проверка healthcheck
docker-compose ps

# Должно быть:
# killbill-postgres   Up (healthy)
# killbill-server     Up (healthy)
# killbill-kaui       Up (healthy)
```

### 6.3. Проверка доступности

**Kill Bill API**:
```bash
curl http://localhost:8080/healthcheck

# Ответ:
# {"status":"UP"}
```

**Admin UI (Kaui)**:
```bash
open http://localhost:3000
# Логин: admin
# Пароль: password (из .env: KAUI_ADMIN_PASSWORD)
```

---

## Шаг 7: Первичная настройка через Kaui

### 7.1. Вход в админку

1. Открыть: http://localhost:3000
2. Логин: `admin`
3. Пароль: `password` (или из `.env`)

### 7.2. Создание тенанта

**Tenant** = изолированное пространство для одного клиента. Для Coube создаём один тенант.

1. **Admin** → **Tenants** → **Create New Tenant**
2. Заполнить:
   - **Name**: `coube`
   - **API Key**: `coube_api_key` (из `.env`)
   - **API Secret**: `coube_api_secret_12345`
3. **Create**

### 7.3. Загрузка каталога тарифов

**Каталог** = описание тарифных планов в XML.

#### Файл `catalog-coube.xml`

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<catalog xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="CatalogSchema.xsd">
    
    <effectiveDate>2025-01-01T00:00:00+00:00</effectiveDate>
    <catalogName>Coube Billing</catalogName>
    
    <!-- Валюты -->
    <currencies>
        <currency>KZT</currency>
        <currency>USD</currency>
    </currencies>
    
    <!-- Единицы времени -->
    <units>
        <unit name="month"/>
    </units>
    
    <!-- Продукты -->
    <products>
        <!-- Подписка для Заказчиков -->
        <product name="customer-subscription">
            <category>BASE</category>
            <limits/>
        </product>
    </products>
    
    <!-- Тарифные планы -->
    <plans>
        <!-- Стандартная подписка (ежемесячная) -->
        <plan name="standard-monthly">
            <product>customer-subscription</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases/>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>MONTHLY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>KZT</currency>
                            <value>10000.00</value>
                        </price>
                    </recurringPrice>
                </recurring>
            </finalPhase>
        </plan>
        
        <!-- Пробный период (trial) -->
        <plan name="trial-monthly">
            <product>customer-subscription</product>
            <recurringBillingMode>IN_ADVANCE</recurringBillingMode>
            <initialPhases>
                <phase type="TRIAL">
                    <duration>
                        <unit>MONTHS</unit>
                        <number>1</number>
                    </duration>
                    <fixed>
                        <fixedPrice>
                            <price>
                                <currency>KZT</currency>
                                <value>0.00</value>
                            </price>
                        </fixedPrice>
                    </fixed>
                </phase>
            </initialPhases>
            <finalPhase type="EVERGREEN">
                <duration>
                    <unit>UNLIMITED</unit>
                </duration>
                <recurring>
                    <billingPeriod>MONTHLY</billingPeriod>
                    <recurringPrice>
                        <price>
                            <currency>KZT</currency>
                            <value>10000.00</value>
                        </price>
                    </recurringPrice>
                </recurring>
            </finalPhase>
        </plan>
    </plans>
    
    <!-- Правила тарифов -->
    <priceLists>
        <defaultPriceList name="DEFAULT">
            <plans>
                <plan>standard-monthly</plan>
                <plan>trial-monthly</plan>
            </plans>
        </defaultPriceList>
    </priceLists>
</catalog>
```

#### Загрузка каталога через Kaui

1. **Admin** → **Tenant Configuration**
2. **Catalog** → **Upload Catalog**
3. Выбрать файл `catalog-coube.xml`
4. **Upload**

---

## Шаг 8: Тестирование через API

### 8.1. Создание тестового аккаунта

```bash
curl -X POST http://localhost:8080/1.0/kb/accounts \
  -H "X-Killbill-ApiKey: coube_api_key" \
  -H "X-Killbill-ApiSecret: coube_api_secret_12345" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "externalKey": "test_org_001",
    "name": "ООО ТЕСТ-1",
    "email": "test@example.kz",
    "currency": "KZT"
  }'
```

**Ответ**:
```json
{
  "accountId": "a3f1b5c9-8d2e-4f7a-9c1d-5e6f7a8b9c0d",
  "externalKey": "test_org_001",
  "name": "ООО ТЕСТ-1",
  "email": "test@example.kz",
  "currency": "KZT",
  ...
}
```

### 8.2. Создание подписки

```bash
ACCOUNT_ID="a3f1b5c9-8d2e-4f7a-9c1d-5e6f7a8b9c0d"

curl -X POST "http://localhost:8080/1.0/kb/subscriptions" \
  -H "X-Killbill-ApiKey: coube_api_key" \
  -H "X-Killbill-ApiSecret: coube_api_secret_12345" \
  -H "X-Killbill-CreatedBy: admin" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d "{
    \"accountId\": \"$ACCOUNT_ID\",
    \"planName\": \"trial-monthly\"
  }"
```

**Ответ**: Подписка создана, первый инвойс на 0₸ (trial).

### 8.3. Получение инвойсов

```bash
curl -X GET "http://localhost:8080/1.0/kb/accounts/$ACCOUNT_ID/invoices" \
  -H "X-Killbill-ApiKey: coube_api_key" \
  -H "X-Killbill-ApiSecret: coube_api_secret_12345" \
  -u admin:password
```

---

## Шаг 9: Интеграция с Coube Platform

### 9.1. Добавление зависимости в `build.gradle.kts`

```kotlin
dependencies {
    // Kill Bill Client Library
    implementation("org.kill-bill.billing:killbill-client-java:2.1.0")
    
    // HTTP Client (если нужен кастомный)
    implementation("org.springframework.boot:spring-boot-starter-webflux")
}
```

### 9.2. Конфигурация в `application.yml`

```yaml
killbill:
  server:
    url: http://localhost:8080
    api-key: coube_api_key
    api-secret: coube_api_secret_12345
    username: admin
    password: password
  tenant:
    api-key: coube_api_key
    api-secret: coube_api_secret_12345
```

### 9.3. Spring Configuration Bean

```java
@Configuration
public class KillBillConfig {
    
    @Value("${killbill.server.url}")
    private String killbillUrl;
    
    @Value("${killbill.server.api-key}")
    private String apiKey;
    
    @Value("${killbill.server.api-secret}")
    private String apiSecret;
    
    @Value("${killbill.server.username}")
    private String username;
    
    @Value("${killbill.server.password}")
    private String password;
    
    @Bean
    public KillBillHttpClient killBillHttpClient() {
        return new KillBillHttpClient(
            killbillUrl,
            username,
            password,
            apiKey,
            apiSecret
        );
    }
}
```

---

## Шаг 10: Мониторинг и логи

### 10.1. Просмотр логов

```bash
# Логи Kill Bill Server
docker-compose logs -f killbill

# Логи PostgreSQL
docker-compose logs -f killbill-db

# Логи Kaui
docker-compose logs -f kaui
```

### 10.2. Healthcheck endpoints

| Сервис | Endpoint | Порт |
|--------|----------|------|
| Kill Bill API | http://localhost:8080/healthcheck | 8080 |
| Kaui Admin | http://localhost:3000/ | 3000 |
| PostgreSQL | `psql -h localhost -p 5433 -U killbill` | 5433 |

---

## Шаг 11: Резервное копирование

### Скрипт бэкапа БД Kill Bill

```bash
#!/bin/bash
# backup-killbill-db.sh

BACKUP_DIR="/Users/ali/www/coube/killbill-docker/backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/killbill_backup_$DATE.sql.gz"

mkdir -p $BACKUP_DIR

docker exec killbill-postgres pg_dump -U killbill killbill | gzip > $BACKUP_FILE

echo "Backup created: $BACKUP_FILE"

# Удаление старых бэкапов (>7 дней)
find $BACKUP_DIR -name "killbill_backup_*.sql.gz" -mtime +7 -delete
```

**Cron job** (ежедневно в 2:00):
```bash
0 2 * * * /Users/ali/www/coube/killbill-docker/backup-killbill-db.sh
```

---

## Troubleshooting

### Проблема: Kill Bill не запускается

**Решение**:
```bash
# Проверить логи
docker-compose logs killbill

# Если ошибка подключения к БД, проверить healthcheck БД
docker-compose ps killbill-db

# Перезапуск с очисткой
docker-compose down -v
docker-compose up -d
```

### Проблема: Каталог не загружается

**Решение**: Проверить XML на валидность:
```bash
xmllint --noout --schema CatalogSchema.xsd catalog-coube.xml
```

### Проблема: Недостаточно памяти

**Решение**: Увеличить лимиты в `docker-compose.yml`:
```yaml
killbill:
  deploy:
    resources:
      limits:
        memory: 4G
```

---

## Следующие шаги

1. ✅ Kill Bill установлен и работает
2. ✅ Каталог тарифов загружен
3. → Перейти к `03-integration-layer.md` для реализации слоя интеграции

---

**Документ подготовлен**: 2025-01-XX  
**Версия**: 1.0  
**Проверено**: DevOps + Backend Team
