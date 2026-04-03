# BE-4 — Статусные условия в ExecutorService.assignCourier

**Статус:** 🟡 Важно  
**Оценка:** 2ч  
**Файл:** `coube-backend/src/main/java/kz/coube/backend/executor/service/ExecutorService.java:768`

---

## Описание

Метод `assignCourier` уже существует и проверяет `transportationType = COURIER_DELIVERY`. Нужно убедиться что он корректно работает в новом FTL-флоу (а не только в импортном).

В импортном флоу курьера назначают при статусе `VALIDATED`.  
В новом FTL-флоу курьера назначают при статусе `SIGNED_CUSTOMER`.

---

## Чеклист

### Проверка текущего кода (ExecutorService.java:768)

- [ ] Прочитать метод `assignCourier` полностью
- [ ] Найти проверку статуса — какой статус требуется для назначения
- [ ] Если требуется только `VALIDATED` → добавить `SIGNED_CUSTOMER` как допустимый

### Статусный переход

- [ ] При назначении курьера из `SIGNED_CUSTOMER`:
  - [ ] `transportation.executorEmployee = courier`
  - [ ] `transportation.transport = transport` (опционально)
  - [ ] `transportation.status = WAITING_DRIVER_CONFIRMATION`
- [ ] Убедиться что переход `SIGNED_CUSTOMER → WAITING_DRIVER_CONFIRMATION` не ломает импортный флоу

### Проверки в assignCourier

- [ ] Курьер принадлежит организации перевозчика (`executorOrganization`)
- [ ] Курьер имеет роль `DRIVER` / `is_driver = true`
- [ ] Курьер активен (`status = ACTIVE`)
- [ ] `transportationType = COURIER_DELIVERY` (уже есть на строке 771)

### Тесты

- [ ] `assignCourier` при `SIGNED_CUSTOMER` → `WAITING_DRIVER_CONFIRMATION` ✓
- [ ] `assignCourier` при `VALIDATED` → `WAITING_DRIVER_CONFIRMATION` ✓ (импортный флоу не сломан)
- [ ] `assignCourier` при `CREATED` → ошибка
- [ ] Курьер не из организации перевозчика → ошибка
