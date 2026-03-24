# НДС — Mobile задачи

## Текущее состояние

| Что есть | Где |
|----------|-----|
| `OrderScreen.tsx` | экран заявки для исполнителя |
| `ExecutorOrderScreen.tsx` | экран заявки исполнителя |
| `FinanceScreen.tsx` | финансовый экран |
| `DocumentsScreen.tsx` | документы |
| `InvoiceSentScreen.tsx` | отправка счёта |

**Роли в мобилке:**
- **Перевозчик (Executor)** — создаёт/принимает заявки, видит документы
- **Заказчик (Customer)** — размещает заказы, подтверждает

---

## TASK-VAT-MOB-1: Добавить VAT блок в форму создания/редактирования заявки

**Приоритет:** 🔴 Критический

### Что сделать

В мобильном приложении заявки создаются через форму. Нужно добавить блок НДС.

**Компонент `src/components/VatCalculatorMobile.tsx`:**

```tsx
interface VatCalculatorProps {
  inputAmount: number | null;
  vatEnabled: boolean;
  vatMode: 'ADD' | 'EXTRACT' | null;
  onChange: (data: {
    inputAmount: number | null;
    vatEnabled: boolean;
    vatMode: 'ADD' | 'EXTRACT' | null;
    // расчётные:
    amountNet: number;
    vatAmount: number;
    amountGross: number;
  }) => void;
}
```

**Визуальная структура (React Native):**
```tsx
<View style={styles.vatBlock}>
  <Text style={styles.label}>НДС</Text>

  {/* Переключатель */}
  <View style={styles.radioGroup}>
    <RadioButton
      label="Без НДС"
      selected={!vatEnabled}
      onPress={() => setVatEnabled(false)}
    />
    <RadioButton
      label="НДС 16%"
      selected={vatEnabled}
      onPress={() => setVatEnabled(true)}
    />
  </View>

  {/* Режим — показывается только если НДС включен */}
  {vatEnabled && (
    <View style={styles.modeGroup}>
      <RadioButton
        label="Добавить НДС к сумме"
        selected={vatMode === 'ADD'}
        onPress={() => setVatMode('ADD')}
      />
      <RadioButton
        label="Выделить НДС из суммы"
        selected={vatMode === 'EXTRACT'}
        onPress={() => setVatMode('EXTRACT')}
      />
    </View>
  )}

  {/* Итоговая карточка */}
  <VatSummaryCard
    amountNet={calculated.amountNet}
    vatAmount={calculated.vatAmount}
    amountGross={calculated.amountGross}
    vatEnabled={vatEnabled}
  />
</View>
```

**Логика расчёта (аналогично фронту):**
```typescript
// utils/vatCalculation.ts (переиспользовать или дублировать)
export function calculateVat(
  inputAmount: number,
  vatEnabled: boolean,
  vatMode: 'ADD' | 'EXTRACT' | null
) {
  if (!vatEnabled || !vatMode) {
    return { amountNet: inputAmount, vatAmount: 0, amountGross: inputAmount, vatRate: 0 };
  }
  if (vatMode === 'ADD') {
    const vatAmount = Math.round(inputAmount * 16) / 100;
    return { amountNet: inputAmount, vatAmount, amountGross: inputAmount + vatAmount, vatRate: 16 };
  }
  // EXTRACT
  const amountNet = Math.round((inputAmount / 1.16) * 100) / 100;
  const vatAmount = Math.round((inputAmount - amountNet) * 100) / 100;
  return { amountNet, vatAmount, amountGross: inputAmount, vatRate: 16 };
}
```

### Критерии готовности
- [ ] Компонент добавлен в форму заявки
- [ ] Переключатель НДС работает
- [ ] Режим расчёта появляется при включении НДС
- [ ] Пересчёт мгновенный при изменении суммы/режима
- [ ] Данные отправляются на бэк: `vatEnabled`, `vatMode`, `inputAmount`

---

## TASK-VAT-MOB-2: Отображение VAT в деталях заявки

**Приоритет:** 🔴 Критический
**Зависит от:** TASK-VAT-BE-2 (бэк возвращает поля)

### Что сделать

В `OrderScreen.tsx` / `ExecutorOrderScreen.tsx` обновить блок стоимости:

```tsx
// Компонент CostBlock
const CostBlock = ({ transportation }) => {
  if (transportation.vatEnabled) {
    return (
      <View style={styles.costCard}>
        <CostRow label="Сумма без НДС" value={transportation.amountNet} />
        <CostRow label={`НДС ${transportation.vatRate}%`} value={transportation.vatAmount} />
        <View style={styles.divider} />
        <CostRow label="ИТОГО" value={transportation.amountGross} bold />
      </View>
    );
  }
  return (
    <View style={styles.costCard}>
      <CostRow label="Стоимость" value={transportation.amountNet} />
      <Text style={styles.noVatBadge}>Без НДС</Text>
    </View>
  );
};
```

### Критерии готовности
- [ ] С НДС: три строки (net, vat, gross)
- [ ] Без НДС: одна строка + бейдж
- [ ] Суммы с форматированием тысяч

---

## TASK-VAT-MOB-3: Отображение VAT в финансовых документах

**Приоритет:** 🟡 Средний
**Зависит от:** TASK-VAT-BE-5

### Что сделать

В `FinanceScreen.tsx` и `DocumentsScreen.tsx` для Invoice и Act:

```tsx
// В карточке счёта в списке
<InvoiceCard
  invoiceNumber={invoice.invoiceNumber}
  totalWithVat={invoice.totalAmountWithVat}   // главная сумма
  vatAmount={invoice.totalVatAmount}
  isVat={invoice.totalVatAmount > 0}
/>
```

**В детальном просмотре счёта:**
```tsx
<View style={styles.invoiceTotals}>
  <TotalRow label="Сумма без НДС" value={invoice.totalAmountWithoutVat} />
  {invoice.totalVatAmount > 0 ? (
    <TotalRow label="НДС 16%" value={invoice.totalVatAmount} />
  ) : (
    <Badge text="Без НДС" />
  )}
  <Divider />
  <TotalRow label="ИТОГО к оплате" value={invoice.totalAmountWithVat} bold />
</View>
```

### Критерии готовности
- [ ] Список счетов: отображает totalAmountWithVat
- [ ] Детали счёта: разбивка по строкам
- [ ] Детали АВР: аналогичная разбивка
