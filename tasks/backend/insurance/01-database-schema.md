# Задача 1: Создание схемы БД для страхования

## Описание
Создать таблицы и схему БД для хранения данных о страховании грузов согласно ТЗ.

## Таблицы

### 1. `insurance_policies` - Полисы страхования
```sql
CREATE TABLE applications.insurance_policies (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT NOT NULL REFERENCES applications.transportation(id),

    -- Номер договора страхования (от страховой)
    contract_number TEXT UNIQUE,

    -- Статусы: pending, client_check_failed, documents_signed, contract_created, active, rejected
    status TEXT NOT NULL DEFAULT 'pending',

    -- Сумма страховой премии
    insurance_premium NUMERIC(15, 2),
    insurance_premium_currency TEXT DEFAULT 'KZT',

    -- Страховая сумма (стоимость груза)
    insurance_sum NUMERIC(15, 2),

    -- ID файлов
    signed_contract_file_id UUID,
    application_form_file_id UUID,

    -- Даты
    contract_start_date TIMESTAMP,
    contract_end_date TIMESTAMP,

    -- Стандартные поля
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

CREATE INDEX idx_insurance_transportation ON applications.insurance_policies(transportation_id);
CREATE INDEX idx_insurance_status ON applications.insurance_policies(status);
```

### 2. `insurance_client_checks` - Проверки клиентов (ПОД/ФТ)
```sql
CREATE TABLE applications.insurance_client_checks (
    id BIGSERIAL PRIMARY KEY,
    insurance_policy_id BIGINT NOT NULL REFERENCES applications.insurance_policies(id),

    -- Тип проверяемого: insured, beneficiary, beneficial_owner, director
    client_type TEXT NOT NULL,

    -- ИИН/БИН проверяемого
    id_number TEXT NOT NULL,

    -- ФИО
    last_name TEXT,
    first_name TEXT,
    middle_name TEXT,
    full_name TEXT,

    -- Результат проверки: passed, failed
    check_result TEXT NOT NULL,

    -- Ответ от API страховой (0 - OK, 1 - в черном списке)
    api_response INTEGER,

    checked_at TIMESTAMP NOT NULL DEFAULT NOW(),

    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

CREATE INDEX idx_client_checks_policy ON applications.insurance_client_checks(insurance_policy_id);
```

### 3. `insurance_documents` - Документы для страхования
```sql
CREATE TABLE applications.insurance_documents (
    id BIGSERIAL PRIMARY KEY,
    insurance_policy_id BIGINT NOT NULL REFERENCES applications.insurance_policies(id),

    -- Тип документа (коды из справочника страховой)
    document_type_code TEXT NOT NULL,
    document_type_name TEXT,

    -- ID файла в MinIO
    file_id UUID NOT NULL,
    file_name TEXT NOT NULL,

    -- Подпись ЭЦП (если есть)
    signature_id BIGINT REFERENCES file.signature(id),

    -- Статус отправки в страховую: pending, sent, confirmed, failed
    upload_status TEXT NOT NULL DEFAULT 'pending',

    uploaded_at TIMESTAMP,

    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

CREATE INDEX idx_insurance_docs_policy ON applications.insurance_documents(insurance_policy_id);
```

### 4. `insurance_api_logs` - Логи взаимодействия с API страховой
```sql
CREATE TABLE applications.insurance_api_logs (
    id BIGSERIAL PRIMARY KEY,
    insurance_policy_id BIGINT REFERENCES applications.insurance_policies(id),

    -- Метод API: CheckClient, CreateNewDocument, SavePicture
    api_method TEXT NOT NULL,

    -- Запрос и ответ
    request_payload JSONB,
    response_payload JSONB,

    -- HTTP статус
    http_status INTEGER,

    -- Статус: success, error
    status TEXT NOT NULL,
    error_message TEXT,

    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_logs_policy ON applications.insurance_api_logs(insurance_policy_id);
CREATE INDEX idx_api_logs_method ON applications.insurance_api_logs(api_method);
```

## Дополнения к существующим таблицам

### Добавить флаг в `applications.transportation`
```sql
ALTER TABLE applications.transportation
ADD COLUMN with_insurance BOOLEAN DEFAULT FALSE;
```

## Flyway миграция
Создать миграцию: `V{next_version}__add_insurance_tables.sql` в папке `coube-documentation/migration-db/`
