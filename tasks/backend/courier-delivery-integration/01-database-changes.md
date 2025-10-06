# 01. Изменения в структуре базы данных

## Обзор

Документ описывает все изменения в БД для поддержки курьерской доставки.

---

## 1. Схема `user` - Роль водитель-курьер

### 1.1. Таблица `users.employees_roles`

**Добавить новое значение в enum роли**:

```sql
-- Новое значение роли
ALTER TYPE employee_role ADD VALUE IF NOT EXISTS 'COURIER_DRIVER';
```

**Описание роли**:
- `COURIER_DRIVER` - Водитель-курьер (выполняет курьерские доставки)

### 1.2. Таблица `users.employee`

**Новые поля для курьеров**:

```sql
ALTER TABLE users.employee
ADD COLUMN IF NOT EXISTS primary_pickup_point_id TEXT, -- Основной ПВЗ курьера
ADD COLUMN IF NOT EXISTS integration_data JSONB,        -- Данные интеграции
ADD COLUMN IF NOT EXISTS current_status TEXT DEFAULT 'free'; -- Статус курьера

-- Комментарии
COMMENT ON COLUMN users.employee.primary_pickup_point_id IS 'ID основного ПВЗ, который контролирует данного курьера';
COMMENT ON COLUMN users.employee.integration_data IS 'Массив объектов интеграции: [{system: "TEEZ_PVZ", external_id: "123"}]';
COMMENT ON COLUMN users.employee.current_status IS 'Статус курьера: free, in_route, unavailable';
```

**Enum для статуса курьера**:

```sql
CREATE TYPE courier_status_enum AS ENUM (
    'free',          -- Свободен
    'in_route',      -- В поездке
    'unavailable'    -- Недоступен по другим причинам
);

ALTER TABLE users.employee
ALTER COLUMN current_status TYPE courier_status_enum USING current_status::courier_status_enum;
```

---

## 2. Схема `applications` - Курьерские заявки

### 2.1. Таблица `applications.transportation`

**Добавить новый тип перевозки**:

```sql
-- Новое значение transportation_type
-- Текущие: 'FLT' (полная грузовая перевозка)
-- Добавляем: 'COURIER_DELIVERY' (курьерская доставка)

ALTER TABLE applications.transportation
ADD COLUMN IF NOT EXISTS source_system TEXT,              -- Внешняя система
ADD COLUMN IF NOT EXISTS external_waybill_id TEXT,        -- ID маршрутного листа во внешней системе
ADD COLUMN IF NOT EXISTS delivery_type TEXT,              -- courier, marketplacedelivery
ADD COLUMN IF NOT EXISTS responsible_courier_warehouse_id TEXT, -- Ответственный склад
ADD COLUMN IF NOT EXISTS target_delivery_day DATE,        -- Целевая дата доставки
ADD COLUMN IF NOT EXISTS validation_status TEXT DEFAULT 'imported_draft'; -- Статус валидации

-- Индексы
CREATE INDEX IF NOT EXISTS idx_transportation_external_waybill 
ON applications.transportation(external_waybill_id, source_system) 
WHERE transportation_type = 'COURIER_DELIVERY';

-- Комментарии
COMMENT ON COLUMN applications.transportation.source_system IS 'Внешняя система-источник: TEEZ_PVZ';
COMMENT ON COLUMN applications.transportation.external_waybill_id IS 'Идентификатор маршрутного листа во внешней системе';
COMMENT ON COLUMN applications.transportation.delivery_type IS 'Тип курьерской доставки: courier, marketplacedelivery';
COMMENT ON COLUMN applications.transportation.validation_status IS 'Статус валидации: imported_draft, validated, assigned, in_route, completed, closed';
```

### 2.2. Новая таблица `applications.courier_route_point`

**Точки маршрута курьерской доставки**:

```sql
CREATE TABLE IF NOT EXISTS applications.courier_route_point (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id) ON DELETE CASCADE,
    
    -- Порядок и идентификация
    sort_order INTEGER NOT NULL,
    is_courier_warehouse BOOLEAN NOT NULL DEFAULT false,
    warehouse_id TEXT,                    -- ID склада (если is_courier_warehouse = true)
    
    -- Адрес и координаты
    address TEXT,
    longitude NUMERIC(11, 8),
    latitude NUMERIC(10, 8),
    
    -- Временные окна доставки
    delivery_desired_datetime TIMESTAMP,
    delivery_desired_datetime_after TIMESTAMP,
    delivery_desired_datetime_before TIMESTAMP,
    
    -- Требования
    is_sms_required BOOLEAN NOT NULL DEFAULT false,
    is_photo_required BOOLEAN NOT NULL DEFAULT false,
    load_type TEXT,                       -- unload, load
    
    -- Получатель
    receiver_name TEXT,
    receiver_phone TEXT,
    comment TEXT,
    
    -- Статус точки
    status TEXT DEFAULT 'pending',        -- pending, arrived, completed, skipped
    status_datetime TIMESTAMP,
    
    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    -- Ограничения
    CONSTRAINT unique_transportation_sort UNIQUE(transportation_id, sort_order),
    CONSTRAINT check_warehouse_or_address CHECK (
        (is_courier_warehouse = true AND warehouse_id IS NOT NULL) OR
        (is_courier_warehouse = false AND address IS NOT NULL)
    )
);

-- Индексы
CREATE INDEX idx_courier_route_point_transportation ON applications.courier_route_point(transportation_id);
CREATE INDEX idx_courier_route_point_status ON applications.courier_route_point(status);

-- Комментарии
COMMENT ON TABLE applications.courier_route_point IS 'Точки маршрута курьерской доставки';
COMMENT ON COLUMN applications.courier_route_point.sort_order IS 'Порядковый номер точки в маршруте';
COMMENT ON COLUMN applications.courier_route_point.is_courier_warehouse IS 'Является ли точка нашим курьерским складом';
COMMENT ON COLUMN applications.courier_route_point.load_type IS 'Тип операции: unload (разгрузка), load (погрузка)';
```

### 2.3. Новая таблица `applications.courier_route_order`

**Заказы в точках маршрута**:

```sql
CREATE TABLE IF NOT EXISTS applications.courier_route_order (
    id BIGSERIAL PRIMARY KEY,
    route_point_id BIGINT NOT NULL REFERENCES applications.courier_route_point(id) ON DELETE CASCADE,
    
    -- Идентификация заказа
    track_number TEXT NOT NULL,
    external_id TEXT NOT NULL,            -- ID заказа из TEEZ_PVZ
    teezpost_id TEXT,                     -- ID заказа из TEEZ_POST
    load_type TEXT NOT NULL,              -- unload, load
    
    -- Статус заказа
    status TEXT NOT NULL DEFAULT 'pending',
    status_reason TEXT,                   -- customer_not_available, customer_postponed, force_majeure
    status_datetime TIMESTAMP,
    
    -- Подтверждения
    sms_code_used TEXT,
    photo_id UUID,
    courier_comment TEXT,
    
    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    CONSTRAINT unique_track_number UNIQUE(track_number)
);

-- Индексы
CREATE INDEX idx_courier_order_route_point ON applications.courier_route_order(route_point_id);
CREATE INDEX idx_courier_order_external_id ON applications.courier_route_order(external_id);
CREATE INDEX idx_courier_order_status ON applications.courier_route_order(status);

-- Комментарии
COMMENT ON TABLE applications.courier_route_order IS 'Заказы в точках маршрута курьерской доставки';
COMMENT ON COLUMN applications.courier_route_order.status IS 'Статус: pending, delivered, returned, partially_returned, not_delivered, not_reached';
COMMENT ON COLUMN applications.courier_route_order.status_reason IS 'Причина невыдачи: customer_not_available, customer_postponed, force_majeure';
```

### 2.4. Новая таблица `applications.courier_route_position`

**Позиции (товары) в заказах**:

```sql
CREATE TABLE IF NOT EXISTS applications.courier_route_position (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES applications.courier_route_order(id) ON DELETE CASCADE,
    
    position_code TEXT NOT NULL,
    position_shortname TEXT NOT NULL,
    quantity INTEGER DEFAULT 1,
    returned_quantity INTEGER DEFAULT 0,
    
    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_courier_position_order ON applications.courier_route_position(order_id);

-- Комментарии
COMMENT ON TABLE applications.courier_route_position IS 'Позиции (товары) в заказах курьерской доставки';
```

### 2.5. Новая таблица `applications.courier_route_log`

**История изменений маршрута**:

```sql
CREATE TABLE IF NOT EXISTS applications.courier_route_log (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id) ON DELETE CASCADE,
    
    event_type TEXT NOT NULL,             -- imported, validated, assigned, started, point_completed, completed, closed
    event_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    actor_id BIGINT,                      -- ID сотрудника (если применимо)
    actor_type TEXT,                      -- logist, courier, system, integration
    
    details JSONB,                        -- Дополнительные данные события
    description TEXT,
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_courier_log_transportation ON applications.courier_route_log(transportation_id);
CREATE INDEX idx_courier_log_event_type ON applications.courier_route_log(event_type);
CREATE INDEX idx_courier_log_datetime ON applications.courier_route_log(event_datetime);

-- Комментарии
COMMENT ON TABLE applications.courier_route_log IS 'История всех изменений курьерских маршрутов';
```

### 2.6. Новая таблица `applications.courier_integration_log`

**Логи интеграции с внешними системами**:

```sql
CREATE TABLE IF NOT EXISTS applications.courier_integration_log (
    id BIGSERIAL PRIMARY KEY,
    
    -- Идентификация запроса
    integration_type TEXT NOT NULL,       -- incoming, outgoing
    source_system TEXT NOT NULL,          -- TEEZ_PVZ
    endpoint TEXT NOT NULL,               -- /integration/teez/waybills
    http_method TEXT NOT NULL,            -- POST, GET, PUT
    
    -- Связь с объектом
    object_type TEXT NOT NULL,            -- waybill, order_result
    object_id TEXT,                       -- external_waybill_id или transportation_id
    
    -- Данные запроса/ответа
    request_payload JSONB,
    response_payload JSONB,
    http_status_code INTEGER,
    
    -- Результат
    status TEXT NOT NULL,                 -- success, failure, retry
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    
    -- Временные метки
    request_datetime TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    response_datetime TIMESTAMP,
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Индексы
CREATE INDEX idx_courier_integration_object ON applications.courier_integration_log(object_type, object_id);
CREATE INDEX idx_courier_integration_status ON applications.courier_integration_log(status);
CREATE INDEX idx_courier_integration_datetime ON applications.courier_integration_log(request_datetime);

-- Комментарии
COMMENT ON TABLE applications.courier_integration_log IS 'Логи всех интеграционных вызовов для курьерской доставки';
```

---

## 3. Схема `dictionaries` - Справочники курьерских складов

### 3.1. Новая таблица `dictionaries.courier_warehouse`

```sql
CREATE TABLE IF NOT EXISTS dictionaries.courier_warehouse (
    id BIGSERIAL PRIMARY KEY,
    
    name TEXT NOT NULL,
    is_pickup_point BOOLEAN NOT NULL DEFAULT false,
    
    -- Интеграционные данные
    integration_system TEXT NOT NULL,     -- TEEZ_PVZ
    external_id TEXT NOT NULL,            -- ID склада во внешней системе
    
    -- Адрес и координаты
    address TEXT NOT NULL,
    longitude NUMERIC(11, 8),
    latitude NUMERIC(10, 8),
    
    -- Статус
    is_active BOOLEAN NOT NULL DEFAULT true,
    
    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL,
    
    CONSTRAINT unique_external_warehouse UNIQUE(integration_system, external_id)
);

-- Индексы
CREATE INDEX idx_courier_warehouse_external ON dictionaries.courier_warehouse(integration_system, external_id);
CREATE INDEX idx_courier_warehouse_active ON dictionaries.courier_warehouse(is_active);

-- Комментарии
COMMENT ON TABLE dictionaries.courier_warehouse IS 'Справочник курьерских складов и ПВЗ';
```

---

## 4. Enums и справочные значения

### 4.1. Статусы маршрутного листа

```sql
CREATE TYPE waybill_validation_status_enum AS ENUM (
    'imported_draft',      -- Импортирован, не провалидирован
    'validated',           -- Провалидирован логистом
    'assigned',            -- Назначен курьеру
    'in_route',           -- Курьер в пути
    'completed',          -- Маршрут выполнен
    'closed'              -- Закрыт логистом
);
```

### 4.2. Статусы заказа

```sql
CREATE TYPE order_status_enum AS ENUM (
    'pending',             -- Ожидает выполнения
    'delivered',           -- Доставлен успешно
    'returned',            -- Полный возврат
    'partially_returned',  -- Частичный возврат
    'not_delivered',       -- Не доставлен
    'not_reached'          -- Курьер не доехал
);
```

### 4.3. Причины невыдачи

```sql
CREATE TYPE order_not_delivered_reason_enum AS ENUM (
    'customer_not_available',  -- Клиент недоступен
    'customer_postponed',      -- Клиент попросил отложить
    'force_majeure'            -- Форс-мажор
);
```

---

## 5. Миграции Flyway

### Порядок применения:

1. `V2025_01_01_01__add_courier_driver_role.sql`
2. `V2025_01_01_02__add_courier_fields_to_employee.sql`
3. `V2025_01_01_03__add_courier_delivery_to_transportation.sql`
4. `V2025_01_01_04__create_courier_route_tables.sql`
5. `V2025_01_01_05__create_courier_warehouse_dictionary.sql`
6. `V2025_01_01_06__create_courier_enums.sql`

---

## 6. Rollback план

В случае необходимости отката изменений:

```sql
-- Удаление таблиц
DROP TABLE IF EXISTS applications.courier_integration_log CASCADE;
DROP TABLE IF EXISTS applications.courier_route_log CASCADE;
DROP TABLE IF EXISTS applications.courier_route_position CASCADE;
DROP TABLE IF EXISTS applications.courier_route_order CASCADE;
DROP TABLE IF EXISTS applications.courier_route_point CASCADE;
DROP TABLE IF EXISTS dictionaries.courier_warehouse CASCADE;

-- Удаление колонок
ALTER TABLE applications.transportation
DROP COLUMN IF EXISTS source_system,
DROP COLUMN IF EXISTS external_waybill_id,
DROP COLUMN IF EXISTS delivery_type,
DROP COLUMN IF EXISTS responsible_courier_warehouse_id,
DROP COLUMN IF EXISTS target_delivery_day,
DROP COLUMN IF EXISTS validation_status;

ALTER TABLE users.employee
DROP COLUMN IF EXISTS primary_pickup_point_id,
DROP COLUMN IF EXISTS integration_data,
DROP COLUMN IF EXISTS current_status;

-- Удаление enums
DROP TYPE IF EXISTS order_not_delivered_reason_enum;
DROP TYPE IF EXISTS order_status_enum;
DROP TYPE IF EXISTS waybill_validation_status_enum;
DROP TYPE IF EXISTS courier_status_enum;
```
