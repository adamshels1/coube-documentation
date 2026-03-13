# TASK-1: Создать схему БД для QR подписания

## Описание
Создать таблицу для хранения сессий QR подписания и расширить существующую таблицу signature для поддержки eGov подписания.

## Приоритет
High

## Story Points
3

## SQL миграция

### Файл миграции
`coube-documentation/migration-db/V{VERSION}__add_egov_signing_session.sql`

```sql
-- Таблица для сессий eGov подписания
CREATE TABLE IF NOT EXISTS applications.egov_signing_session (
    id BIGSERIAL PRIMARY KEY,

    -- Связи с документами
    contract_id BIGINT REFERENCES applications.contract(id),
    invoice_id BIGINT REFERENCES applications.invoices(id),
    act_id BIGINT REFERENCES applications.acts(id),
    registry_id BIGINT REFERENCES applications.registries(id),

    document_type TEXT NOT NULL, -- 'CONTRACT', 'INVOICE', 'ACT', 'REGISTRY'

    -- Статус сессии
    status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, SIGNED, EXPIRED, FAILED

    -- Метод подписания
    signing_method TEXT NOT NULL, -- 'QR', 'CROSS_SIGN'

    -- Токен авторизации для API №2
    auth_type TEXT NOT NULL DEFAULT 'TOKEN', -- 'NONE', 'TOKEN', 'EDS'
    auth_token TEXT,

    -- QR/Deep link данные
    qr_url TEXT NOT NULL,

    -- Сроки
    expires_at TIMESTAMP NOT NULL,
    signed_at TIMESTAMP,

    -- Подписанты
    expected_signers_count INTEGER DEFAULT 1,
    actual_signers_count INTEGER DEFAULT 0,

    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_egov_session_contract ON applications.egov_signing_session(contract_id);
CREATE INDEX idx_egov_session_invoice ON applications.egov_signing_session(invoice_id);
CREATE INDEX idx_egov_session_status ON applications.egov_signing_session(status);
CREATE INDEX idx_egov_session_expires ON applications.egov_signing_session(expires_at);

-- Расширение таблицы signature
ALTER TABLE file.signature
ADD COLUMN IF NOT EXISTS signing_session_id BIGINT REFERENCES applications.egov_signing_session(id),
ADD COLUMN IF NOT EXISTS signing_method TEXT, -- 'NCLAYER', 'EGOV_QR', 'EGOV_CROSS'
ADD COLUMN IF NOT EXISTS certificate_serial TEXT,
ADD COLUMN IF NOT EXISTS signature_data TEXT, -- base64 подписи
ADD COLUMN IF NOT EXISTS validation_status TEXT DEFAULT 'PENDING', -- PENDING, VALID, INVALID
ADD COLUMN IF NOT EXISTS validation_error TEXT,
ADD COLUMN IF NOT EXISTS validated_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_signature_session ON file.signature(signing_session_id);
CREATE INDEX IF NOT EXISTS idx_signature_method ON file.signature(signing_method);
CREATE INDEX IF NOT EXISTS idx_signature_validation_status ON file.signature(validation_status);
```

## Entity классы

### EgovSigningSession.java
```java
@Entity
@Table(name = "egov_signing_session", schema = "applications")
public class EgovSigningSession {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long contractId;
    private Long invoiceId;
    private Long actId;
    private Long registryId;

    private String documentType; // CONTRACT, INVOICE, ACT, REGISTRY
    private String status; // PENDING, SIGNED, EXPIRED, FAILED
    private String signingMethod; // QR, CROSS_SIGN

    private String authType;
    private String authToken;
    private String qrUrl;

    private LocalDateTime expiresAt;
    private LocalDateTime signedAt;

    private Integer expectedSignersCount;
    private Integer actualSignersCount;

    // аудит поля
}
```

## Критерии приемки
- ✅ Создана таблица `egov_signing_session`
- ✅ Расширена таблица `signature` новыми полями
- ✅ Добавлены все индексы
- ✅ Миграция успешно применяется на dev окружении
- ✅ Создан Entity класс `EgovSigningSession`

## Зависимости
Нет

## Связанные таблицы
- `applications.contract`
- `applications.invoices`
- `applications.acts`
- `applications.registries`
- `file.signature`
