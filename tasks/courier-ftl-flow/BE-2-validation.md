# BE-2 — Валидация при ручном создании COURIER_DELIVERY

**Статус:** 🔴 Критично  
**Оценка:** 2ч  
**Файл:** `coube-backend/src/main/java/kz/coube/backend/customer/CustomerTransportationService.java`

---

## Описание

При ручном создании курьерской заявки (не через импорт) нужно:
1. Убедиться что `source_system = null` и `external_waybill_id = null`
2. Статусный переход идёт `FORMING → CREATED` (не `IMPORTED`)
3. Статусы `IMPORTED` и `VALIDATED` недоступны для ручного флоу

Различие между флоу определяется полем `source_system`:
- Импорт: `source_system = 'TEEZ_PVZ'` / `'KASPI'` / etc
- Ручное: `source_system = null`

---

## Чеклист

### В методе createCompleteTransportation

- [ ] При `transportationType = COURIER_DELIVERY`:
  - [ ] Установить `source_system = null`
  - [ ] Установить `external_waybill_id = null`
  - [ ] Статус: `FORMING` (не `IMPORTED`)

### Валидация полей маршрута

- [ ] Проверить что `cargoLoadings` не пустой (минимум 2 точки: LOADING + UNLOADING)
- [ ] Проверить что у каждой точки есть `address` и `loadingType`

### Защита статусов IMPORTED / VALIDATED

- [ ] В `CourierIntegrationService` добавить проверку: если `source_system = null` → запретить переход в `IMPORTED` / `VALIDATED`
- [ ] Убедиться что `validateWaybill` (IMPORTED → VALIDATED) работает только для заявок с `source_system != null`

### Тесты

- [ ] `createCompleteTransportation` с `COURIER_DELIVERY` → `source_system = null`
- [ ] `createCompleteTransportation` с `COURIER_DELIVERY` → статус `FORMING`, не `IMPORTED`
- [ ] Вызов `validateWaybill` на ручной заявке → ошибка
