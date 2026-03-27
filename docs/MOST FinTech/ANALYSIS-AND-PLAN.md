# MOST FinTech — Анализ текущего состояния и план доработок

> Дата анализа: 2026-03-27
> Тестовая среда MOST: `https://testcf.mfomost.kz/api/v1/coube`
> API Key (test): `7hDa3pXnQkLMV2rTyUz8JcWbNsFqReH1`

---

## 1. Как должно работать (идеальный флоу)

```
[Executor регистрируется в Coube]
          │
          ▼
[Нажимает "Подключить быструю оплату"]
          │
          ▼
[Coube: POST /client → MOST]         ← регистрация в системе MOST
          │
          ▼
[Статус: "Заявка на рассмотрении..."]
(MOST проводит скоринг)
          │
          ▼
[Coube polling GET /client каждые N мин]
          │
          ▼  factoring_available = true
[Coube: factoring_allowed = true АВТОМАТИЧЕСКИ]
[Уведомление: "Быстрая оплата доступна!"]
          │
          ▼
[Executor подписывает договор факторинга через ЭЦП]
          │
          ▼
[Customer создаёт перевозку с флагом "Быстрая оплата"]
          │
          ▼
[Executor откликается → подтверждает сумму → OTP]
          │
          ▼
[Coube: POST /factoring → MOST]      ← создание заявки
[Ответ: application_number CUB-XX-XXXXXXXX]
          │
          ▼
[Executor подписывает АВР]
          │
          ▼
[Coube: PUT /factoring → MOST]       ← загрузка документов
[Статус заявки: processing]
          │
          ▼
[Coube polling GET /factoring каждые 15 мин]
          │
          ▼  status = "issued"
[factoring status → PAID АВТОМАТИЧЕСКИ]
[Push/WhatsApp: "Деньги переведены!"]
```

---

## 2. Текущее состояние — что реализовано

### Бэкенд ✅

| Компонент | Статус | Файл |
|---|---|---|
| `MostApiClient` (WebClient + retry) | ✅ Готов | `factoring/client/MostApiClient.java` |
| `MostApiProperties` (конфиг) | ✅ Готов | `factoring/config/MostApiProperties.java` |
| `MostClientRegistrationService` | ✅ Готов | вызывается при `createPayout()` |
| `MostClientCheckService` (с кэшем) | ✅ Готов | вызывается из `/customer/limit` |
| `MostCreateApplicationService` | ✅ Готов | вызывается при `confirmPayout()` |
| `MostUploadDocumentsService` | ✅ Готов | вызывается при подписании АВР |
| `MostStatusPollingService` (каждые 15 мин) | ✅ Готов | polling → PAID/REJECTED |
| `MostFactoringStatusService` | ✅ Готов | GET /factoring |
| Все exception-классы | ✅ Готов | MostApiException и др. |
| Все DTO/Records | ✅ Готов | MostApplicationResponse и др. |
| Все миграции БД | ✅ Готово | most_* поля в org и payout_request |
| `most_api_outbox` таблица | ✅ В БД | миграция есть |
| `factoring_allowed` auto-set при подписании договора | ✅ Работает | `FactoringService.signContract()` |
| POST `/executor/initiate` | ✅ Есть | создаёт договор факторинга |
| POST `/executor/sign` | ✅ Есть | подписание договора |

### Фронтенд ✅

| Компонент | Статус | Файл |
|---|---|---|
| Типы: `MostFactoringStatus`, `IMostClientLimit` | ✅ Есть | `factoringApi.ts` |
| `mostApplicationNumber`, `mostStatus` в `IClaimPayoutResponse` | ✅ Есть | `factoringApi.ts` |
| `getMostLimit()` API + store | ✅ Есть | `factoring.ts`, `organization.ts` |
| `registerMostClient()` API | ✅ Есть | `factoring.ts` |
| Отображение mostStatus в `TransportationHeader.vue` | ✅ Есть | цвет + текст |
| Отображение mostStatus в `TransportationListItem.vue` | ✅ Есть | бейдж |
| Переводы статусов MOST (4 языка) | ✅ Есть | `ru/en/kk/zh.json` |
| Модалки факторинга | ✅ Есть | 4 модалки в ModalContent/ |

---

## 3. Проблемы и что не работает

### КРИТИЧЕСКИЕ

---

#### ❌ ПРОБЛЕМА 1: Нет автоматического включения факторинга после одобрения MOST

**Суть:**
Когда MOST одобряет организацию (`factoring_available: true`), в Coube **ничего не происходит автоматически**. `factoring_allowed` остаётся `false`. Executor не видит кнопку быстрой оплаты.

**Сейчас:**
```
MOST одобрил организацию
          │
          ▼
❌ НИЧЕГО (нет polling по клиентам, нет авто-включения)
          │
          ▼
Кто-то вручную: UPDATE users.organization SET factoring_allowed = true
```

**Нет polling клиентов.** `MostStatusPollingService` опрашивает только заявки (`GET /factoring`), но не статус клиентов (`GET /client`). Никто не следит за тем, одобрил ли MOST организацию.

**Поле `factoring_eligible`** — никогда и нигде не выставляется. Висит в БД мёртвым грузом.

---

#### ❌ ПРОБЛЕМА 2: Нет `MostApiOutboxService` — потеря заявок

**Суть:**
Таблица `factoring.most_api_outbox` создана в БД, но Java-сервис для неё **не реализован**. Если MOST API недоступен в момент:
- подтверждения OTP → `POST /factoring` упадёт → заявка потеряется
- подписания АВР → `PUT /factoring` упадёт → документы не попадут в MOST

WebClient имеет встроенный retry (3 попытки), но если MOST лежит дольше — запрос теряется навсегда.

---

#### ❌ ПРОБЛЕМА 3: Нет кнопки "Подключить быструю оплату"

**Суть:**
Сейчас весь флоу факторинга **встроен в форму перевозки**. Executor узнаёт о факторинге только когда открывает конкретную перевозку. Нет отдельного места где он может:
- Узнать что такое быстрая оплата
- Зарегистрироваться в MOST
- Отслеживать статус одобрения

---

#### ❌ ПРОБЛЕМА 4: Нет блокировки кнопки при нулевом лимите

**Суть:**
Если `limit_amount = null` (организация на скоринге), executor всё равно может нажать "Быстрая оплата" и получить невнятную ошибку от бэкенда. Лимит из MOST нигде не отображается и кнопка не блокируется.

---

### ВЫСОКИЙ ПРИОРИТЕТ

---

#### ⚠️ ПРОБЛЕМА 5: Нет frontend polling — статус не обновляется

**Суть:**
Статус заявки MOST (`new → processing → issued`) обновляется на бэкенде каждые 15 минут, но **фронтенд не перезапрашивает данные**. Executor должен вручную обновить страницу чтобы увидеть что деньги пришли.

---

#### ⚠️ ПРОБЛЕМА 6: Нет UI для статуса REJECTED

**Суть:**
Если MOST отклоняет заявку, в БД ставится статус `REJECTED`, но на экране executor ничего не меняется — нет красного блока, нет уведомления, нет объяснения.

---

#### ⚠️ ПРОБЛЕМА 7: Баг в URL отправки OTP

**Суть:**
В `src/api/factoring.ts` URL содержит двойной сегмент:
```
СЕЙЧАС:   v1/factoring/payout/payouts/{id}/send-otp   ❌
ДОЛЖНО:   v1/factoring/payout/{id}/send-otp           ✅
```
OTP может не отправляться если роутинг на бэке не обработал дубль.

---

#### ⚠️ ПРОБЛЕМА 8: Нет прогресс-бара заявки

**Суть:**
Статус MOST (`new / processing / ready_for_issue / issued`) отображается как текстовый бейдж в шапке перевозки. Нет визуального трекера шагов внутри раздела факторинга.

---

### СРЕДНИЙ ПРИОРИТЕТ

---

#### ℹ️ ПРОБЛЕМА 9: `factoring_eligible` нигде не используется

Поле есть в БД и entity, но никогда не выставляется и не проверяется. Нужно либо использовать, либо убрать чтобы не путать.

#### ℹ️ ПРОБЛЕМА 10: Нет admin-кнопки для ручного включения факторинга

В `coube-admin` страница организации показывает `factoringAllowed` как read-only чип. Нет кнопки toggle для администратора (на случай ручного включения/отключения).

#### ℹ️ ПРОБЛЕМА 11: Нет toast-уведомлений при смене статуса MOST

При polling если статус изменился — нет всплывающего уведомления пользователю.

---

## 4. План доработок

### BACK-1 — Polling клиентов + авто-включение факторинга
**Приоритет: КРИТИЧЕСКИЙ**

Создать `MostClientPollingService`:
```java
// Каждые 30 минут
// Находим организации где most_registered_at IS NOT NULL AND factoring_allowed = false
// Для каждой: GET /client?tax_id={bin}
// Если factoring_available = true → org.setFactoringAllowed(true)
// Уведомить executor через push/WhatsApp: "Быстрая оплата теперь доступна!"
```

Убрать поле `factoring_eligible` — оно не несёт смысла при наличии `factoring_allowed`.

**Файлы:**
- Новый: `factoring/service/MostClientPollingService.java`
- Изменение: `factoring/service/MostStatusPollingService.java` или отдельный сервис

---

### BACK-2 — MostApiOutboxService
**Приоритет: КРИТИЧЕСКИЙ**

Реализовать сервис для таблицы `factoring.most_api_outbox`:
```java
// scheduleOperation(payoutId, "CREATE_APPLICATION" | "UPLOAD_DOCUMENTS", payload)
// processOutbox() — @Scheduled каждую минуту
// Exponential backoff: 1 → 2 → 4 → 8 → 16 мин
// После 5 попыток → FAILED + алерт в логи
```

Переписать вызовы MOST через outbox:
- `confirmPayout()` → вместо прямого `.block()` → `scheduleOperation(CREATE_APPLICATION)`
- `processSignedFactoringActs()` → `scheduleOperation(UPLOAD_DOCUMENTS)`

**Файлы:**
- Новый: `factoring/integration/most/MostApiOutboxService.java`
- Новый: `factoring/entity/MostApiOutbox.java`
- Новый: `factoring/repository/MostApiOutboxRepository.java`
- Изменение: `factoring/service/PayoutFactoringServiceImpl.java`
- Изменение: `factoring/service/FactoringActProcessingService.java`

---

### BACK-3 — Endpoint для регистрации executor в MOST
**Приоритет: КРИТИЧЕСКИЙ**

Добавить в `ExecutorFactoringController`:
```java
POST /api/v1/factoring/executor/register-most
// Вызывает mostClientRegistrationService.registerExecutor(org)
// Возвращает { status: "registered" | "already_registered" | "pending" }
```

Это нужно для кнопки "Подключить быструю оплату" на фронте.

---

### BACK-4 — Toggle factoring в admin панели
**Приоритет: СРЕДНИЙ**

Добавить в `SuperAdminOrganizationController`:
```java
PATCH /api/v1/super-admin/organizations/{id}/factoring
// Body: { factoringAllowed: true | false }
// Для ручного управления администратором
```

---

### FRONT-1 — Страница / секция "Подключить быструю оплату"
**Приоритет: КРИТИЧЕСКИЙ**

Создать отдельную страницу или секцию в профиле организации:

```
┌─────────────────────────────────────────┐
│  Быстрая оплата                         │
│                                         │
│  [Не подключено]                        │
│                                         │
│  Получайте деньги сразу после           │
│  выполнения перевозки, не дожидаясь     │
│  оплаты от заказчика.                   │
│                                         │
│  [Подключить быструю оплату]  ← кнопка  │
└─────────────────────────────────────────┘

После нажатия:
┌─────────────────────────────────────────┐
│  Быстрая оплата                         │
│                                         │
│  ⏳ Заявка на рассмотрении              │
│  Обычно занимает 1-2 рабочих дня        │
│                                         │
│  Мы уведомим вас когда всё будет готово │
└─────────────────────────────────────────┘

После одобрения MOST:
┌─────────────────────────────────────────┐
│  Быстрая оплата                         │
│                                         │
│  ✅ Подключена                          │
│  Доступный лимит: 20 000 000 ₸          │
│                                         │
│  [Подписать договор факторинга]         │
└─────────────────────────────────────────┘
```

**Логика:**
- Нет `most_registered_at` → кнопка "Подключить"
- `most_registered_at` есть, `factoring_allowed = false` → статус "На рассмотрении"
- `factoring_allowed = true`, договор не подписан → кнопка "Подписать договор"
- `factoring_allowed = true`, договор подписан → "Подключена ✅ + лимит"

---

### FRONT-2 — Исправить URL бага OTP
**Приоритет: КРИТИЧЕСКИЙ**

В `src/api/factoring.ts`:
```typescript
// БЫЛО:
return api.post(`v1/factoring/payout/payouts/${id}/send-otp`)
// СТАЛО:
return api.post(`v1/factoring/payout/${id}/send-otp`)
```

---

### FRONT-3 — Блокировка кнопки + отображение лимита
**Приоритет: ВЫСОКИЙ**

В `ExecutorTransportationForm.vue`:
- Загружать лимит через `getMostLimit()` при открытии перевозки с факторингом
- Если `limitAmount = null` → disabled кнопка + текст "Организация проходит проверку"
- Если `limitAmount` есть → показывать "Доступный лимит: X ₸"

---

### FRONT-4 — Frontend polling статуса заявки
**Приоритет: ВЫСОКИЙ**

В `ExecutorTransportationForm.vue`:
```typescript
// При открытии перевозки с активной заявкой MOST:
// setInterval каждые 30 сек если mostStatus in ['new', 'processing', 'ready_for_issue']
// При смене статуса → toast уведомление
// onUnmounted → clearInterval
```

---

### FRONT-5 — UI для статуса REJECTED
**Приоритет: ВЫСОКИЙ**

Если `mostStatus = 'rejected'` или `payoutStatus = 'REJECTED'`:
```
┌─────────────────────────────────────────┐
│ ❌ Заявка на быструю оплату отклонена   │
│                                         │
│ Обратитесь в поддержку для уточнения    │
│ причины отказа.                         │
└─────────────────────────────────────────┘
```

---

### FRONT-6 — Прогресс-бар заявки в MOST
**Приоритет: СРЕДНИЙ**

Компонент `FactoringMostStatus.vue`:
```
[Заявка создана] → [В обработке] → [Готово к выдаче] → [Выплачено]
      ✅                 🔄                  ⏳               ⏳
```

---

### ADMIN-1 — Toggle factoring_allowed в coube-admin
**Приоритет: СРЕДНИЙ**

На странице организации `/companies/[id]` добавить кнопку:
```tsx
<Switch
  isSelected={organization.factoringAllowed}
  onChange={() => toggleFactoring(organization.id)}
>
  Быстрая оплата
</Switch>
```

---

## 5. Порядок реализации

```
BACK-2 (outbox)          BACK-1 (polling клиентов)
     │                          │
     └──────────┬───────────────┘
                │
           BACK-3 (register endpoint)
                │
           FRONT-2 (баг OTP URL) ← можно сразу
                │
           FRONT-1 (страница подключения)
                │
           FRONT-3 (блокировка лимита)
                │
      ┌─────────┴──────────┐
      │                    │
 FRONT-4 (polling)    FRONT-5 (rejected UI)
      │
 FRONT-6 (прогресс-бар)
      │
 BACK-4 + ADMIN-1 (admin toggle)
```

---

## 6. Итоговая таблица проблем

| # | Проблема | Приоритет | Тип | Что сломано |
|---|---|---|---|---|
| 1 | Нет авто-включения факторинга после одобрения MOST | 🔴 Критический | Back | Весь онбординг — вручную |
| 2 | Нет MostApiOutboxService | 🔴 Критический | Back | Потеря заявок при недоступности MOST |
| 3 | Нет кнопки "Подключить быструю оплату" | 🔴 Критический | Front | Пользователь не может сам подключить |
| 4 | Нет блокировки при нулевом лимите | 🔴 Критический | Front | UX ломается, непонятные ошибки |
| 5 | Баг двойного URL в OTP | 🔴 Критический | Front | OTP может не отправляться |
| 6 | Нет frontend polling | 🟠 Высокий | Front | Статус только после перезагрузки |
| 7 | Нет UI для REJECTED | 🟠 Высокий | Front | Executor не знает что заявка отклонена |
| 8 | factoring_eligible нигде не используется | 🟡 Средний | Back | Мусор в БД и entity |
| 9 | Нет admin toggle для factoring_allowed | 🟡 Средний | Admin | Только SQL вручную |
| 10 | Нет прогресс-бара заявки | 🟡 Средний | Front | UX |
| 11 | Нет toast при смене статуса MOST | 🟡 Средний | Front | UX |
