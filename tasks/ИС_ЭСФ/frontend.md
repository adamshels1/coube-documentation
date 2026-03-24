# ИС ЭСФ — Frontend задачи

## Текущее состояние

| Что есть | Где |
|----------|-----|
| `api/invoice.ts` — полный клиент для счетов | `src/api/invoice.ts` |
| `src/views/Finance/` — раздел финансов | уже есть |
| Статусная модель документов в UI | уже есть |
| Кнопки действий над счетами (подписать, отклонить) | уже есть |

**Что нужно добавить:** кнопка "Выставить ЭСФ", отображение статуса ЭСФ и регистрационного номера в интерфейсе счёта.

---

## TASK-ESF-FE-1: Добавить ESF API методы

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-ESF-BE-7

### Что сделать

Добавить в `src/api/invoice.ts` (или создать `src/api/esf.ts`):

```typescript
// src/api/esf.ts

import { apiClient } from './client'

export interface EsfStatusResponse {
  invoiceId: number
  status: 'NOT_SENT' | 'SENDING' | 'SENT' | 'DELIVERED' | 'DECLINED' | 'CANCELLED'
  registrationNumber: string | null
  sentAt: string | null
  lastSyncAt: string | null
  errorCode: string | null
  errorMessage: string | null
}

// Отправить ЭСФ
export const sendEsf = (invoiceId: number) =>
  apiClient.post<EsfStatusResponse>(`/v1/esf/invoices/${invoiceId}/send`)

// Получить статус ЭСФ
export const getEsfStatus = (invoiceId: number) =>
  apiClient.get<EsfStatusResponse>(`/v1/esf/invoices/${invoiceId}/status`)

// Отозвать ЭСФ
export const cancelEsf = (invoiceId: number) =>
  apiClient.post<EsfStatusResponse>(`/v1/esf/invoices/${invoiceId}/cancel`)
```

### Критерии готовности
- [ ] Все три метода реализованы
- [ ] Типизация статусов через union type
- [ ] Обработка ошибок (try/catch в вызывающем коде)

---

## TASK-ESF-FE-2: Компонент EsfStatusBadge

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-ESF-FE-1

### Что сделать

Бейдж-компонент для отображения статуса ЭСФ:

```vue
<!-- src/components/Esf/EsfStatusBadge.vue -->
<template>
  <span :class="['esf-badge', `esf-badge--${statusClass}`]">
    {{ statusLabel }}
  </span>
</template>

<script setup lang="ts">
type EsfStatus = 'NOT_SENT' | 'SENDING' | 'SENT' | 'DELIVERED' | 'DECLINED' | 'CANCELLED'

const props = defineProps<{ status: EsfStatus | null }>()

const statusConfig: Record<EsfStatus, { label: string; class: string }> = {
  NOT_SENT:  { label: 'ЭСФ не выставлен', class: 'gray' },
  SENDING:   { label: 'Отправляется...',  class: 'blue' },
  SENT:      { label: 'Отправлен',        class: 'blue' },
  DELIVERED: { label: 'ЭСФ принят',       class: 'green' },
  DECLINED:  { label: 'Отклонён ИС ЭСФ', class: 'red' },
  CANCELLED: { label: 'Отозван',          class: 'gray' },
}

const statusClass = computed(() => statusConfig[props.status ?? 'NOT_SENT'].class)
const statusLabel = computed(() => statusConfig[props.status ?? 'NOT_SENT'].label)
</script>
```

### Критерии готовности
- [ ] Все 6 статусов с правильными цветами
- [ ] Работает с `null` (когда ЭСФ ещё не создавался)

---

## TASK-ESF-FE-3: ESF блок в детальном просмотре счёта

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-ESF-FE-1, TASK-ESF-FE-2, TASK-VAT-BE-5

### Что сделать

В компоненте просмотра счёта (в `src/views/Finance/` или `Documents/`) добавить блок ЭСФ **после блока стоимости и статуса**:

```vue
<!-- Блок ЭСФ — виден только исполнителю -->
<div class="esf-block" v-if="isExecutor">
  <h4>Электронный счёт-фактура (ЭСФ)</h4>

  <!-- Статус -->
  <div class="esf-status-row">
    <EsfStatusBadge :status="invoice.esfStatus?.status ?? null" />

    <!-- Рег. номер если есть -->
    <span v-if="invoice.esfStatus?.registrationNumber" class="esf-reg-number">
      № {{ invoice.esfStatus.registrationNumber }}
    </span>
  </div>

  <!-- Ошибка если отклонён -->
  <div v-if="invoice.esfStatus?.status === 'DECLINED'" class="esf-error">
    <span>{{ invoice.esfStatus.errorMessage }}</span>
    <a href="https://esf.gov.kz" target="_blank">Открыть ИС ЭСФ →</a>
  </div>

  <!-- Кнопки действий -->
  <div class="esf-actions">
    <!-- Выставить ЭСФ — только если счёт подписан и ЭСФ ещё не отправлен/принят -->
    <button
      v-if="canSendEsf"
      @click="handleSendEsf"
      :loading="isSending"
      class="btn-primary"
    >
      Выставить ЭСФ
    </button>

    <!-- Повторить — если отклонён -->
    <button
      v-if="invoice.esfStatus?.status === 'DECLINED'"
      @click="handleSendEsf"
      :loading="isSending"
      class="btn-secondary"
    >
      Повторить отправку
    </button>

    <!-- Отозвать — если принят -->
    <button
      v-if="invoice.esfStatus?.status === 'DELIVERED'"
      @click="handleCancelEsf"
      class="btn-danger"
    >
      Отозвать ЭСФ
    </button>
  </div>
</div>
```

**Вычисляемые условия:**
```typescript
// Кнопка "Выставить ЭСФ" доступна если:
const canSendEsf = computed(() => {
  const esfStatus = invoice.value.esfStatus?.status
  const invoiceStatus = invoice.value.status

  return invoiceStatus === 'SIGNED_BY_CUSTOMER' &&
    (!esfStatus || esfStatus === 'NOT_SENT' || esfStatus === 'DECLINED' || esfStatus === 'CANCELLED')
})
```

**Обработчики:**
```typescript
const handleSendEsf = async () => {
  isSending.value = true
  try {
    const result = await sendEsf(invoice.value.id)
    invoice.value.esfStatus = result.data
    // toast: "ЭСФ успешно отправлен" или "Ошибка отправки"
  } catch (e) {
    // toast: "Не удалось отправить ЭСФ"
  } finally {
    isSending.value = false
  }
}
```

### Критерии готовности
- [ ] Блок виден только исполнителю (не заказчику)
- [ ] Кнопка "Выставить ЭСФ" активна только для подписанных счетов
- [ ] Рег. номер отображается после успешной отправки
- [ ] Ошибка с сообщением показывается при статусе DECLINED
- [ ] Состояние loading на кнопке во время отправки
- [ ] Подтверждение перед "Отозвать ЭСФ"

---

## TASK-ESF-FE-4: ESF статус в списке счетов

**Приоритет:** 🟡 Средний
**Зависит от:** TASK-ESF-FE-2

### Что сделать

В таблице/списке счетов добавить колонку ESF статуса:

```vue
<!-- В строке таблицы счетов -->
<td>
  <EsfStatusBadge :status="invoice.esfStatus?.status ?? null" />
</td>
```

Опционально — tooltip с рег. номером при наведении на бейдж.

### Критерии готовности
- [ ] Колонка "ЭСФ" в списке счетов (только для исполнителя)
- [ ] Бейдж кликабелен — открывает детали счёта

---

## TASK-ESF-FE-5: i18n переводы для ESF блока

**Приоритет:** 🟡 Средний

### Что сделать

```json
// locales/ru.json
{
  "esf": {
    "title": "Электронный счёт-фактура (ЭСФ)",
    "status": {
      "NOT_SENT": "ЭСФ не выставлен",
      "SENDING": "Отправляется...",
      "SENT": "Отправлен",
      "DELIVERED": "ЭСФ принят КГД",
      "DECLINED": "Отклонён ИС ЭСФ",
      "CANCELLED": "Отозван"
    },
    "actions": {
      "send": "Выставить ЭСФ",
      "resend": "Повторить отправку",
      "cancel": "Отозвать ЭСФ",
      "cancelConfirm": "Вы уверены, что хотите отозвать ЭСФ? Это действие необратимо."
    },
    "registrationNumber": "Рег. номер ЭСФ",
    "errorHint": "Открыть ИС ЭСФ для подробностей"
  }
}
```

### Критерии готовности
- [ ] ru, kk языки заполнены полностью
- [ ] `npm run i18n:check` без ошибок
