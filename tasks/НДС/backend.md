# НДС — Backend задачи

## Текущее состояние

| Что есть | Где |
|----------|-----|
| `Organization.vat` (boolean) | `organization/model/Organization.java` |
| `Invoice.totalAmountWithoutVat/totalVatAmount/totalAmountWithVat` | `invoice/entity/Invoice.java` |
| `Act` с теми же VAT полями | `invoice/entity/Act.java` |
| `Transportation.isNdsIncluded` (в frontend interface) | только на фронте, в entity нет |
| `TransportationCost` список в Transportation | `applications/entity/Transportation.java` |

**Проблема:** сейчас НДС определяется по флагу `Organization.vat` — либо есть, либо нет. Нет выбора режима (добавить/выделить), нет хранения суммы НДС на уровне заявки. Invoice генерируется суммированием TransportationCost без явного хранения VAT-параметров заявки.

---

## TASK-VAT-BE-1: Миграция БД — добавить VAT поля в таблицу transportation

**Приоритет:** 🔴 Критический (блокирует всё остальное)

### Что сделать

Создать Flyway миграцию в `coube-documentation/migration-db/`:

```sql
-- V{timestamp}__add_vat_fields_to_transportation.sql

ALTER TABLE applications.transportation
    ADD COLUMN vat_enabled     BOOLEAN      NOT NULL DEFAULT FALSE,
    ADD COLUMN vat_mode        VARCHAR(20)  NULL,         -- 'ADD' | 'EXTRACT'
    ADD COLUMN vat_rate        DECIMAL(5,2) NULL,         -- 16.00
    ADD COLUMN amount_net      DECIMAL(19,2) NULL,        -- сумма без НДС
    ADD COLUMN vat_amount      DECIMAL(19,2) NULL,        -- сумма НДС
    ADD COLUMN amount_gross    DECIMAL(19,2) NULL;        -- итого с НДС

-- Проставить для существующих записей
-- Если у исполнителя vat=true — считаем что НДС был
UPDATE applications.transportation t
SET vat_enabled = true,
    vat_mode    = 'ADD',
    vat_rate    = 16.00
FROM users.organization o
WHERE t.executor_organization_id = o.id
  AND o.vat = true;

-- Комментарии
COMMENT ON COLUMN applications.transportation.vat_enabled  IS 'Применяется ли НДС к перевозке';
COMMENT ON COLUMN applications.transportation.vat_mode     IS 'Режим НДС: ADD - добавить к сумме, EXTRACT - выделить из суммы';
COMMENT ON COLUMN applications.transportation.vat_rate     IS 'Ставка НДС в процентах (16.00)';
COMMENT ON COLUMN applications.transportation.amount_net   IS 'Сумма без НДС';
COMMENT ON COLUMN applications.transportation.vat_amount   IS 'Сумма НДС';
COMMENT ON COLUMN applications.transportation.amount_gross IS 'Итого с НДС';
```

### Критерии готовности
- [ ] Миграция применяется без ошибок
- [ ] Существующие записи обновлены корректно
- [ ] Поля nullable (не ломают старые вставки без VAT)

---

## TASK-VAT-BE-2: Добавить enum VatMode + обновить Transportation entity

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-1

### Что сделать

**1. Создать enum:**
```java
// applications/entity/VatMode.java
public enum VatMode {
    ADD,     // НДС добавляется к сумме (введённая сумма = net)
    EXTRACT  // НДС выделяется из суммы (введённая сумма = gross)
}
```

**2. Обновить `Transportation.java` — добавить поля:**
```java
@Column(name = "vat_enabled", nullable = false)
private boolean vatEnabled = false;

@Enumerated(EnumType.STRING)
@Column(name = "vat_mode")
private VatMode vatMode;

@Column(name = "vat_rate", precision = 5, scale = 2)
private BigDecimal vatRate;

@Column(name = "amount_net", precision = 19, scale = 2)
private BigDecimal amountNet;

@Column(name = "vat_amount", precision = 19, scale = 2)
private BigDecimal vatAmount;

@Column(name = "amount_gross", precision = 19, scale = 2)
private BigDecimal amountGross;
```

### Критерии готовности
- [ ] Entity компилируется
- [ ] Маппинг на колонки БД корректен

---

## TASK-VAT-BE-3: Обновить DTO для создания/обновления заявки

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-2

### Что сделать

Найти DTO создания заявки (предположительно `CreateTransportationDto` или аналог в `applications/dto/`), добавить поля:

```java
// В DTO создания заявки
@Schema(description = "Применяется ли НДС")
private boolean vatEnabled;

@Schema(description = "Режим НДС: ADD - добавить к сумме, EXTRACT - выделить из суммы")
private VatMode vatMode;

@Schema(description = "Введённая пользователем сумма (до расчёта)")
@NotNull
private BigDecimal inputAmount;
```

**Важно:** `inputAmount` — это то, что ввёл пользователь. Расчёт `amountNet/vatAmount/amountGross` делается в сервисе.

**Обновить Response DTO** (TransportationResponse или аналог):
```java
private boolean vatEnabled;
private VatMode vatMode;
private BigDecimal vatRate;
private BigDecimal amountNet;
private BigDecimal vatAmount;
private BigDecimal amountGross;
```

### Критерии готовности
- [ ] DTO принимает VAT параметры
- [ ] Response возвращает расчётные VAT поля
- [ ] Swagger документация обновлена

---

## TASK-VAT-BE-4: Логика расчёта НДС в TransportationService

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-3

### Что сделать

В сервисе создания/обновления заявки добавить метод расчёта НДС:

```java
// Создать VatCalculationService или добавить в TransportationService

private static final BigDecimal VAT_RATE = new BigDecimal("16.00");
private static final BigDecimal VAT_DIVISOR = new BigDecimal("1.16");

public VatCalculationResult calculateVat(boolean vatEnabled, VatMode vatMode, BigDecimal inputAmount) {
    if (!vatEnabled || vatMode == null || inputAmount == null) {
        return VatCalculationResult.noVat(inputAmount);
    }

    return switch (vatMode) {
        case ADD -> {
            // inputAmount = net, НДС добавляется сверху
            BigDecimal vatAmount = inputAmount.multiply(VAT_RATE)
                .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
            BigDecimal gross = inputAmount.add(vatAmount);
            yield new VatCalculationResult(inputAmount, vatAmount, gross, VAT_RATE);
        }
        case EXTRACT -> {
            // inputAmount = gross, НДС выделяется из суммы
            BigDecimal net = inputAmount.divide(VAT_DIVISOR, 2, RoundingMode.HALF_UP);
            BigDecimal vatAmount = inputAmount.subtract(net);
            yield new VatCalculationResult(net, vatAmount, inputAmount, VAT_RATE);
        }
    };
}

// Вспомогательный record
record VatCalculationResult(
    BigDecimal amountNet,
    BigDecimal vatAmount,
    BigDecimal amountGross,
    BigDecimal vatRate
) {
    static VatCalculationResult noVat(BigDecimal amount) {
        return new VatCalculationResult(amount, BigDecimal.ZERO, amount, BigDecimal.ZERO);
    }
}
```

**В методе сохранения заявки:**
```java
VatCalculationResult vat = calculateVat(dto.isVatEnabled(), dto.getVatMode(), dto.getInputAmount());
transportation.setVatEnabled(dto.isVatEnabled());
transportation.setVatMode(dto.getVatMode());
transportation.setVatRate(vat.vatRate());
transportation.setAmountNet(vat.amountNet());
transportation.setVatAmount(vat.vatAmount());
transportation.setAmountGross(vat.amountGross());
```

### Критерии готовности
- [ ] `ADD`: inputAmount=100000 → net=100000, vat=16000, gross=116000
- [ ] `EXTRACT`: inputAmount=116000 → net=100000, vat=16000, gross=116000
- [ ] `vatEnabled=false`: net=inputAmount, vat=0, gross=inputAmount
- [ ] Округление до 2 знаков после запятой (RoundingMode.HALF_UP)
- [ ] Формула сходится: `amountNet + vatAmount = amountGross`

---

## TASK-VAT-BE-5: Обновить InvoiceService — использовать VAT из Transportation

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-4

### Текущая логика (предположительно в `InvoiceService.java`)

Сейчас `InvoiceService` при создании счёта суммирует стоимости из `TransportationCost` и применяет VAT на основе `Organization.vat`.

### Что изменить

При создании Invoice суммировать `amountNet`, `vatAmount`, `amountGross` из Transportation:

```java
// В InvoiceService.createInvoice(CreateInvoiceDto dto)

List<Transportation> transportations = transportationRepository.findAllById(dto.getTransportationIds());

// Валидация: все заявки должны иметь согласованный VAT статус
// (опционально: предупреждать если смешанные VAT/без VAT)

BigDecimal totalNet   = transportations.stream()
    .map(t -> t.getAmountNet() != null ? t.getAmountNet() : BigDecimal.ZERO)
    .reduce(BigDecimal.ZERO, BigDecimal::add);

BigDecimal totalVat   = transportations.stream()
    .map(t -> t.getVatAmount() != null ? t.getVatAmount() : BigDecimal.ZERO)
    .reduce(BigDecimal.ZERO, BigDecimal::add);

BigDecimal totalGross = transportations.stream()
    .map(t -> t.getAmountGross() != null ? t.getAmountGross() : BigDecimal.ZERO)
    .reduce(BigDecimal.ZERO, BigDecimal::add);

Invoice invoice = Invoice.builder()
    .totalAmountWithoutVat(totalNet)
    .totalVatAmount(totalVat)
    .totalAmountWithVat(totalGross)
    // ...остальные поля
    .build();
```

### Критерии готовности
- [ ] Счёт корректно суммирует VAT из нескольких заявок
- [ ] Если заявка без НДС — `vatAmount=0`, `amountGross=amountNet`
- [ ] InvoiceResponse возвращает все три суммы
- [ ] Документ Excel/PDF генерируется с правильными значениями

---

## TASK-VAT-BE-6: Обновить генерацию документов (Excel/PDF)

**Приоритет:** 🟡 Средний
**Зависит от:** TASK-VAT-BE-5

### Что сделать

В `DocumentGenerationService` / `InvoiceTemplate` / `HtmlTemplateService`:

- Если `totalVatAmount == 0` → отображать строку "Без НДС" вместо строки НДС
- Если `totalVatAmount > 0` → отображать три строки:
  - Сумма без НДС: `totalAmountWithoutVat`
  - НДС 16%: `totalVatAmount`
  - ИТОГО: `totalAmountWithVat`

Аналогично для Act (АВР).

### Критерии готовности
- [ ] PDF/Excel счёт отображает НДС корректно
- [ ] "Без НДС" видно если vatEnabled=false
- [ ] Цифры в документе совпадают с расчётными

---

## TASK-VAT-BE-7: Добавить endpoint для пересчёта НДС (preview)

**Приоритет:** 🟢 Желательно

### Что сделать

Добавить легковесный endpoint для мгновенного пересчёта без сохранения (нужен для real-time UI):

```java
// POST /api/v1/vat/calculate
// Request: { vatEnabled, vatMode, inputAmount }
// Response: { amountNet, vatAmount, amountGross, vatRate }
```

Использует тот же `VatCalculationService` без записи в БД.

### Критерии готовности
- [ ] Endpoint доступен без авторизации (или с базовой)
- [ ] Отвечает < 50ms
- [ ] Не требует транзакции / БД запроса
