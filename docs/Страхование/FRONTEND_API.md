# Страхование — API для фронтенда

> Документ для фронтенд-разработчика. Описывает все эндпоинты интеграции страхования грузов через Eurasian Insurance.

---

## Общее

| Параметр | Значение |
|---|---|
| Base URL | `http://localhost:8080` (локально) |
| Авторизация | `Authorization: Bearer <token>` |
| Организация | `X-Organization-Id: <orgId>` |
| Content-Type | `application/json` |

Все эндпоинты требуют роль: `CEO`, `ADMIN`, `SIGNER`, `LOGISTICIAN`, `ACCOUNTANT` или `SUPER_ADMIN` и тип компании `CUSTOMER`.

---

## Флоу со стороны фронтенда

```
1. Пользователь заполняет форму страхования → POST /verify/{transportationId}
2. Показываем PDF документов → POST /prepare/{transportationId}
3. Пользователь подписывает PDF через NCALayer → POST /sign/{policyId}
4. Проверка статуса в любой момент → GET /status/{policyId}
```

---

## 1. Верификация компании и физлица

**`POST /api/insurance/bpm/verify/{transportationId}`**

Шаги 1–2: проверяет компанию заказчика и CEO в базах Eurasian (ГБД/БМГ).
Создаёт полис со статусом `PENDING`. Занимает ~10–30 секунд.

> ⚠️ Обычно этот эндпоинт не нужен вызывать отдельно — `/prepare` делает то же самое. Используй если хочешь заранее прогреть проверку.

### Path параметры
| Параметр | Тип | Описание |
|---|---|---|
| `transportationId` | Long | ID перевозки |

### Request Body
```json
{
  "insuranceSumKzt": 1000000,
  "cargoQuantity": 10,
  "cargoPackaging": "паллеты"
}
```

| Поле | Тип | Обязательно | Описание |
|---|---|---|---|
| `insuranceSumKzt` | Number | ✅ | Страховая сумма в тенге (стоимость груза) |
| `cargoQuantity` | Integer | ✅ | Количество мест/единиц груза |
| `cargoPackaging` | String | ✅ | Вид упаковки (напр. "паллеты", "коробки") |

### Response `200 OK`
Пустое тело.

### Возможные ошибки
| Код | Описание |
|---|---|
| `MISSING_DATA` | У перевозки нет организации заказчика или CEO |
| `BPM_INIT_ERROR` | Ошибка со стороны Eurasian при проверке |
| `BPM_TIMEOUT` | Eurasian не ответил за 120 секунд |

---

## 2. Подготовка документов (основной шаг)

**`POST /api/insurance/bpm/prepare/{transportationId}`**

Шаги 1–4: верифицирует компанию, оформляет страховку, возвращает два PDF для подписания клиентом.

> ✅ Это главный эндпоинт флоу. Вызывается когда пользователь нажимает "Оформить страховку".

### Path параметры
| Параметр | Тип | Описание |
|---|---|---|
| `transportationId` | Long | ID перевозки |

### Request Body
```json
{
  "insuranceSumKzt": 1000000,
  "cargoQuantity": 10,
  "cargoPackaging": "паллеты"
}
```

| Поле | Тип | Обязательно | Описание |
|---|---|---|---|
| `insuranceSumKzt` | Number | ✅ | Страховая сумма в тенге |
| `cargoQuantity` | Integer | ✅ | Количество мест/единиц |
| `cargoPackaging` | String | ✅ | Вид упаковки |

### Response `200 OK`
```json
{
  "policyId": 5,
  "applicationPdf": "JVBERi0xLjQK...",
  "contractPdf": "JVBERi0xLjQK..."
}
```

| Поле | Тип | Описание |
|---|---|---|
| `policyId` | Long | ID созданного полиса — сохранить! Нужен для `/sign` и `/status` |
| `applicationPdf` | String | base64 PDF **заявления** для подписания |
| `contractPdf` | String | base64 PDF **договора** для подписания |

> ⚠️ `policyId` нужно сохранить в стейте — он используется в следующих шагах.

### Как отобразить PDF
```javascript
const blob = base64ToBlob(response.applicationPdf, 'application/pdf');
const url = URL.createObjectURL(blob);
window.open(url); // или показать в iframe

function base64ToBlob(base64, type) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new Blob([bytes], { type });
}
```

### Возможные ошибки
| Код | Описание |
|---|---|
| `MISSING_DATA` | Нет точек маршрута (LOADING/UNLOADING) у перевозки |
| `VERIFY_FIRST` | Верификация не пройдена (не должно возникать — prepare делает verify сам) |
| `BPM_INIT_ERROR` | Ошибка Eurasian |
| `BPM_TIMEOUT` | Таймаут 120 сек |

---

## 3. Подписание документов

**`POST /api/insurance/bpm/sign/{policyId}`**

Шаги 5–7: принимает CMS-подписи клиента, завершает флоу. После этого полис переходит в статус `ACTIVE`.

> ✅ Вызывается после того, как пользователь подписал оба PDF через NCALayer.

### Path параметры
| Параметр | Тип | Описание |
|---|---|---|
| `policyId` | Long | ID полиса из ответа `/prepare` |

### Request Body
```json
{
  "applicationCms": "MIIHCAYJKoZIhvcNAQcCoIIG...",
  "contractCms": "MIIHCAYJKoZIhvcNAQcCoIIG..."
}
```

| Поле | Тип | Обязательно | Описание |
|---|---|---|---|
| `applicationCms` | String | ✅ | base64 CMS-подпись заявления (от NCALayer) |
| `contractCms` | String | ✅ | base64 CMS-подпись договора (от NCALayer) |

### Response `200 OK`
Пустое тело. Полис теперь `ACTIVE`.

### Как получить CMS — переиспользуй готовые сервисы из проекта

В проекте уже есть всё необходимое — **не нужно писать с нуля**.

#### Вариант 1: NCALayer (ЭЦП через USB-токен)

Используй готовый сервис `src/services/pki.ts`:

```typescript
import { Pki } from '@/services/pki'

const pki = new Pki()
await pki.start() // подключение к NCALayer wss://127.0.0.1:13579/
pki.config()      // настройка токена

// Подписать applicationPdf:
pki.signBase64(applicationPdf, (applicationCms) => {
  // Подписать contractPdf:
  pki.signBase64(contractPdf, (contractCms) => {
    // Отправить на бэкенд
    await signInsurance(policyId, { applicationCms, contractCms })
  })
})
```

#### Вариант 2: QR (eGov Mobile)

Для QR-подписания бэкенд должен поддержать новый `documentType: 'insurance'` в eGov сессии.
Используй готовые сервисы `src/services/egovSign.ts` + компонент `QRSignModal`:

```typescript
import EgovSignService from '@/services/egovSign'

const session = await EgovSignService.initSession({
  documentId: String(policyId),
  documentType: 'insurance' // нужно добавить на бэкенде
})
// Показать QRSignModal с session.qrCode, session.sessionId
```

#### Готовый компонент для выбора метода

Посмотри `src/components/SignPdfModal/SignPdfModal.vue` — там уже есть UI с выбором между NCALayer и QR + превью PDF. Можно переиспользовать напрямую или адаптировать.

Полный готовый флоу с выбором метода — `src/components/ContractSigningFlow/ContractSigningFlow.vue`.

### Возможные ошибки
| Код | Описание |
|---|---|
| `PREPARE_FIRST` | Полис не прошёл `/prepare` (нет cargo_inst_id) |
| `NOT_FOUND` | Полис с таким ID не найден |
| `BPM_TIMEOUT` | Таймаут при ожидании Eurasian |

---

## 4. Статус полиса

**`GET /api/insurance/bpm/status/{policyId}`**

Получить текущий статус полиса. Можно опрашивать для отслеживания.

### Path параметры
| Параметр | Тип | Описание |
|---|---|---|
| `policyId` | Long | ID полиса |

### Response `200 OK`
```json
{
  "policyId": 5,
  "status": "ACTIVE",
  "cargoInstId": "16038150",
  "invoiceFileId": "abbf2f4e-b5c7-42f9-aa2e-e5423704e1d3"
}
```

| Поле | Тип | Описание |
|---|---|---|
| `policyId` | Long | ID полиса |
| `status` | String | Статус полиса (см. таблицу ниже) |
| `cargoInstId` | String \| null | ID процесса в Eurasian BPM (после prepare) |
| `invoiceFileId` | UUID \| null | ID файла счёта на оплату (после sign) |

### Статусы полиса
| Статус | Описание |
|---|---|
| `PENDING` | Полис создан, верификация/оформление ещё не завершены |
| `ACTIVE` | Договор заключён, страховка активна |
| `CANCELLED` | Страховка отменена |

### Возможные ошибки
| Код | Описание |
|---|---|
| `NOT_FOUND` | Полис не найден |

---

## Полный пример флоу (JavaScript)

```javascript
const API = 'http://localhost:8080';
const headers = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${token}`,
  'X-Organization-Id': orgId
};

// Шаг 1: Оформляем страховку, получаем PDF
const prepareRes = await fetch(`${API}/api/insurance/bpm/prepare/${transportationId}`, {
  method: 'POST',
  headers,
  body: JSON.stringify({
    insuranceSumKzt: 1000000,
    cargoQuantity: 10,
    cargoPackaging: 'паллеты'
  })
}).then(r => r.json());

const { policyId, applicationPdf, contractPdf } = prepareRes;
// → показываем пользователю PDF для ознакомления

// Шаг 2: Пользователь подписывает через NCALayer
const applicationCms = await signWithNCALayer(applicationPdf);
const contractCms    = await signWithNCALayer(contractPdf);

// Шаг 3: Отправляем подписи
await fetch(`${API}/api/insurance/bpm/sign/${policyId}`, {
  method: 'POST',
  headers,
  body: JSON.stringify({ applicationCms, contractCms })
});

// Шаг 4: Проверяем статус
const status = await fetch(`${API}/api/insurance/bpm/status/${policyId}`, { headers })
  .then(r => r.json());

console.log(status.status); // → "ACTIVE"
console.log(status.invoiceFileId); // → UUID файла счёта
```

---

## Скачать файлы (PDF счёта)

После успешного `/sign` в поле `invoiceFileId` будет UUID файла. Скачать его:

```
GET /api/files/{invoiceFileId}
Authorization: Bearer <token>
```

---

## Структура ошибок

Все ошибки возвращаются в формате:

```json
{
  "traceId": "69de...",
  "message": {
    "ru": "Описание ошибки",
    "kk": "Описание ошибки"
  },
  "path": "/api/insurance/bpm/...",
  "timestamp": "2026-04-14T20:18:40",
  "details": []
}
```

HTTP статус: `400` для бизнес-ошибок, `401` для проблем с авторизацией, `500` для неожиданных ошибок.

---

## Важные моменты

1. **`/prepare` занимает 30–60 секунд** — Eurasian генерирует PDF договора. Показывай лоадер.
2. **`/sign` занимает 30–90 секунд** — Eurasian регистрирует договор в 1С. Показывай лоадер.
3. **`policyId` из `/prepare`** — сохрани в стейт, он нужен для `/sign` и `/status`.
4. **PDF размером ~40KB** — `applicationPdf` и `contractPdf` это base64 строки.
5. **NCALayer должен быть запущен** — WebSocket `wss://127.0.0.1:13579/` должен быть доступен.
