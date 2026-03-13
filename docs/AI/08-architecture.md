# Архитектура AI-подсистемы Coube

## Общая схема

```
┌─────────────────────────────────────────────────────────────────┐
│                      Клиентские приложения                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  ┌────────┐│
│  │  Frontend     │  │  Mobile      │  │  Admin    │  │Telegram││
│  │  (Vue.js)     │  │  (React      │  │  (Next.js)│  │  Bot   ││
│  │              │  │   Native)    │  │           │  │        ││
│  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘  └───┬────┘│
└─────────┼──────────────────┼───────────────┼─────────────┼──────┘
          │                  │               │             │
          └──────────┬───────┴───────┬───────┘             │
                     │               │                     │
┌────────────────────┴───────────────┴─────────────────────┴──────┐
│                   Coube Backend (Spring Boot)                    │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    AI Gateway Controller                  │   │
│  │  /api/v1/ai/route-guardian/*                              │   │
│  │  /api/v1/ai/eta/*                                         │   │
│  │  /api/v1/ai/matching/*                                    │   │
│  │  /api/v1/ai/forecast/*                                    │   │
│  │  /api/v1/ai/credit-score/*                                │   │
│  │  /api/v1/ai/routes/*                                      │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────┴───────────────────────────────────┐   │
│  │                    AI Service Layer                        │   │
│  │                                                           │   │
│  │  RouteGuardianService ──── GPS Stream Processing          │   │
│  │  EtaPredictionService ──── Model Inference Cache          │   │
│  │  MatchingService ─────── Scoring + Ranking                │   │
│  │  AlarmService ────────── Notification Dispatch            │   │
│  └──────────────────────┬───────────────────────────────────┘   │
│                         │ HTTP / gRPC                            │
└─────────────────────────┼────────────────────────────────────────┘
                          │
┌─────────────────────────┴────────────────────────────────────────┐
│                   AI Microservice (Python)                        │
│                                                                   │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐               │
│  │ Route      │  │ ETA        │  │ Smart        │               │
│  │ Guardian   │  │ Predictor  │  │ Matching     │               │
│  │ Engine     │  │ Model      │  │ Ranker       │               │
│  └────────────┘  └────────────┘  └──────────────┘               │
│  ┌────────────┐  ┌────────────┐  ┌──────────────┐               │
│  │ Demand     │  │ Credit     │  │ Fraud        │               │
│  │ Forecast   │  │ Scoring    │  │ Detection    │               │
│  └────────────┘  └────────────┘  └──────────────┘               │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   ML Pipeline                            │    │
│  │  Feature Store ── Model Registry ── Training Pipeline    │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────┬───────────────────────────────────────┘
                           │
┌──────────────────────────┴───────────────────────────────────────┐
│                        Data Layer                                 │
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐     │
│  │ PostgreSQL   │  │ Redis        │  │ TimescaleDB        │     │
│  │ + PostGIS    │  │ (Cache +     │  │ (Time-series,      │     │
│  │ (Main DB)    │  │  Real-time)  │  │  опционально)      │     │
│  └──────────────┘  └──────────────┘  └────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

## Компоненты

### 1. AI Gateway (Spring Boot)

**Роль:** Прокси между клиентами и AI Microservice. Обеспечивает:
- Аутентификацию и авторизацию (через существующий Keycloak)
- Кеширование результатов (Redis)
- Rate limiting
- Fallback при недоступности AI-сервиса
- Логирование запросов

**Расположение:** Новый модуль `ai` в `coube-backend/src/main/java/kz/coube/backend/ai/`

**Структура модуля:**
```
ai/
├── controller/
│   ├── AiRouteGuardianController.java
│   ├── AiEtaController.java
│   ├── AiMatchingController.java
│   ├── AiForecastController.java
│   ├── AiCreditScoreController.java
│   └── AiRouteIntelligenceController.java
├── service/
│   ├── RouteGuardianService.java      -- GPS stream processing + alarm logic
│   ├── EtaPredictionService.java      -- Cache + delegation to Python
│   ├── MatchingService.java           -- Rule-based scoring (v1) + ML (v2)
│   ├── AlarmService.java              -- Alarm persistence + notification dispatch
│   └── AiClientService.java           -- HTTP client to Python microservice
├── model/
│   ├── Alarm.java
│   ├── EtaPrediction.java
│   ├── MatchingScore.java
│   └── CreditScore.java
├── config/
│   └── AiServiceConfig.java           -- URLs, timeouts, feature flags
└── dto/
    └── ...request/response DTOs
```

### 2. AI Microservice (Python)

**Роль:** ML-модели, обучение, inference.

**Технологии:**
- **Framework:** FastAPI
- **ML:** scikit-learn, XGBoost, LightGBM
- **Time-series:** Prophet, statsmodels
- **Geospatial:** GeoPandas, Shapely
- **Feature Store:** простой PostgreSQL-based (v1), Feast (v2)
- **Model Registry:** MLflow (v2)

**API:**
```
POST /predict/eta          -- Предсказание ETA
POST /predict/matching     -- Скоринг перевозчиков
POST /predict/credit       -- Кредитный скоринг
POST /predict/fraud        -- Обнаружение аномалий
GET  /forecast/demand      -- Прогноз спроса
POST /analyze/route        -- Анализ маршрута
GET  /health               -- Healthcheck
GET  /models/status        -- Статус моделей
```

**Структура:**
```
coube-ai/
├── app/
│   ├── main.py                 -- FastAPI app
│   ├── api/
│   │   ├── eta.py
│   │   ├── matching.py
│   │   ├── credit.py
│   │   ├── fraud.py
│   │   ├── forecast.py
│   │   └── route.py
│   ├── models/
│   │   ├── eta_model.py
│   │   ├── matching_model.py
│   │   ├── credit_model.py
│   │   └── fraud_model.py
│   ├── features/
│   │   ├── feature_store.py
│   │   ├── eta_features.py
│   │   ├── matching_features.py
│   │   └── credit_features.py
│   ├── training/
│   │   ├── train_eta.py
│   │   ├── train_matching.py
│   │   ├── train_credit.py
│   │   └── scheduler.py
│   └── config.py
├── data/
│   └── models/                 -- Сериализованные модели
├── tests/
├── Dockerfile
├── requirements.txt
└── docker-compose.yml
```

### 3. Route Guardian (real-time processing)

**Особенность:** Работает в реальном времени, обрабатывает каждое GPS-обновление.

**Варианты реализации:**

**v1 (простой):** Обработка в Spring Boot.
- `DriverLocationService` при каждом GPS update вызывает `RouteGuardianService`
- Проверки выполняются синхронно
- Алармы сохраняются в БД и отправляются через `NotificationService`

**v2 (масштабируемый):** Event-driven.
- GPS updates публикуются в Kafka/Redis Stream
- AI Microservice подписывается на стрим
- Алармы публикуются обратно
- Spring Boot читает алармы и уведомляет пользователей

**Рекомендация:** Начать с v1, перейти на v2 при >1000 одновременных перевозок.

### 4. Data Layer

**PostgreSQL (основная БД):**
- Все существующие данные
- Новые таблицы: `gis.transportation_alarm`, `ai.prediction_log`, `ai.model_metrics`

**Redis:**
- Кеш ETA предсказаний (TTL 5 мин)
- Кеш matching скоров (TTL 1 час)
- Кеш кредитных скоров (TTL 24 часа)
- Real-time данные для Route Guardian (последние N точек водителя)
- Оптимальные маршруты (кеш Yandex Router)

**TimescaleDB (опционально, v2):**
- Для больших объёмов GPS-данных (>10 млн записей/месяц)
- Автоматическое сжатие старых данных
- Быстрые time-series запросы

## Новые таблицы БД

```sql
-- Алармы Route Guardian
CREATE TABLE gis.transportation_alarm (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transportation_id UUID NOT NULL,
    alarm_type VARCHAR(50) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    location GEOGRAPHY(POINT, 4326),
    description TEXT,
    metadata JSONB,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP,
    resolved_by UUID,
    resolution_note TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Лог предсказаний (для мониторинга качества моделей)
CREATE TABLE ai.prediction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name VARCHAR(50) NOT NULL,
    model_version VARCHAR(20) NOT NULL,
    input_hash VARCHAR(64),
    prediction JSONB NOT NULL,
    actual_value JSONB,
    latency_ms INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Метрики моделей
CREATE TABLE ai.model_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name VARCHAR(50) NOT NULL,
    model_version VARCHAR(20) NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    metric_value DOUBLE PRECISION NOT NULL,
    dataset_size INTEGER,
    calculated_at TIMESTAMP DEFAULT NOW()
);

-- Кредитные скоры (кеш)
CREATE TABLE ai.credit_score_cache (
    organization_id UUID PRIMARY KEY,
    credit_score INTEGER NOT NULL,
    risk_category VARCHAR(20) NOT NULL,
    recommended_limit BIGINT,
    confidence DOUBLE PRECISION,
    factors JSONB,
    model_version VARCHAR(20),
    calculated_at TIMESTAMP DEFAULT NOW(),
    valid_until TIMESTAMP
);
```

## Этапы внедрения

### Этап 1 (MVP, 4-6 недель)
- Route Guardian (rule-based в Spring Boot)
- Базовый ETA (расстояние/средняя скорость + корректировки)
- Таблицы БД для алармов
- Push-уведомления при алармах
- UI: панель алармов в Frontend

### Этап 2 (ML v1, 6-8 недель)
- Python AI Microservice (FastAPI)
- ML-модель ETA (XGBoost на исторических данных)
- Smart Matching (rule-based скоринг)
- Credit Scoring (XGBoost)
- UI: ETA в карточке перевозки, рекомендации перевозчиков

### Этап 3 (Advanced, 8-12 недель)
- Demand Forecasting (Prophet)
- Route Intelligence (аналитика маршрутов)
- Fraud Detection (Isolation Forest)
- ML-based matching (Learning-to-Rank)
- UI: дашборды аналитики, прогнозы

### Этап 4 (AI Platform, 12+ недель)
- AI-чатбот (LLM + RAG)
- Голосовой помощник
- Document AI (OCR)
- Predictive Maintenance
- MLOps: автоматическое переобучение, A/B тесты

## Мониторинг AI-системы

### Метрики для отслеживания
- **Latency:** p50, p95, p99 времени ответа каждого AI-endpoint
- **Accuracy:** MAPE для ETA, AUC-ROC для credit scoring, precision/recall для fraud
- **Drift:** Изменение распределения входных данных vs. обучающих
- **Usage:** Кол-во вызовов, adoption rate рекомендаций

### Дашборд мониторинга (Admin)
- Статус моделей (версия, дата обучения, метрики)
- Графики accuracy за время
- Алерты при деградации качества
- Feature importance для каждой модели

## Требования к инфраструктуре

### Минимальные (MVP)
- Дополнительная нагрузка на Spring Boot: +10-15% CPU
- Redis: +512 MB RAM
- PostgreSQL: +2-5 GB для алармов и логов

### Для Python Microservice (Этап 2+)
- 1 instance: 2 CPU, 4 GB RAM
- GPU не требуется (табличные модели, не deep learning)
- Хранение моделей: ~100 MB
- Docker deployment (рядом с основным бэкендом)

### Для масштабирования (Этап 4+)
- 2-3 instances Python Microservice (за балансером)
- Kafka/Redis Streams для event-driven обработки
- TimescaleDB для time-series данных
- MLflow для model registry
