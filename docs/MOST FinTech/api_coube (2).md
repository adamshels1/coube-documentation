# Coube API для партнёров

Все эндпоинты доступны по базовому пути `/api/v1/coube` и должны вызываться по HTTPS

## Аутентификация и заголовки

- `X-API-Key` **(обязательный)** — общий секрет, выданный Coube. При отсутствии или неверном значении сервер отвечает `401 Unauthorized`.

Ответы возвращаются в формате JSON. Если не указано иное.
Успешные вызовы отвечают `200 OK`, ошибки содержат поле `detail` с описанием.

## Общие правила валидации

- `tax_id` — строка из 12 цифр;
- `iban` — 20 алфавитно-цифровых символов;
- Номер телефона — формат `+########` с 8–15 цифрами после `+`;
- Email содержит один `@` и ненулевые части до/после него;
- Денежные суммы — положительные десятичные числа с двумя знаками после запятой. `factoring_amount` не превышает `service_amount`.
- `environment` — одно из значений: `prod`, `test`, `dev`.

## Эндпоинты

### GET `/client`

Возвращает информацию о клиенте по `tax_id`.

- Query-параметр `tax_id` — строка из 12 цифр.
- Заголовок `X-API-Key` обязателен.

**Ответ `200 OK`:**

```json
{
  "tax_id": "123456789012",
  "title": "ТОО Компания",
  "kind": "legal_entity",
  "limit_amount": 2500000.0
}
```

`limit_amount` может быть `null` - это означает что клиент еще на стадии скоринга или проверки. При отсутствии клиента в БД MOST — `404 Not Found`. 

### POST `/client`

Регистрирует нового клиента в системе. Требует `multipart/form-data`.

| Поле | Тип | Описание |
| --- | --- | --- |
| `environment` | string | Окружение: `prod`, `test`, `dev` |
| `tax_id` | string | БИН/ИИН клиента (12 цифр) |
| `title` | string? | Название компании/ФИО |
| `address` | string? | Адрес |
| `role` | string? | Роль: `carrier` или `customer` |
| `ceo_fullname` | string? | ФИО руководителя |
| `ceo_phone` | string? | Телефон руководителя |
| `ceo_email` | string? | Email руководителя |
| `contact_fullname` | string? | ФИО контактного лица |
| `contact_phone` | string? | Телефон контактного лица |
| `contact_email` | string? | Email контактного лица |


**Ответ `201 Created`:**

```json
{
  "request_id": 123,
  "tax_id": "123456789012",
  "status": "new",
  "created_at": "2025-10-22T09:15:30.123456"
}
```

### GET `/factoring`

Возвращает текущий статус факторинговой заявки по номеру.

- Query-параметр `application_number` — номер заявки в формате `CUB-{id}-{date}`.
- Заголовок `X-API-Key` обязателен.

**Ответ `200 OK`:**

```json
{
  "application_number": "CUB-123-20251022",
  "status": "new"
}
```

**Возможные статусы заявки:**

| Статус | Описание |
| --- | --- |
| `new` | Новая заявка, ожидает загрузки документов через PUT |
| `processing` | Документы загружены, заявка в обработке |
| `ready_for_issue` | Проверка пройдена, заявка готова к выдаче |
| `issued` | Факторинг выдан |
| `rejected` | Заявка отклонена |
| `closed` | Заявка закрыта (оплачена) |

**Ошибки:**

- `401 Unauthorized` — `X-API-Key` отсутствует/неверен.
- `404 Not Found` — заявка не найдена.
- `422 Unprocessable Entity` — неверный формат `application_number`.

### POST `/factoring`

Создаёт новую факторинговую заявку. Требует `multipart/form-data`.

| Поле | Тип | Описание |
| --- | --- | --- |
| `environment` | string | Окружение: `prod`, `test`, `dev` |
| `coube_application_id` | string | ID заявки в Coube |
| `carrier_tax_id` | string | БИН/ИИН перевозчика (12 цифр) |
| `carrier_iban` | string | IBAN перевозчика (20 символов) |
| `carrier_contact_fullname` | string | ФИО контактного лица перевозчика (1–255 символов) |
| `carrier_contact_phone` | string | Телефон перевозчика |
| `carrier_contact_email` | string | Email перевозчика |
| `customer_tax_id` | string | БИН/ИИН клиента (12 цифр) |
| `customer_contact_fullname` | string | ФИО контактного лица клиента (1–255 символов) |
| `customer_contact_phone` | string | Телефон клиента |
| `customer_contact_email` | string | Email клиента |
| `service_amount` | string | Полная сумма услуг (десятичное число) |
| `factoring_amount` | string | Запрашиваемая сумма факторинга (<= service_amount) |
| `tariff` | string | Тариф |
| `factoring_agreement` | file | Договор факторинга (PDF, <= 10 MB) |
| `factoring_payout` | file | Заявка на факторинг (PDF, <= 10 MB) |
| `otp_validation` | file | OTP-подтверждение (text/plain, <= 1 MB) |

**Требования:**
- Клиенты `carrier_tax_id` и `customer_tax_id` должны существовать в системе MOST, поэтому их нужно предварительно регистрировать через POST `/client`

**Ответ `201 Created`:**

```json
{
  "application_number": "CUB-123-20251022",
  "status": "new"
}
```

**Ошибки:**

- `401 Unauthorized` — `X-API-Key` отсутствует/неверен.
- `422 Unprocessable Entity` — нарушение правил валидации или клиенты не найдены.

### PUT `/factoring`

Обновляет существующую заявку, добавляя документы и переводя в статус `processing`. Требует `multipart/form-data`.

| Поле | Тип | Описание |
| --- | --- | --- |
| `environment` | string | Окружение: `prod`, `test`, `dev` |
| `coube_application_id` | string | ID заявки в Coube (должен совпадать) |
| `application_number` | string | Номер заявки (формат: `CUB-{id}-{date}`) |
| `carrier_tax_id` | string | БИН/ИИН перевозчика (должен совпадать) |
| `carrier_iban` | string | IBAN перевозчика (должен совпадать) |
| `customer_tax_id` | string | БИН/ИИН клиента (должен совпадать) |
| `service_amount` | string | Сумма услуг (должна совпадать) |
| `factoring_amount` | string | Сумма факторинга (должна совпадать) |
| `tariff` | string | Тариф (должен совпадать) |
| `avr` | file | Акт выполненных работ (PDF, <= 10 MB) |
| `contract` | file | Договор (PDF, <= 10 MB) |
| `invoice` | file | Счёт-фактура (PDF, <= 10 MB) |
| `cms` | file | CMS-подпись (application/pkcs7-signature, <= 1 MB) |

**Бизнес-правила:**

- Статус заявки должен быть `new`, иначе `409 Conflict`.
- Все поля должны совпадать с сохранёнными значениями. Несовпадение вызывает `422 Unprocessable Entity`; в `detail.fields` перечислены отличия.

**Ответ `200 OK`:**

```json
{
  "application_number": "CUB-123-20251022",
  "status": "processing"
}
```

## Коды ошибок

| Статус | Когда |
| --- | --- |
| `400 Bad Request` | Некорректный формат запроса (редко, обычно 422) |
| `401 Unauthorized` | Не передан или неверен `X-API-Key` |
| `404 Not Found` | Клиент или заявка не найдены |
| `409 Conflict` | Неверный статус заявки при обновлении |
| `422 Unprocessable Entity` | Ошибки валидации, нарушения ограничений по файлам |

Ошибочные ответы соответствуют формату FastAPI, например `{ "detail": "application not found" }` или `{ "detail": { "message": "profile not found", "fields": ["carrier_tax_id"] } }`.
