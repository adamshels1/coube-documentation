# Задача 25: Исправление бага с завершением маршрута при отъезде со склада

**Дата создания**: 2025-12-23
**Приоритет**: 🔴 CRITICAL
**Статус**: ❌ Bug Found
**Оценка времени**: 2-3 часа (Backend + тестирование)

---

## 📋 Описание проблемы

### Критический баг в методе `processDeparture`

**Файл**: `coube-backend/src/main/java/kz/coube/backend/driver/service/DriverService.java`
**Строка**: 442
**Метод**: `processDeparture(Long transportationId, CargoLoadingUpdateRequest request)`

### Воспроизведение бага

**Сценарий**:
1. У курьера есть маршрут с 2 точками:
   - Точка 1 (склад LOADING): orderNum = 1
   - Точка 2 (доставка UNLOADING): orderNum = 2, с заказами TRACK-460, TRACK-461
2. Курьер начинает маршрут → статус `ON_THE_WAY`, активна точка 1
3. Курьер прибывает на склад → точка 1: `isDriverAtLocation: true`
4. Курьер нажимает "Поехали дальше" (departure from point 1)
5. **❌ БАГ**: Заказ сразу завершается (статус `FINISHED`), показывается модалка "Заказ завершен"
6. **✅ ОЖИДАЛОСЬ**: Должна активироваться точка 2, курьер должен доехать до нее и выполнить доставки

### Ожидаемый флоу:
```
1. Начать маршрут → статус ON_THE_WAY, активна точка 1 (склад)
2. Прибыть на склад → точка 1: isDriverAtLocation = true
3. Завершить погрузку и отъехать → деактивировать точку 1, активировать точку 2
4. Прибыть на доставку → точка 2: isDriverAtLocation = true
5. Выполнить доставки → заказы получают статус DELIVERED/NOT_DELIVERED
6. Отъехать от последней точки → статус FINISHED
```

### Актуальный (неправильный) флоу:
```
1. Начать маршрут → статус ON_THE_WAY, активна точка 1 (склад)
2. Прибыть на склад → точка 1: isDriverAtLocation = true
3. Завершить погрузку и отъехать → ❌ статус FINISHED (БАГ!)
```

---

## 🔍 Анализ кода

### Проблемный код (строка 442)

```java
@Transactional
public TransportationResponse processDeparture(
        final Long transportationId, final CargoLoadingUpdateRequest request) {
    var transportation = getTransportationById(transportationId);
    var cargoLoading =
            cargoLoadingService.findCargoLoadingByTransportationIdAndIsActiveTrue(transportationId);
    TransportationHistoryEventType eventType;

    if (!cargoLoading.getId().equals(request.cargoLoadingId())
            || !cargoLoading.getIsDriverAtLocation()) {
        throw new NoAccessException("error.access.universal");
    }
    cargoLoading.setIsDriverAtLocation(false);
    cargoLoading.setIsActive(false);
    cargoLoadingService.save(cargoLoading);

    var nextOrderNum = cargoLoading.getOrderNum() + 1;

    // ❌ ПРОБЛЕМА НА ЭТОЙ СТРОКЕ
    if (nextOrderNum == transportation.getCargoLoadings().size()) {
        // Этот код выполняется когда водитель едет К последней точке,
        // а не когда он отъезжает С последней точки!

        boolean isCourierDelivery = TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType());
        boolean hasReturnedOrders = isCourierDelivery && courierRouteOrderService.hasReturnedOrders(transportation);

        if (hasReturnedOrders) {
            transportation.setStatus(TransportationStatus.AWAITING_RETURN_CONFIRMATION);
            eventType = TransportationHistoryEventType.AWAITING_RETURN_CONFIRMATION;
        } else {
            transportation.setStatus(TransportationStatus.FINISHED); // ❌ Устанавливается преждевременно!
            eventType = TransportationHistoryEventType.TRIP_FINISHED;
        }

        if (transportation.getTransport() != null) {
            transportation.getTransport().setStatus(TransportStatus.AVAILABLE);
        }
        transportationService.save(transportation);
    } else {
        var nextCargoLoading =
                cargoLoadingService.findByTransportationIdAndOrderNum(
                        transportationId, cargoLoading.getOrderNum() + 1);
        nextCargoLoading.setIsActive(true);
        cargoLoadingService.save(nextCargoLoading);
        eventType = TransportationHistoryEventType.WAYPOINT_LEFT;
    }

    // ... остальной код
}
```

### Логика ошибки

**Данные**:
- Всего точек: `transportation.getCargoLoadings().size()` = 2
- Текущая точка: `cargoLoading.getOrderNum()` = 1
- Следующая точка: `nextOrderNum = 1 + 1` = 2

**Условие**:
```java
if (nextOrderNum == transportation.getCargoLoadings().size()) {
    // nextOrderNum = 2
    // size = 2
    // 2 == 2 → TRUE ❌
    // Заказ завершается!
}
```

**Проблема**: Условие `nextOrderNum == size` становится `true` когда водитель **едет К последней точке**, а не когда он **отъезжает С последней точки**.

---

## ✅ Решение

### Вариант 1: Минимальное исправление (рекомендуется)

Изменить условие на строке 442:

```java
// Было:
if (nextOrderNum == transportation.getCargoLoadings().size()) {

// Стало:
if (nextOrderNum > transportation.getCargoLoadings().size()) {
```

**Логика после исправления**:

| Точка | orderNum | nextOrderNum | size | Условие | Результат |
|-------|----------|--------------|------|---------|-----------|
| Склад (1) | 1 | 2 | 2 | `2 > 2` = FALSE | Активируется точка 2 ✅ |
| Доставка (2) | 2 | 3 | 2 | `3 > 2` = TRUE | Заказ завершается ✅ |

### Вариант 2: Альтернативное условие

```java
// Альтернатива:
if (cargoLoading.getOrderNum() == transportation.getCargoLoadings().size()) {
```

Это эквивалентно варианту 1, но более явно показывает намерение: "если текущая точка - последняя".

---

## 🔧 Полное исправление для курьерской доставки

### Упрощенная логика (строка ~443)

**Ключевое правило**: Без разницы, является ли последняя точка обычной доставкой или ПВЗ (склад с `isCourierWarehouse = true`).

**Единственная проверка**: Есть ли возвраты в маршруте?
- ✅ Если есть возвраты → статус `AWAITING_RETURN_CONFIRMATION` (требуется подтверждение логиста/админа)
- ✅ Если нет возвратов → статус `FINISHED`

```java
if (nextOrderNum > transportation.getCargoLoadings().size()) {
    // Отъезжаем от последней точки (любой - доставка или ПВЗ)

    boolean isCourierDelivery = TransportationType.COURIER_DELIVERY.equals(
        transportation.getTransportationType());

    // ✅ ЕДИНСТВЕННАЯ ПРОВЕРКА: есть ли возвраты в маршруте
    boolean hasReturnedOrders = isCourierDelivery &&
                                courierRouteOrderService.hasReturnedOrders(transportation);

    if (hasReturnedOrders) {
        // Есть возвраты → требуется подтверждение логиста/админа
        transportation.setStatus(TransportationStatus.AWAITING_RETURN_CONFIRMATION);
        eventType = TransportationHistoryEventType.AWAITING_RETURN_CONFIRMATION;

        log.info("Transportation {} has returned orders, status set to AWAITING_RETURN_CONFIRMATION",
                transportationId);
    } else {
        // Нет возвратов → завершаем
        transportation.setStatus(TransportationStatus.FINISHED);
        eventType = TransportationHistoryEventType.TRIP_FINISHED;
    }

    if (transportation.getTransport() != null) {
        transportation.getTransport().setStatus(TransportStatus.AVAILABLE);
    }
    transportationService.save(transportation);
} else {
    // Активируем следующую точку
    var nextCargoLoading =
            cargoLoadingService.findByTransportationIdAndOrderNum(
                    transportationId, cargoLoading.getOrderNum() + 1);
    nextCargoLoading.setIsActive(true);
    cargoLoadingService.save(nextCargoLoading);
    eventType = TransportationHistoryEventType.WAYPOINT_LEFT;
}
```

### Матрица сценариев для последней точки

| Последняя точка | Есть возвраты? | Статус после departure |
|-----------------|----------------|------------------------|
| Обычная доставка | ❌ Нет | `FINISHED` ✅ |
| Обычная доставка | ✅ Да | `AWAITING_RETURN_CONFIRMATION` ✅ |
| Склад ПВЗ (`isCourierWarehouse = true`) | ❌ Нет | `FINISHED` ✅ |
| Склад ПВЗ (`isCourierWarehouse = true`) | ✅ Да | `AWAITING_RETURN_CONFIRMATION` ✅ |

**Важно**: `isCourierWarehouse` не влияет на логику завершения маршрута. Важно только наличие возвратов.

---

## 📝 Чеклист реализации

### Backend изменения

- [ ] **Исправить условие в `DriverService.processDeparture`** (строка 442)
  - Изменить `if (nextOrderNum == transportation.getCargoLoadings().size())` на
  - `if (nextOrderNum > transportation.getCargoLoadings().size())`

- [ ] **Упростить логику для последней точки**
  - Убрать лишние проверки (тип точки, статусы заказов)
  - Оставить только проверку `hasReturnedOrders`
  - Логика работает одинаково для любой последней точки (доставка или ПВЗ)

- [ ] **Добавить логирование**
  ```java
  log.info("Processing departure from point {} (orderNum: {}/{}). Next orderNum: {}",
      cargoLoading.getId(), cargoLoading.getOrderNum(),
      transportation.getCargoLoadings().size(), nextOrderNum);
  ```

### Тестирование

- [ ] **Unit тест: Отъезд с первой точки (не последней)**
  ```java
  @Test
  void processDeparture_fromFirstPoint_shouldActivateNextPoint() {
      // Given: маршрут с 2 точками, водитель на точке 1
      // When: processDeparture от точки 1
      // Then:
      //   - точка 1 деактивирована
      //   - точка 2 активирована
      //   - статус остается ON_THE_WAY
  }
  ```

- [ ] **Unit тест: Отъезд с последней точки (нет возвратов)**
  ```java
  @Test
  void processDeparture_fromLastPoint_noReturns_shouldFinish() {
      // Given: маршрут с 2 точками, водитель на точке 2, НЕТ возвратов
      // When: processDeparture от точки 2
      // Then:
      //   - точка 2 деактивирована
      //   - статус FINISHED
  }
  ```

- [ ] **Unit тест: Отъезд с последней точки (есть возвраты)**
  ```java
  @Test
  void processDeparture_fromLastPoint_hasReturns_shouldAwaitConfirmation() {
      // Given: маршрут с 2 точками, водитель на точке 2, ЕСТЬ возвраты
      // When: processDeparture от точки 2
      // Then:
      //   - точка 2 деактивирована
      //   - статус AWAITING_RETURN_CONFIRMATION
  }
  ```

- [ ] **Unit тест: Отъезд с последней точки ПВЗ (нет возвратов)**
  ```java
  @Test
  void processDeparture_fromWarehouse_noReturns_shouldFinish() {
      // Given: маршрут с последней точкой = ПВЗ (isCourierWarehouse=true), НЕТ возвратов
      // When: processDeparture от ПВЗ
      // Then:
      //   - ПВЗ деактивирован
      //   - статус FINISHED
  }
  ```

- [ ] **Unit тест: Отъезд с последней точки ПВЗ (есть возвраты)**
  ```java
  @Test
  void processDeparture_fromWarehouse_hasReturns_shouldAwaitConfirmation() {
      // Given: маршрут с последней точкой = ПВЗ (isCourierWarehouse=true), ЕСТЬ возвраты
      // When: processDeparture от ПВЗ
      // Then:
      //   - ПВЗ деактивирован
      //   - статус AWAITING_RETURN_CONFIRMATION
  }
  ```

- [ ] **Integration тест: Полный флоу с 2 точками (нет возвратов)**
  ```java
  @Test
  void courierDelivery_fullFlow_twoPoints_noReturns_shouldFinish() {
      // 1. Начать маршрут
      // 2. Прибыть на склад (точка 1)
      // 3. Отъехать со склада → точка 2 активируется, статус ON_THE_WAY
      // 4. Прибыть на доставку (точка 2)
      // 5. Обновить статусы заказов → DELIVERED (нет возвратов)
      // 6. Отъехать от доставки → статус FINISHED
  }
  ```

- [ ] **Integration тест: Полный флоу с возвратами**
  ```java
  @Test
  void courierDelivery_fullFlow_withReturns_shouldAwaitConfirmation() {
      // 1. Начать маршрут
      // 2. Прибыть на склад (точка 1)
      // 3. Отъехать со склада → точка 2 активируется
      // 4. Прибыть на доставку (точка 2)
      // 5. Обновить статусы заказов → некоторые PARTIALLY_RETURNED (есть возвраты)
      // 6. Отъехать от доставки → статус AWAITING_RETURN_CONFIRMATION
  }
  ```

### Manual тестирование (с мобильным приложением)

- [ ] **Сценарий 1: Базовый флоу без возвратов (как в баге)**
  - Создать маршрут с 2 точками: Склад + Доставка
  - Отъехать со склада → ✅ точка доставки активируется (не FINISHED!)
  - Доставить все заказы (статус DELIVERED)
  - Отъехать от доставки → ✅ статус FINISHED

- [ ] **Сценарий 2: Флоу с возвратами**
  - Создать маршрут с 2 точками: Склад + Доставка
  - Отъехать со склада → точка доставки активируется
  - Отметить некоторые заказы как PARTIALLY_RETURNED
  - Отъехать от доставки → ✅ статус AWAITING_RETURN_CONFIRMATION (не FINISHED!)

- [ ] **Сценарий 3: Последняя точка = ПВЗ, с возвратами**
  - Создать маршрут с 3 точками: Склад + Доставка + ПВЗ (isCourierWarehouse=true)
  - Выполнить доставку с возвратами
  - Прибыть на ПВЗ (точка 3)
  - Отъехать от ПВЗ → ✅ статус AWAITING_RETURN_CONFIRMATION

- [ ] **Сценарий 4: Последняя точка = ПВЗ, без возвратов**
  - Создать маршрут с 3 точками: Склад + Доставка + ПВЗ (isCourierWarehouse=true)
  - Выполнить доставку без возвратов (все DELIVERED)
  - Прибыть на ПВЗ (точка 3)
  - Отъехать от ПВЗ → ✅ статус FINISHED

- [ ] **Сценарий 5: Три точки доставки**
  - Создать маршрут с 4 точками: Склад + Доставка 1 + Доставка 2 + Доставка 3
  - Отъехать с точки 1 → точка 2 активируется
  - Отъехать с точки 2 → точка 3 активируется
  - Отъехать с точки 3 → точка 4 активируется
  - Выполнить доставки на точке 4 (без возвратов)
  - Отъехать с точки 4 → ✅ статус FINISHED

---

## 🎯 Критерии приемки

### Функциональные требования

✅ При отъезде с **не последней** точки:
- Текущая точка деактивируется (`isActive = false`, `isDriverAtLocation = false`)
- Следующая точка активируется (`isActive = true`)
- Статус остается `ON_THE_WAY`
- В историю записывается событие `WAYPOINT_LEFT`

✅ При отъезде с **последней** точки (любой - доставка или ПВЗ):
- Текущая точка деактивируется
- Проверяется наличие возвратов в маршруте (`hasReturnedOrders`)
  - **Если есть возвраты** → статус `AWAITING_RETURN_CONFIRMATION`, событие `AWAITING_RETURN_CONFIRMATION`
  - **Если нет возвратов** → статус `FINISHED`, событие `TRIP_FINISHED`
- Транспорт переходит в статус `AVAILABLE` (если был назначен)
- **Важно**: Тип последней точки (`isCourierWarehouse`) НЕ влияет на логику

✅ Для **обычной перевозки** (FLT):
- Логика не изменяется
- Работает как раньше

### Нефункциональные требования

✅ Все существующие тесты проходят
✅ Добавлены unit тесты для новой логики
✅ Добавлены integration тесты
✅ Код прошел code review
✅ Обновлена документация (если требуется)

---

## 🚨 Влияние на другие части системы

### Затронутые компоненты

1. **Backend**:
   - ✅ `DriverService.processDeparture` - основное исправление
   - ⚠️ Убедиться, что для FLT ничего не сломалось

2. **Mobile (React Native)**:
   - ℹ️ Изменений не требуется
   - ℹ️ Но нужно убедиться, что кнопка "Поехали дальше" правильно обрабатывает обновленное поведение

3. **Frontend (Vue.js)**:
   - ℹ️ Изменений не требуется
   - ℹ️ Логист может мониторить корректное выполнение маршрута

### Откат (Rollback plan)

Если после деплоя обнаружатся проблемы:

1. **Быстрый откат (revert commit)**:
   ```bash
   git revert <commit-hash>
   ```

2. **Feature flag** (если используются):
   ```java
   if (featureFlags.isEnabled("fix-departure-last-point")) {
       // новая логика
   } else {
       // старая логика
   }
   ```

---

## 📊 Оценка времени

| Задача | Время |
|--------|-------|
| Исправление кода в `DriverService` (упрощенная логика) | 20 мин |
| Написание unit тестов (5 тестов) | 1 час |
| Integration тесты (2 теста) | 30 мин |
| Manual тестирование с мобильным приложением (5 сценариев) | 1 час |
| Code review + правки | 20 мин |
| **ИТОГО** | **2.5 часа** |

**Буфер на непредвиденные ситуации**: +30 мин

**Общая оценка**: **2.5-3 часа**

**Примечание**: Оценка снизилась благодаря упрощению логики (убрали проверку статусов заказов)

---

## 🔗 Связанные документы

- **API Documentation**: [09-logist-edit-waybill-api.md](09-logist-edit-waybill-api.md)
- **Order Status Update**: [10-courier-order-status-update-endpoint.md](10-courier-order-status-update-endpoint.md)
- **Return Confirmation**: [13-return-confirmation-blocking.md](13-return-confirmation-blocking.md)
- **Transportation Entity**: `coube-backend/src/main/java/kz/coube/backend/applications/entity/Transportation.java`
- **DriverService**: `coube-backend/src/main/java/kz/coube/backend/driver/service/DriverService.java:442`

---

## 📞 Контакты

**Найдено**: Claude Code
**Дата обнаружения**: 2025-12-23
**Окружение**: Development/Testing
**Severity**: CRITICAL - блокирует выполнение курьерской доставки

---

**Статус**: ❌ Требует исправления
**Приоритет**: 🔴 CRITICAL
**Assigned to**: Backend Developer
**Estimated time**: 2-4 часа
