# FE-2 — Словарь и i18n переводы для COURIER_DELIVERY

**Статус:** 🔴 Критично  
**Оценка:** 1ч  
**Зависит от:** FE-1  
**Файлы:**
- `coube-frontend/src/vars/application.ts`
- `coube-frontend/src/i18n/ru.json`
- `coube-frontend/src/i18n/en.json`
- `coube-frontend/src/i18n/kk.json`
- `coube-frontend/src/i18n/zh.json`

---

## Чеклист

### vars/application.ts — transportationTypesDictionary

- [ ] Добавить запись для `COURIER_DELIVERY`:

```typescript
[ETransportationType.COURIER_DELIVERY]: {
  title: 'application.type.COURIER_DELIVERY.title',
  subtitle: 'application.type.COURIER_DELIVERY.subtitle',
  disabled: false,
}
```

### i18n — ru.json

- [ ] `application.type.COURIER_DELIVERY.title` = `"Курьерская доставка"`
- [ ] `application.type.COURIER_DELIVERY.subtitle` = `"Курьерская доставка с перевозчиком"`

### i18n — en.json

- [ ] `application.type.COURIER_DELIVERY.title` = `"Courier Delivery"`
- [ ] `application.type.COURIER_DELIVERY.subtitle` = `"Courier delivery with carrier"`

### i18n — kk.json

- [ ] `application.type.COURIER_DELIVERY.title` = `"Курьерлік жеткізу"`
- [ ] `application.type.COURIER_DELIVERY.subtitle` = `"Тасымалдаушымен курьерлік жеткізу"`

### i18n — zh.json

- [ ] `application.type.COURIER_DELIVERY.title` = `"快递配送"`
- [ ] `application.type.COURIER_DELIVERY.subtitle` = `"承运商快递配送"`

### Проверка

- [ ] `npm run i18n:check` — нет missing ключей
- [ ] Тип отображается корректно в UI при выборе в форме создания
