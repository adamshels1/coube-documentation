# Frontend задачи — Интеграция с MOST FinTech API

---

## Текущее состояние фронтенда

### Что реализовано
- **API-клиент** (`src/api/factoring.ts`) — все текущие эндпоинты бэкенда
- **Модалки:**
  - `FactoringInfo` — информация о договоре быстрой оплаты + подпись
  - `AcceptFactoringConfirmation` — подтверждение отклика с суммой факторинга
  - `FactoringPayoutInfo` — данные заявки + скачать PDF + подписать
  - `FactoringPayoutOtp` — ввод OTP-кода из WhatsApp
- **Store** (Pinia `organization.ts`) — `isFactoringAvailable`, `isFactoringContractSigned`
- **Типы** (`factoringApi.ts`) — полные TypeScript-интерфейсы
- **i18n** — переводы на 4 языка (ru, en, kk, zh)
- **Интеграция:**
  - `CargoCost.vue` — бейдж и toggle факторинга при создании заявки (customer)
  - `ExecutorTransportationForm.vue` — полный flow executor-а (подпись договора, payout, OTP)
  - `ApplicationsAddPage.vue` — включение факторинга при создании перевозки (customer)
  - `TransportationHeader.vue` — бейдж "Быстрая оплата"

### Текущий UX-flow

**Customer:**
1. Создание перевозки → toggle "Быстрая оплата" (если доступно) → отправка

**Executor:**
1. Просмотр перевозки с факторингом → "Быстрая оплата" кнопка
2. Если договор не подписан: подпись договора через ЭЦП
3. Если подписан: подтверждение суммы → claim payout → просмотр заявки → OTP → подписание
4. Скачивание подписанного PDF

### Что НЕ реализовано
- Отображение статуса заявки в MOST
- Отображение лимита из MOST
- Статусы MOST (new, processing, ready_for_issue, issued, rejected, closed)
- Уведомления о смене статуса в MOST
- Статус REJECTED в UI
- Прогресс-бар/трекер заявки
- Информация о регистрации организации в MOST

---

## Задачи

### FRONT-1. Обновление TypeScript-интерфейсов

**Приоритет:** Критический (блокирует остальные задачи)

**Описание:**
Добавить новые типы для данных MOST в существующие интерфейсы.

**Что сделать:**

1. Обновить `IClaimPayoutResponse` в `factoringApi.ts`:
```typescript
export interface IClaimPayoutResponse {
  id: string
  requestNumber: string
  status: string
  amount: number
  financingAmount: number
  transportationId: number
  createdAt: string
  confirmedAt: string
  paidAt: string
  // Новые поля MOST
  mostApplicationNumber: string | null
  mostStatus: string | null     // 'new' | 'processing' | 'ready_for_issue' | 'issued' | 'rejected' | 'closed'
  mostLastCheckedAt: string | null
}
```

2. Добавить новый интерфейс для лимита:
```typescript
export interface IMostClientLimit {
  taxId: string
  title: string
  limitAmount: number | null
  available: boolean
}
```

3. Добавить enum для статусов MOST:
```typescript
export enum MostFactoringStatus {
  NEW = 'new',
  PROCESSING = 'processing',
  READY_FOR_ISSUE = 'ready_for_issue',
  ISSUED = 'issued',
  REJECTED = 'rejected',
  CLOSED = 'closed'
}
```

4. Добавить enum для PayoutStatus (дополнить существующий):
```typescript
export enum PayoutStatus {
  INITIATED = 'INITIATED',
  SMS_PENDING = 'SMS_PENDING',
  CONFIRMED = 'CONFIRMED',
  DOCUMENTS_SENT = 'DOCUMENTS_SENT',
  AVR_DOCS_SENT = 'AVR_DOCS_SENT',
  PAID = 'PAID',
  REJECTED = 'REJECTED'  // Новый
}
```

**Файлы:**
- `src/types/interfaces/api/factoringApi.ts`

---

### FRONT-2. Обновление API-клиента

**Приоритет:** Критический

**Описание:**
Добавить новые методы API для работы с данными MOST.

**Что сделать:**

1. Добавить в `src/api/factoring.ts`:
```typescript
executor: {
  // ... существующие методы ...

  // Новый: проверка лимита в MOST
  getMostLimit(): Promise<AxiosResponse<IMostClientLimit>> {
    return api.get('v1/factoring/executor/limit')
  }
},

payout: {
  // ... существующие методы ...

  // Новый: получить статус в MOST
  getMostStatus(id: string): Promise<AxiosResponse<IMostStatusResponse>> {
    return api.get(`v1/factoring/payout/${id}/most-status`)
  }
}
```

**Файлы:**
- `src/api/factoring.ts`

---

### FRONT-3. Компонент статуса заявки MOST

**Приоритет:** Высокий

**Описание:**
Создать компонент для отображения текущего статуса заявки в MOST с визуальным прогрессом.

**Что сделать:**

1. Создать компонент `FactoringMostStatus.vue`:
   - Props: `mostStatus: string | null`, `mostApplicationNumber: string | null`, `payoutStatus: string`
   - Отображение:
     - Номер заявки MOST (если есть): `№ CUB-123-20251022`
     - Статус-бар с этапами:
       ```
       [Заявка создана] → [В обработке] → [Готово к выдаче] → [Выдано]
       ```
     - Иконка + текст статуса + цвет:
       - `new` → желтый, "Новая заявка"
       - `processing` → синий, "В обработке"
       - `ready_for_issue` → зелёный, "Готово к выдаче"
       - `issued` → зелёный, "Оплата произведена"
       - `rejected` → красный, "Заявка отклонена"
       - `closed` → серый, "Закрыта"
     - Если `mostStatus == null` и payout существует — показать "Отправка в MOST..."
     - Дата последней проверки (если есть)

2. Стили: использовать существующую дизайн-систему (BaseIcon, цвета из SCSS-переменных)

**Файлы:**
- Новый: `src/components/TransportationForm/FactoringMostStatus.vue`

---

### FRONT-4. Интеграция статуса MOST в форму executor-а

**Приоритет:** Высокий

**Описание:**
Встроить компонент статуса MOST в `ExecutorTransportationForm.vue`.

**Что сделать:**

1. В `ExecutorTransportationForm.vue`:
   - Добавить `ref` для MOST-данных:
     ```typescript
     const mostStatus = ref<string | null>(null)
     const mostApplicationNumber = ref<string | null>(null)
     ```
   - Обновить `getFactoringPayout()` — парсить новые поля `mostApplicationNumber`, `mostStatus` из ответа
   - Добавить компонент `FactoringMostStatus` в template после блока заявки на быструю оплату
   - Показывать когда `factoringPayoutInfo` существует и `status !== 'INITIATED'`

2. Авто-обновление статуса:
   - Polling каждые 30 секунд если статус `mostStatus` в активных состояниях (`new`, `processing`, `ready_for_issue`)
   - Остановить polling при `issued`, `rejected`, `closed`
   - Использовать `setInterval` / `onUnmounted` cleanup

3. Обработка статуса `REJECTED`:
   - Показать красный блок с сообщением: "Заявка на быструю оплату отклонена"
   - Скрыть кнопки подписания/подтверждения
   - Опционально: кнопка "Попробовать снова" (если бэкенд позволит)

**Файлы:**
- Изменение: `src/components/TransportationForm/ExecutorTransportationForm.vue`

---

### FRONT-5. Проверка лимита MOST перед созданием payout

**Приоритет:** Высокий

**Описание:**
Перед нажатием "Быстрая оплата" executor должен видеть информацию о лимите, и система должна блокировать создание если лимит не одобрен.

**Что сделать:**

1. В `ExecutorTransportationForm.vue`:
   - При загрузке перевозки с `isFactoringAllowed` — вызвать `api.factoring.executor.getMostLimit()`
   - Сохранить в `mostLimit: ref<IMostClientLimit | null>(null)`

2. UI-логика:
   - Если `mostLimit.available === true` и `mostLimit.limitAmount !== null`:
     - Показать "Доступный лимит: {limitAmount} ₸"
     - Разрешить кнопку "Быстрая оплата"
   - Если `mostLimit.available === false` или `limitAmount === null`:
     - Показать предупреждение: "Ваша организация проходит проверку. Быстрая оплата будет доступна после одобрения."
     - Заблокировать кнопку "Быстрая оплата" (disabled)
   - Если ошибка вызова API:
     - Не блокировать (fallback на текущее поведение)
     - Логировать ошибку

3. Graceful degradation — если бэкенд ещё не реализовал endpoint `/limit`:
   - Обработать 404 → не показывать информацию о лимите
   - Не блокировать текущий функционал

**Файлы:**
- Изменение: `src/components/TransportationForm/ExecutorTransportationForm.vue`

---

### FRONT-6. Обновление i18n-переводов

**Приоритет:** Средний

**Описание:**
Добавить переводы для всех новых элементов UI, связанных с MOST.

**Что сделать:**

1. Добавить ключи во все 4 локали (ru, en, kk, zh):

```json
{
  "factoring": {
    "most": {
      "status": {
        "new": "Новая заявка",
        "processing": "В обработке",
        "ready_for_issue": "Готово к выдаче",
        "issued": "Оплата произведена",
        "rejected": "Заявка отклонена",
        "closed": "Закрыта",
        "sending": "Отправка в MOST..."
      },
      "applicationNumber": "Номер заявки MOST",
      "lastChecked": "Последняя проверка",
      "limit": {
        "available": "Доступный лимит",
        "checking": "Проверка организации...",
        "notAvailable": "Ваша организация проходит проверку. Быстрая оплата будет доступна после одобрения.",
        "exceeded": "Сумма превышает доступный лимит"
      },
      "rejected": {
        "title": "Заявка на быструю оплату отклонена",
        "description": "Обратитесь в поддержку для уточнения причины"
      },
      "paid": {
        "title": "Оплата произведена",
        "description": "Средства переведены на ваш счёт"
      }
    }
  }
}
```

2. Файлы для обновления:
   - `public/locales/ru.json`
   - `public/locales/en.json`
   - `public/locales/kk.json`
   - `public/locales/zh.json`

3. После добавления запустить `npm run i18n:check` для проверки

**Файлы:**
- `public/locales/ru.json`
- `public/locales/en.json`
- `public/locales/kk.json`
- `public/locales/zh.json`

---

### FRONT-7. Обновление Pinia store

**Приоритет:** Средний

**Описание:**
Расширить organization store для хранения данных MOST.

**Что сделать:**

1. В `src/store/organization.ts`:
   - Добавить state:
     ```typescript
     const mostClientLimit = ref<IMostClientLimit | null>(null)
     const mostLimitLoading = ref(false)
     ```
   - Добавить action:
     ```typescript
     async function checkMostLimit() {
       mostLimitLoading.value = true
       try {
         const { data } = await api.factoring.executor.getMostLimit()
         mostClientLimit.value = data
       } catch (e) {
         mostClientLimit.value = null
       } finally {
         mostLimitLoading.value = false
       }
     }
     ```
   - Экспортировать новые ref и action

**Файлы:**
- Изменение: `src/store/organization.ts`

---

### FRONT-8. Уведомления о смене статуса MOST

**Приоритет:** Низкий

**Описание:**
Показывать toast-уведомления при изменении статуса заявки MOST во время polling.

**Что сделать:**

1. В `ExecutorTransportationForm.vue`:
   - При polling если статус изменился:
     - `processing` → toast info: "Ваша заявка принята в обработку"
     - `ready_for_issue` → toast success: "Заявка одобрена, ожидайте выплату"
     - `issued` → toast success: "Оплата произведена! Средства переведены на ваш счёт"
     - `rejected` → toast error: "Заявка отклонена. Обратитесь в поддержку"

2. Использовать существующий toast-сервис (как в текущем коде — `showSuccessToast`, `showErrorToast`)

**Файлы:**
- Изменение: `src/components/TransportationForm/ExecutorTransportationForm.vue`

---

### FRONT-9. Исправление существующих UI-проблем

**Приоритет:** Средний

**Описание:**
Исправить найденные проблемы в текущей реализации.

**Что сделать:**

1. **FactoringPayoutOtpHeader.vue** — пустой компонент, добавить заголовок:
   - Текст: `$t('factoring.info.payout.enter')` — "Введите код, чтобы подписать документ ПЭП"

2. **Баг в sendOTP URL** — в `src/api/factoring.ts`:
   - Текущий: `v1/factoring/payout/payouts/${id}/send-otp` (двойное `payout/payouts`)
   - Правильный: `v1/factoring/payout/${id}/send-otp`

3. **commission percentage** (`IFactoringCost.commissionPercentage`) — хранится но не отображается пользователю. Добавить в карточку факторинга:
   - "Комиссия: {commissionPercentage}%"

4. **Страховка** — ссылка "Условия страхования" показывает toast "раздел в разработке":
   - Если раздел не планируется — убрать ссылку
   - Если планируется — оставить как есть

**Файлы:**
- Изменение: `src/components/ModalContent/FactoringPayoutOtp/FactoringPayoutOtpHeader.vue`
- Изменение: `src/api/factoring.ts`
- Изменение: `src/components/TransportationForm/ExecutorTransportationForm.vue`

---

## Порядок выполнения

```
FRONT-1 (типы)
    ↓
FRONT-2 (API-клиент)
    ↓
 ┌───────────────────────────────┐
 ↓                ↓              ↓
FRONT-3 (статус) FRONT-7 (store) FRONT-9 (фиксы)
 ↓                ↓
FRONT-4 (интеграция)
 ↓
FRONT-5 (проверка лимита)
 ↓
FRONT-6 (i18n)
 ↓
FRONT-8 (уведомления)
```

---

## Зависимости от бэкенда

| Frontend задача | Зависит от Backend задачи | Описание |
|----------------|---------------------------|----------|
| FRONT-1, FRONT-2 | BACK-4, BACK-9 | Новые поля в ответах API |
| FRONT-3, FRONT-4 | BACK-6 | Статус MOST в данных payout |
| FRONT-5 | BACK-3 | Эндпоинт `/executor/limit` |
| FRONT-8 | BACK-6 | Корректные статусы для polling |
| FRONT-9 (баг sendOTP) | — | Можно фиксить независимо |

---

## Маппинг: текущий UI → новый UI

| Текущее состояние | Новое состояние |
|-------------------|-----------------|
| Нет информации о статусе MOST | Прогресс-бар со статусами: new → processing → issued |
| Нет лимита | Показ доступного лимита, блокировка если нет |
| Только PAID/нет PAID | + REJECTED статус с красным блоком |
| Нет номера заявки MOST | Отображение `CUB-XXX-XXXXXXXX` |
| Нет автообновления статуса | Polling каждые 30 сек для активных заявок |
| Баг двойного `/payout/payouts/` в OTP URL | Исправленный URL |
| Пустой header в OTP-модалке | Заголовок "Введите код..." |
