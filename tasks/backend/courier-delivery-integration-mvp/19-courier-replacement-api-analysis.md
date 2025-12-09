# Анализ API для замены курьера

## 📋 Резюме

Система Coube **частично поддерживает** замену курьера, но есть существенные ограничения и потенциальные проблемы, которые требуют доработки.

---

## 🔍 Текущая реализация

### Существующие API endpoints

#### 1. Назначение курьера
```
POST /api/v1/courier/waybills/{transportationId}/assign
POST /api/v1/executor/{transportationId}/assign-courier
```

**Локация кода:**
- `CourierWaybillController:59` - назначение курьера
- `ExecutorController:120` - назначение курьера
- `ExecutorService:615` - метод `assignCourier()`

#### 2. Отмена назначения водителя/курьера
```
DELETE /api/v1/executor/{transportationId}/driver
```

**Локация кода:**
- `ExecutorController:440` - отмена назначения
- `ExecutorService:890` - метод `cancelDriverAssignment()`

---

## ⚠️ Выявленные проблемы

### 1. Отсутствует специальный API для замены курьера

**Проблема:** Нет единого endpoint для замены курьера. Для замены нужно:
1. Сначала отменить текущего курьера (`cancelDriverAssignment`)
2. Затем назначить нового курьера (`assignCourier`)

**Риски:**
- Возможна рассинхронизация между операциями
- Временное отсутствие курьера на заявке
- Нет транзакционной целостности

### 2. Метод assignCourier не проверяет наличие существующего курьера

**Код проблемы:** `ExecutorService:652-653`
```java
transportation.setExecutorEmployee(courier);
transportation.setTransport(transport);
```

**Проблема:** Метод просто перезаписывает существующего курьера без проверок

**Риски:**
- Потеря информации о предыдущем курьере
- Нет истории изменений
- Возможна замена курьера в неподходящих статусах

### 3. Ограничения по статусам

**Отмена курьера возможна только в статусах:**
- `WAITING_DRIVER_CONFIRMATION`
- `DRIVER_ACCEPTED`

**Код:** `ExecutorService:296-299`
```java
if (transportation.getStatus() != TransportationStatus.WAITING_DRIVER_CONFIRMATION &&
    transportation.getStatus() != TransportationStatus.DRIVER_ACCEPTED) {
    throw new ClientAppException("Cannot cancel driver assignment in current status: " + transportation.getStatus());
}
```

**Проблема:** Нельзя заменить курьера если заявка в статусе:
- `ON_THE_WAY` - курьер уже в пути
- `VALIDATED` - заявка провалидирована
- Других промежуточных статусах

### 4. Отсутствует история замены курьера

**В TransportationHistoryEventType нет событий:**
- `DRIVER_CHANGED`
- `COURIER_REPLACED`
- `DRIVER_REASSIGNED`

**Проблема:** Невозможно отследить историю замен курьеров

### 5. Нет уведомлений при замене

**Проблема:** При замене курьера:
- Старый курьер не получает уведомление об отмене
- Новый курьер получает стандартное уведомление о назначении
- Заказчик не уведомляется о замене курьера

### 6. Проблемы с транспортным средством

При назначении курьера можно указать `transportId`, но при замене:
- Нет проверки совместимости нового ТС с маршрутом
- Не учитывается грузоподъемность/объем нового ТС

### 7. Отсутствие проверки активных доставок

**Проблема:** Можно заменить курьера, который уже начал выполнение (статус `ON_THE_WAY`)

---

## 🛡️ Подводные камни при замене курьера

### 1. Потеря данных о выполненной работе
- Если курьер уже отметил часть точек доставки
- Фотографии подтверждений привязаны к курьеру
- GPS треки привязаны к предыдущему курьеру

### 2. Юридические проблемы
- Договор/заявка может быть оформлена на конкретного курьера
- Проблемы с ответственностью за груз при передаче

### 3. Проблемы с интеграциями
- TEEZ может ожидать конкретного курьера
- Webhook уведомления могут содержать ID старого курьера

### 4. Финансовые риски
- Расчеты с курьерами могут быть нарушены
- Факторинг может быть привязан к конкретному исполнителю

---

## ✅ Рекомендации по реализации API замены курьера

### 1. Создать специальный endpoint для замены

```java
@PutMapping("/waybills/{transportationId}/replace-courier")
@Operation(summary = "Замена курьера на маршруте")
public ResponseEntity<Void> replaceCourier(
    @PathVariable Long transportationId,
    @RequestBody @Valid ReplaceCourierRequest request) {

    courierReplacementService.replaceCourier(
        transportationId,
        request.getOldCourierId(),
        request.getNewCourierId(),
        request.getReason());

    return ResponseEntity.ok().build();
}
```

### 2. Добавить новый DTO

```java
public class ReplaceCourierRequest {
    @NotNull
    private Long oldCourierId;

    @NotNull
    private Long newCourierId;

    private Long newTransportId; // опционально

    @NotBlank
    private String reason; // причина замены

    private boolean transferProgress; // передать прогресс выполнения
}
```

### 3. Создать сервис замены курьера

```java
@Service
@Transactional
public class CourierReplacementService {

    public void replaceCourier(Long transportationId, Long oldCourierId,
                               Long newCourierId, String reason) {

        Transportation transportation = transportationService.findById(transportationId);

        // 1. Проверка статуса
        validateReplacementAllowed(transportation);

        // 2. Проверка старого курьера
        validateOldCourier(transportation, oldCourierId);

        // 3. Проверка нового курьера
        Employee newCourier = validateAndGetNewCourier(newCourierId);

        // 4. Сохранение истории
        saveReplacementHistory(transportation, oldCourierId, newCourierId, reason);

        // 5. Передача прогресса (если нужно)
        transferProgressIfNeeded(transportation, oldCourierId, newCourierId);

        // 6. Замена курьера
        transportation.setExecutorEmployee(newCourier);

        // 7. Обновление статуса при необходимости
        updateStatusIfNeeded(transportation);

        // 8. Сохранение
        transportationService.save(transportation);

        // 9. Отправка уведомлений
        sendReplacementNotifications(transportation, oldCourierId, newCourierId);

        // 10. Логирование для интеграций
        logCourierReplacement(transportationId, oldCourierId, newCourierId, reason);
    }

    private void validateReplacementAllowed(Transportation transportation) {
        Set<TransportationStatus> allowedStatuses = Set.of(
            TransportationStatus.VALIDATED,
            TransportationStatus.WAITING_DRIVER_CONFIRMATION,
            TransportationStatus.DRIVER_ACCEPTED,
            TransportationStatus.ON_THE_WAY // с ограничениями
        );

        if (!allowedStatuses.contains(transportation.getStatus())) {
            throw new ValidationException("Замена курьера невозможна в статусе: "
                + transportation.getStatus());
        }

        // Дополнительная проверка для ON_THE_WAY
        if (transportation.getStatus() == TransportationStatus.ON_THE_WAY) {
            // Проверить, что не прошло более 30% маршрута
            validatePartialProgress(transportation);
        }
    }
}
```

### 4. Добавить новые типы событий истории

```java
public enum TransportationHistoryEventType {
    // ... существующие
    COURIER_REPLACED,         // Курьер заменен
    COURIER_REPLACEMENT_REQUESTED, // Запрошена замена курьера
    COURIER_REPLACEMENT_REJECTED,  // Замена отклонена
}
```

### 5. Добавить таблицу истории замен

```sql
CREATE TABLE courier_replacement_history (
    id BIGSERIAL PRIMARY KEY,
    transportation_id BIGINT NOT NULL REFERENCES transportation(id),
    old_courier_id BIGINT REFERENCES employee(id),
    new_courier_id BIGINT NOT NULL REFERENCES employee(id),
    reason TEXT NOT NULL,
    replaced_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    replaced_by_employee_id BIGINT REFERENCES employee(id),
    status VARCHAR(50) NOT NULL, -- PENDING, COMPLETED, FAILED
    progress_transferred BOOLEAN DEFAULT FALSE,
    metadata JSONB -- дополнительная информация
);

CREATE INDEX idx_courier_replacement_transportation
    ON courier_replacement_history(transportation_id);
```

### 6. Обработка специальных случаев

```java
// Замена курьера в процессе доставки
if (transportation.getStatus() == TransportationStatus.ON_THE_WAY) {
    // 1. Передать текущую геолокацию
    transferCurrentLocation(oldCourier, newCourier, transportation);

    // 2. Передать выполненные точки
    transferCompletedPoints(oldCourier, newCourier, transportation);

    // 3. Передать загруженные фото
    reassignUploadedPhotos(oldCourier, newCourier, transportation);

    // 4. Обновить статусы заказов
    updateOrdersAssignment(oldCourier, newCourier, transportation);
}
```

---

## 📊 Оценка трудозатрат

| Задача | Время |
|--------|-------|
| Создание endpoint и DTO | 2 часа |
| Реализация сервиса замены | 8 часов |
| Добавление истории событий | 2 часа |
| Создание таблицы истории замен | 2 часа |
| Обработка специальных случаев | 4 часа |
| Интеграция с уведомлениями | 3 часа |
| Тестирование | 4 часа |
| **Итого** | **25 часов** (~3 дня) |

---

## 🚀 Быстрое решение (MVP)

Если нужно быстрое решение без полного рефакторинга:

### Вариант 1: Использовать существующие методы с проверками

```java
@Transactional
public void quickReplaceCourier(Long transportationId, Long newCourierId) {
    Transportation t = transportationService.findById(transportationId);

    // Проверка статуса
    if (t.getStatus() == TransportationStatus.ON_THE_WAY ||
        t.getStatus() == TransportationStatus.FINISHED) {
        throw new ValidationException("Нельзя заменить курьера в текущем статусе");
    }

    // Сохранить старого курьера
    Long oldCourierId = t.getExecutorEmployee() != null ?
        t.getExecutorEmployee().getId() : null;

    // Назначить нового
    executorService.assignCourier(transportationId, newCourierId, null);

    // Логирование
    log.info("Курьер {} заменен на {} для заявки {}",
        oldCourierId, newCourierId, transportationId);
}
```

### Вариант 2: Добавить флаг isReplacement

Модифицировать существующий `assignCourier` метод:

```java
public void assignCourier(Long transportationId, Long courierId,
                         Long transportId, boolean isReplacement) {
    // ... существующая логика

    if (isReplacement && transportation.getExecutorEmployee() != null) {
        // Логика замены
        historyService.save(
            HistoryRequestDto.builder()
                .transportation(transportation)
                .eventType(TransportationHistoryEventType.DRIVER_REPLACED)
                .metadata(Map.of(
                    "oldCourierId", transportation.getExecutorEmployee().getId(),
                    "newCourierId", courierId
                ))
                .build()
        );
    }

    // ... продолжение
}
```

---

## ⚠️ Критические моменты

1. **ОБЯЗАТЕЛЬНО** добавить проверку статуса перед заменой
2. **ОБЯЗАТЕЛЬНО** логировать все замены для аудита
3. **ВАЖНО** уведомлять всех участников процесса
4. **ВАЖНО** сохранять историю изменений
5. **КРИТИЧНО** не допускать замену после начала доставки без специальной логики

---

## 📝 Заключение

Текущая система **не готова** к полноценной замене курьеров без доработок. Основные проблемы:

1. Отсутствует транзакционная замена
2. Нет истории изменений
3. Нет проверок совместимости
4. Нет уведомлений о замене
5. Возможна потеря данных о выполненной работе

**Рекомендация:** Реализовать специальный API для замены курьера с учетом всех описанных рисков и проверок.

---

**Дата создания:** 2025-12-09
**Автор:** Claude AI Assistant
**Версия:** 1.0
**Статус:** Анализ завершен