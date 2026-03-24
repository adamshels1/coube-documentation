# ИС ЭСФ — Mobile задачи

## Решение: только отображение, без отправки

Отправка ЭСФ в ИС ЭСФ — **только с веба**. Это сложная операция с ЭЦП и требует стабильного соединения. В мобильном приложении реализуем только:
- Отображение статуса ЭСФ для уже выставленных счетов
- Уведомление когда ЭСФ был отклонён

---

## TASK-ESF-MOB-1: Отображение ESF статуса в деталях счёта

**Приоритет:** 🟡 Средний
**Зависит от:** TASK-ESF-BE-7

### Что сделать

В `DocumentsScreen.tsx` или экране деталей Invoice:

```tsx
// components/EsfStatusBadge.tsx
type EsfStatus = 'NOT_SENT' | 'SENDING' | 'SENT' | 'DELIVERED' | 'DECLINED' | 'CANCELLED'

const ESF_STATUS_CONFIG = {
  NOT_SENT:  { label: 'ЭСФ не выставлен', color: '#9CA3AF' },
  SENDING:   { label: 'Отправляется...',  color: '#3B82F6' },
  SENT:      { label: 'Отправлен',        color: '#3B82F6' },
  DELIVERED: { label: 'ЭСФ принят КГД',   color: '#10B981' },
  DECLINED:  { label: 'Отклонён ИС ЭСФ', color: '#EF4444' },
  CANCELLED: { label: 'Отозван',          color: '#9CA3AF' },
}

const EsfStatusBadge = ({ status }: { status: EsfStatus | null }) => {
  const config = ESF_STATUS_CONFIG[status ?? 'NOT_SENT']
  return (
    <View style={[styles.badge, { backgroundColor: config.color + '20' }]}>
      <Text style={[styles.badgeText, { color: config.color }]}>
        {config.label}
      </Text>
    </View>
  )
}

// В деталях счёта (только для исполнителя):
{isExecutor && (
  <View style={styles.esfSection}>
    <Text style={styles.sectionTitle}>ЭСФ</Text>
    <EsfStatusBadge status={invoice.esfStatus?.status ?? null} />

    {invoice.esfStatus?.registrationNumber && (
      <Text style={styles.regNumber}>
        № {invoice.esfStatus.registrationNumber}
      </Text>
    )}

    {invoice.esfStatus?.status === 'DECLINED' && (
      <View style={styles.errorBlock}>
        <Text style={styles.errorText}>
          {invoice.esfStatus.errorMessage}
        </Text>
        <Text style={styles.errorHint}>
          Для повторной отправки откройте веб-версию COUBE
        </Text>
      </View>
    )}
  </View>
)}
```

### Критерии готовности
- [ ] Статус ЭСФ виден в деталях счёта (только исполнитель)
- [ ] Рег. номер отображается при DELIVERED
- [ ] При DECLINED — сообщение об ошибке + подсказка перейти в веб

---

## TASK-ESF-MOB-2: Push-уведомление при изменении статуса ЭСФ

**Приоритет:** 🟢 Желательно (Фаза 2)
**Зависит от:** TASK-ESF-BE-8 (scheduler)

### Что сделать

В бэке при синхронизации статусов — отправлять push через Firebase:

```java
// В EsfStatusSyncScheduler при изменении статуса:
if (newStatus == EsfStatus.DELIVERED) {
    notificationService.sendPush(
        executorUserId,
        "ЭСФ принят",
        "Счёт №" + invoice.getInvoiceNumber() + " подтверждён КГД"
    );
} else if (newStatus == EsfStatus.DECLINED) {
    notificationService.sendPush(
        executorUserId,
        "ЭСФ отклонён",
        "Счёт №" + invoice.getInvoiceNumber() + " отклонён. Проверьте детали."
    );
}
```

В мобилке уведомления уже работают через Firebase — дополнительной разработки не требуется, только добавить типы уведомлений.

### Критерии готовности
- [ ] Пуш приходит при DELIVERED
- [ ] Пуш приходит при DECLINED
- [ ] Нажатие на пуш открывает нужный счёт
