# BE-3 — Workflow Contract + EDS для COURIER_DELIVERY

**Статус:** 🔴 Критично  
**Оценка:** 4ч  
**Файлы:**
- `coube-backend/src/main/java/kz/coube/backend/agreement/service/AgreementService.java`
- `coube-backend/src/main/java/kz/coube/backend/applications/entity/Contract.java`
- `coube-backend/src/main/java/kz/coube/backend/executor/service/ExecutorService.java`

---

## Описание

Убедиться что для `COURIER_DELIVERY` (`agreementBased=false`) работает тот же путь создания и подписания договора (Contract + EDS), что и для FTL.

Целевой флоу:
1. Заказчик принимает цену перевозчика
2. Создаётся `Contract`, привязанный к `Transportation`
3. Договор отправляется перевозчику на EDS подпись
4. Перевозчик подписывает → договор идёт заказчику
5. Заказчик подписывает → `status = SIGNED_CUSTOMER`

---

## Чеклист

### Проверка существующего кода

- [ ] Найти метод принятия цены заказчиком (вероятно в `CustomerTransportationService` или `ExecutorService`)
- [ ] Убедиться что при принятии цены создаётся `Contract` для `COURIER_DELIVERY`
- [ ] Убедиться что `Contract.expectedSignaturesCount = 2` (обе стороны)

### Contract Entity

- [ ] `Contract` корректно связан с `Transportation` (one-to-one)
- [ ] Поля `signatureWithOneSign` и `signatureWithTwoSigns` используются для EDS
- [ ] Генерация документа договора (PDF) работает для `COURIER_DELIVERY`

### EDS подпись

- [ ] Перевозчик может подписать через `POST /api/v1/executor/agreements/{id}/sign` или аналог
- [ ] Заказчик может подписать через `POST /api/v1/customer/agreements/{id}/sign`
- [ ] После обеих подписей → `Transportation.status = SIGNED_CUSTOMER`
- [ ] После `SIGNED_CUSTOMER` → нельзя редактировать `cargoLoadings`

### AgreementService

- [ ] Нет ограничений по `transportationType` при создании Agreement/Contract
- [ ] `Agreement.transportationType` корректно хранит `COURIER_DELIVERY`

### Тесты

- [ ] Принятие цены → Contract создаётся
- [ ] EDS подпись перевозчика → статус обновляется
- [ ] EDS подпись заказчика → `SIGNED_CUSTOMER`
- [ ] Редактирование `cargoLoadings` после `SIGNED_CUSTOMER` → ошибка
