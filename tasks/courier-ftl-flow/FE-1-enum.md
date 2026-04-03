# FE-1 — Добавить COURIER_DELIVERY в ETransportationType enum

**Статус:** 🔴 Критично  
**Оценка:** 30мин  
**Файл:** `coube-frontend/src/types/enums/transportationType.ts`

---

## Описание

`COURIER_DELIVERY` отсутствует в фронтенд-перечислении. Без этого невозможно создать заявку этого типа через UI. Это блокирующее изменение для всего остального на фронтенде.

---

## Чеклист

### transportationType.ts

- [ ] Добавить `COURIER_DELIVERY = 'COURIER_DELIVERY'` в `ETransportationType`

```typescript
export const enum ETransportationType {
  BULK = 'BULK',
  FTL = 'FTL',
  CITY = 'CITY',
  LTL = 'LTL',
  COURIER_DELIVERY = 'COURIER_DELIVERY', // добавить
}
```

### Проверить все места использования enum

- [ ] Найти все switch/if по `ETransportationType` — убедиться что `COURIER_DELIVERY` обрабатывается (или попадает в default)
- [ ] Проверить компоненты фильтрации — если есть hardcode списка типов, добавить `COURIER_DELIVERY`
- [ ] `npm run type-check` — нет TS ошибок
