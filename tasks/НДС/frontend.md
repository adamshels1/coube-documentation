# НДС — Frontend задачи

## Текущее состояние

| Что есть | Где |
|----------|-----|
| `ITransportation.isNdsIncluded: boolean` | `types/interfaces/transportation.ts` |
| `api/invoice.ts` — полный API клиент для счетов | `src/api/invoice.ts` |
| Pinia store заявок | `src/store/transportation.ts` |
| Разделы Finance/ и Transportations/ | `src/views/` |
| InvoiceResponse с VAT полями | уже приходит с бэка |

**Проблема:** поле `isNdsIncluded` есть в интерфейсе, но нет компонента для управления НДС, нет визуального расчёта, нет отображения разбивки сумм.

---

## TASK-VAT-FE-1: Компонент VatCalculator

**Приоритет:** 🔴 Критический

### Что сделать

Создать переиспользуемый компонент `src/components/VatCalculator/VatCalculator.vue`:

```
Стоимость перевозки
────────────────────────
Сумма  [__________] тг

НДС
  ○ Без НДС
  ● НДС 16%

  [если НДС 16% выбран:]
  Режим расчёта
    ● Добавить НДС к сумме
    ○ Выделить НДС из суммы

────────────────────────
┌──────────────────────┐
│ Расчёт стоимости     │
│ Без НДС   100 000 тг │
│ НДС 16%    16 000 тг │
│ ──────────────────── │
│ ИТОГО     116 000 тг │
└──────────────────────┘
```

**Props:**
```typescript
interface VatCalculatorProps {
  modelValue: {
    inputAmount: number | null
    vatEnabled: boolean
    vatMode: 'ADD' | 'EXTRACT' | null
  }
  currency?: string  // default 'тг'
  disabled?: boolean
}
```

**Emits:**
```typescript
emit('update:modelValue', payload)
emit('calculated', { amountNet, vatAmount, amountGross, vatRate })
```

**Логика расчёта (клиентская, для instant preview):**
```typescript
// composable: src/composables/useVatCalculation.ts

export function useVatCalculation() {
  const VAT_RATE = 16

  function calculate(inputAmount: number, vatEnabled: boolean, vatMode: 'ADD' | 'EXTRACT' | null) {
    if (!vatEnabled || !vatMode || !inputAmount) {
      return { amountNet: inputAmount, vatAmount: 0, amountGross: inputAmount, vatRate: 0 }
    }

    if (vatMode === 'ADD') {
      const vatAmount = round(inputAmount * VAT_RATE / 100)
      return { amountNet: inputAmount, vatAmount, amountGross: inputAmount + vatAmount, vatRate: VAT_RATE }
    }

    if (vatMode === 'EXTRACT') {
      const amountNet = round(inputAmount / 1.16)
      const vatAmount = round(inputAmount - amountNet)
      return { amountNet, vatAmount, amountGross: inputAmount, vatRate: VAT_RATE }
    }
  }

  function round(value: number): number {
    return Math.round(value * 100) / 100
  }

  return { calculate }
}
```

**UX детали:**
- При смене режима НДС — пересчёт мгновенный (watchEffect)
- Блок "Режим расчёта" появляется только если выбрано "НДС 16%"
- Итоговая карточка всегда видна (показывает 0 НДС если выключен)
- Поле суммы — числовой ввод с форматированием (разделитель тысяч)
- Подсказки (tooltip ⓘ):
  - "Добавить НДС": "НДС будет начислен сверху на указанную сумму"
  - "Выделить НДС": "Система выделит НДС из указанной суммы"

### Критерии готовности
- [ ] Компонент работает автономно (не зависит от конкретной формы)
- [ ] Real-time пересчёт без задержки
- [ ] ADD: 100 000 → net=100 000, vat=16 000, gross=116 000
- [ ] EXTRACT: 116 000 → net=100 000, vat=16 000, gross=116 000
- [ ] Без НДС: показывает "Без НДС" в карточке
- [ ] Адаптивный (мобильный вид)

---

## TASK-VAT-FE-2: Интеграция VatCalculator в форму создания заявки

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-FE-1, TASK-VAT-BE-3

### Что сделать

Найти форму создания/редактирования заявки в `src/views/Transportations/` или `src/views/Applications/` и встроить компонент.

**Обновить интерфейс:**
```typescript
// types/interfaces/transportation.ts
export interface ITransportation {
  // ... существующие поля

  // Удалить устаревшее:
  // isNdsIncluded: boolean  ← заменить на новые

  // Добавить:
  vatEnabled: boolean
  vatMode: 'ADD' | 'EXTRACT' | null
  vatRate: number | null
  amountNet: number | null
  vatAmount: number | null
  amountGross: number | null
  inputAmount: number | null  // то что ввёл пользователь
}
```

**Обновить Pinia store** (`store/transportation.ts`):
```typescript
// В createTransportation() / updateTransportation()
const payload = {
  ...formData,
  vatEnabled: form.vatEnabled,
  vatMode: form.vatMode,
  inputAmount: form.inputAmount,
  // НЕ отправлять расчётные поля — они считаются на бэке
}
```

**В форме:**
```html
<!-- В блоке стоимости перевозки -->
<VatCalculator
  v-model="form.vatData"
  @calculated="onVatCalculated"
/>
```

### Критерии готовности
- [ ] Форма отправляет vatEnabled, vatMode, inputAmount на бэк
- [ ] После сохранения получаем amountNet, vatAmount, amountGross в ответе
- [ ] Пересчёт происходит в реальном времени в UI

---

## TASK-VAT-FE-3: Отображение VAT в деталях заявки

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-3

### Что сделать

В просмотре заявки (транспортировки) добавить блок стоимости с разбивкой НДС:

```html
<!-- Компонент src/components/TransportationCostBlock.vue -->
<div class="cost-block">
  <template v-if="transportation.vatEnabled">
    <div class="cost-row">
      <span>Сумма без НДС</span>
      <span>{{ formatMoney(transportation.amountNet) }} тг</span>
    </div>
    <div class="cost-row vat">
      <span>НДС {{ transportation.vatRate }}%</span>
      <span>{{ formatMoney(transportation.vatAmount) }} тг</span>
    </div>
    <div class="cost-row total">
      <span>ИТОГО</span>
      <span>{{ formatMoney(transportation.amountGross) }} тг</span>
    </div>
  </template>
  <template v-else>
    <div class="cost-row">
      <span>Стоимость</span>
      <span>{{ formatMoney(transportation.amountNet) }} тг</span>
    </div>
    <div class="cost-row no-vat">
      <span class="badge">Без НДС</span>
    </div>
  </template>
</div>
```

### Критерии готовности
- [ ] С НДС: три строки + значок "НДС 16%"
- [ ] Без НДС: одна строка + бейдж "Без НДС"
- [ ] Суммы форматированы (100 000, не 100000)

---

## TASK-VAT-FE-4: Отображение VAT в финансовых документах (Счёт, АВР)

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-5

### Что сделать

В `src/views/Finance/` (или Documents/) в компонентах просмотра Invoice и Act:

**Для Invoice:**
```html
<!-- Итоговый блок счёта -->
<div class="invoice-totals">
  <div class="row">
    <span>Сумма без НДС</span>
    <span>{{ formatMoney(invoice.totalAmountWithoutVat) }} тг</span>
  </div>
  <div class="row" v-if="invoice.totalVatAmount > 0">
    <span>НДС 16%</span>
    <span>{{ formatMoney(invoice.totalVatAmount) }} тг</span>
  </div>
  <div class="row" v-else>
    <span>НДС</span>
    <span class="badge">Без НДС</span>
  </div>
  <div class="row total">
    <strong>ИТОГО к оплате</strong>
    <strong>{{ formatMoney(invoice.totalAmountWithVat) }} тг</strong>
  </div>
</div>
```

**Аналогично для Act (АВР).**

### Критерии готовности
- [ ] Invoice список: отображает totalAmountWithVat как основную сумму
- [ ] Invoice детали: три строки разбивки
- [ ] Act детали: аналогичная разбивка
- [ ] Смешанный случай (часть заявок с НДС, часть без) — суммы корректны

---

## TASK-VAT-FE-5: i18n переводы для VAT блока

**Приоритет:** 🟡 Средний
**Зависит от:** TASK-VAT-FE-1

### Что сделать

Добавить ключи в `src/locales/ru.json`, `en.json`, `kk.json`:

```json
{
  "vat": {
    "title": "НДС",
    "withoutVat": "Без НДС",
    "vatRate": "НДС {rate}%",
    "addMode": "Добавить НДС к сумме",
    "extractMode": "Выделить НДС из суммы",
    "addModeHint": "НДС будет начислен сверху на указанную сумму",
    "extractModeHint": "Система выделит НДС из указанной суммы",
    "amountNet": "Сумма без НДС",
    "vatAmount": "Сумма НДС",
    "amountGross": "Итого с НДС",
    "total": "ИТОГО к оплате"
  }
}
```

Запустить `npm run i18n:check` после добавления.

### Критерии готовности
- [ ] Все 4 языка (ru, en, kk, zh) заполнены хотя бы для ru и kk
- [ ] Нет хардкода строк в компонентах
