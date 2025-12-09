# 20. Дублирование SMS-кода подтверждения для логиста

**Дата создания**: 2025-12-09
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali

---

## Проблема

SMS-код подтверждения доставки отправляется только клиенту в WhatsApp. Если клиент не может прочитать SMS, логист не знает код и не может помочь.

**Текущая ситуация**:
- ✅ SMS-код генерируется при прибытии курьера (`DriverService:514`)
- ✅ Код отправляется клиенту в WhatsApp
- ✅ Код сохраняется после использования в `CourierRouteOrder.smsCodeUsed`
- ❌ Код НЕ сохраняется сразу при генерации
- ❌ Логист НЕ получает push с кодом
- ❌ Код НЕ отображается в заявке

---

## Решение

Сохранять SMS-код в БД при генерации и дублировать его логисту через push + показывать в админке.

---

## Изменения в коде

### 1. Добавить поле в БД для хранения последнего SMS-кода

**Файл**: Новая миграция `V20251209__add_last_sms_code_to_cargo_loading.sql`

```sql
ALTER TABLE gis.cargo_loading_history
ADD COLUMN last_sms_code VARCHAR(6);
```

### 2. Обновить Entity

**Файл**: `src/main/java/kz/coube/backend/route/entity/CargoLoadingHistory.java`

**Добавить поле**:
```java
@Column(name = "last_sms_code")
private String lastSmsCode;

// + getter/setter
public String getLastSmsCode() {
    return lastSmsCode;
}

public void setLastSmsCode(String lastSmsCode) {
    this.lastSmsCode = lastSmsCode;
}
```

### 3. Сохранять SMS-код при генерации и отправлять логисту

**Файл**: `src/main/java/kz/coube/backend/driver/service/DriverService.java`

**Было** (строка 513-526):
```java
private void sendSmsWhenCourierArrived(CargoLoadingHistory cargoLoadingHistory) {
    String smsCode = delegate.generate(new OtpId(cargoLoadingHistory.getContactNumber()));
    log.info("Sms code for: {} number, otp: {}", cargoLoadingHistory.getContactNumber(), smsCode);

    WhatsAppSendRequest requestWhatsApp = WhatsAppSendRequest.builder()
            .phone(cargoLoadingHistory.getContactNumber())
            .template(WhatsAppTemplate.DELIVERY_CODE_MSG)
            .language("ru")
            .bodyParams(List.of(smsCode))
            .buttonParam(smsCode)
            .build();
    whatsAppSenderService.sendTemplate(requestWhatsApp);
}
```

**Стало**:
```java
private void sendSmsWhenCourierArrived(CargoLoadingHistory cargoLoadingHistory) {
    String smsCode = delegate.generate(new OtpId(cargoLoadingHistory.getContactNumber()));
    log.info("Sms code for: {} number, otp: {}", cargoLoadingHistory.getContactNumber(), smsCode);

    // ⭐ NEW: Сохранить код в БД
    cargoLoadingHistory.setLastSmsCode(smsCode);
    cargoLoadingService.save(cargoLoadingHistory);

    // Отправка клиенту (существующий код)
    WhatsAppSendRequest requestWhatsApp = WhatsAppSendRequest.builder()
            .phone(cargoLoadingHistory.getContactNumber())
            .template(WhatsAppTemplate.DELIVERY_CODE_MSG)
            .language("ru")
            .bodyParams(List.of(smsCode))
            .buttonParam(smsCode)
            .build();
    whatsAppSenderService.sendTemplate(requestWhatsApp);

    // ⭐ NEW: Отправить push логисту
    sendSmsCodeToLogist(cargoLoadingHistory, smsCode);
}

// ⭐ NEW: Новый метод для отправки логисту
private void sendSmsCodeToLogist(CargoLoadingHistory cargoLoadingHistory, String smsCode) {
    Transportation transportation = cargoLoadingHistory.getTransportation();
    if (transportation.getExecutorOrganization() == null) return;

    String orderNumber = transportation.getAgreementNumber();
    String customerName = cargoLoadingHistory.getContactPersonName() != null
        ? cargoLoadingHistory.getContactPersonName()
        : "Клиент";
    String address = cargoLoadingHistory.getAddress();

    // Push-уведомление логистам и админам организации-исполнителя
    transportation.getExecutorOrganization().getRoles().stream()
        .filter(role -> role.isActive())
        .filter(role -> role.getRole() == KeycloakRole.LOGISTICIAN
                     || role.getRole() == KeycloakRole.ADMIN)
        .map(OrganizationEmployeesRoles::getEmployee)
        .filter(Objects::nonNull)
        .forEach(logist -> {
            notificationService.sendNotification(
                NotificationRequest.builder()
                    .title("SMS-код доставки")
                    .body(String.format(
                        "Заказ №%s\nКлиент: %s\nАдрес: %s\nКод: %s",
                        orderNumber, customerName, address, smsCode
                    ))
                    .eventType("delivery_sms_code")
                    .employeeId(logist.getId())
                    .build()
            );
        });
}
```

### 4. Добавить SMS-код в DTO заявки для админки

**Файл**: `src/main/java/kz/coube/backend/customer/dto/CargoLoadingResponse.java`

**Было**:
```java
public record CargoLoadingResponse(
        Long id,
        LoadingType loadingType,
        // ... остальные поля
        Boolean isActive,
        Boolean isDriverAtLocation,
        Boolean isSmsRequired,
        Boolean isPhotoRequired
) {}
```

**Стало**:
```java
public record CargoLoadingResponse(
        Long id,
        LoadingType loadingType,
        // ... остальные поля
        Boolean isActive,
        Boolean isDriverAtLocation,
        Boolean isSmsRequired,
        Boolean isPhotoRequired,
        String lastSmsCode          // ⭐ NEW
) {}
```

### 5. Обновить маппер

**Файл**: `src/main/java/kz/coube/backend/customer/mapper/CustomerMapper.java`

**Метод**: `toTransportationCargo`

**Было** (последние строки):
```java
        cargoLoading.getIsActive() != null ? cargoLoading.getIsActive() : false,
        cargoLoading.getIsDriverAtLocation() != null ? cargoLoading.getIsDriverAtLocation() : false,
        cargoLoading.getIsSmsRequired(),
        cargoLoading.getIsPhotoRequired()
    );
```

**Стало**:
```java
        cargoLoading.getIsActive() != null ? cargoLoading.getIsActive() : false,
        cargoLoading.getIsDriverAtLocation() != null ? cargoLoading.getIsDriverAtLocation() : false,
        cargoLoading.getIsSmsRequired(),
        cargoLoading.getIsPhotoRequired(),
        cargoLoading.getLastSmsCode()      // ⭐ NEW
    );
```

### 6. Добавить SMS-код в детали маршрутного листа для логиста

**Файл**: `src/main/java/kz/coube/backend/courier/dto/CourierWaybillDetailResponse.java`

**Добавить класс для точек доставки**:
```java
@Data
@Builder
public class CourierWaybillDetailResponse {
    // ... существующие поля

    private List<DeliveryPointInfo> deliveryPoints;  // ⭐ NEW

    // ⭐ NEW: Вложенный класс
    @Data
    @Builder
    public static class DeliveryPointInfo {
        private Long id;
        private String address;
        private String contactNumber;
        private String contactName;
        private String lastSmsCode;         // SMS-код для этой точки
        private Boolean isActive;
        private Boolean isDriverAtLocation;
    }
}
```

### 7. Обновить сервис для возврата точек доставки с SMS-кодами

**Файл**: `src/main/java/kz/coube/backend/courier/service/CourierIntegrationService.java`

**Метод**: `getWaybillById` (строка ~319)

**Было**:
```java
public CourierWaybillDetailResponse getWaybillById(Long transportationId) {
    Transportation transportation = transportationService.findById(transportationId);

    return CourierWaybillDetailResponse.builder()
            .id(transportation.getId())
            .externalWaybillId(transportation.getExternalWaybillId())
            // ... остальные поля
            .build();
}
```

**Стало**:
```java
public CourierWaybillDetailResponse getWaybillById(Long transportationId) {
    Transportation transportation = transportationService.findById(transportationId);

    // ⭐ NEW: Собрать точки доставки с SMS-кодами
    List<DeliveryPointInfo> points = transportation.getCargoLoadings().stream()
        .sorted(Comparator.comparing(CargoLoadingHistory::getOrderNum))
        .map(cl -> DeliveryPointInfo.builder()
            .id(cl.getId())
            .address(cl.getAddress())
            .contactNumber(cl.getContactNumber())
            .contactName(cl.getContactPersonName())
            .lastSmsCode(cl.getLastSmsCode())  // SMS-код
            .isActive(cl.getIsActive())
            .isDriverAtLocation(cl.getIsDriverAtLocation())
            .build())
        .collect(Collectors.toList());

    return CourierWaybillDetailResponse.builder()
            .id(transportation.getId())
            .externalWaybillId(transportation.getExternalWaybillId())
            // ... остальные поля
            .deliveryPoints(points)  // ⭐ NEW
            .build();
}
```

---

## API Response Examples

### Для водителя (GET /api/v1/driver/orders/{id})
```json
{
  "transportationCargoInfoResponse": {
    "cargoLoadings": [{
      "id": 2617,
      "address": "Алматы, мкр. Самал-2",
      "contactNumber": "+77771234567",
      "isActive": true,
      "isDriverAtLocation": true,
      "isSmsRequired": true,
      "isPhotoRequired": false,
      "lastSmsCode": "1234"    // ✅ SMS-код для текущей точки
    }]
  }
}
```

### Для логиста (GET /api/v1/courier/waybills/{id})
```json
{
  "id": 1229,
  "externalWaybillId": "WB123456",
  "deliveryPoints": [
    {
      "id": 2617,
      "address": "Алматы, мкр. Самал-2",
      "contactNumber": "+77771234567",
      "contactName": "Иванов И.И.",
      "lastSmsCode": "1234",    // ✅ SMS-код видит логист
      "isActive": true,
      "isDriverAtLocation": true
    },
    {
      "id": 2618,
      "address": "Алматы, ул. Абая 150",
      "lastSmsCode": null,      // Еще не сгенерирован
      "isActive": false,
      "isDriverAtLocation": false
    }
  ]
}
```

### Push-уведомление логисту
```json
{
  "title": "SMS-код доставки",
  "body": "Заказ №2025-1229\nКлиент: Иванов И.И.\nАдрес: Алматы, мкр. Самал-2\nКод: 1234",
  "eventType": "delivery_sms_code",
  "employeeId": 456
}
```

---

## Тестирование

### 1. Проверить сохранение SMS-кода в БД
```sql
-- После прибытия курьера на точку
SELECT id, address, contact_number, last_sms_code
FROM gis.cargo_loading_history
WHERE transportation_id = 1229;
```

### 2. Проверить push-уведомление логисту
1. Курьер прибывает на точку с `is_sms_required = true`
2. Проверить что логист получил push с кодом
3. Проверить текст уведомления содержит SMS-код

### 3. Проверить API response для логиста
```bash
curl -X GET "https://stage-platform.coube.kz/api/v1/courier/waybills/1229" \
  -H "Authorization: Bearer {logist_token}"
```
Проверить что в `deliveryPoints` есть поле `lastSmsCode`

### 4. Проверить API response для водителя
```bash
curl -X GET "https://stage-platform.coube.kz/api/v1/driver/orders/1229" \
  -H "Authorization: Bearer {driver_token}"
```
Проверить что в `cargoLoadings` есть поле `lastSmsCode`

---

## Testing Checklist

### БД
- [ ] SMS-код сохраняется в `cargo_loading_history.last_sms_code`
- [ ] Код сохраняется сразу при генерации (не после использования)
- [ ] Старые записи имеют `last_sms_code = null`

### Push-уведомления
- [ ] Логист получает push при генерации SMS-кода
- [ ] Админ организации получает push
- [ ] В push есть: номер заказа, клиент, адрес, SMS-код
- [ ] Push приходит сразу при генерации (не после использования)

### API Response
- [ ] GET /api/v1/driver/orders возвращает `lastSmsCode`
- [ ] GET /api/v1/driver/orders/{id} возвращает `lastSmsCode`
- [ ] GET /api/v1/courier/waybills/{id} возвращает `deliveryPoints` с `lastSmsCode`
- [ ] Поле nullable (может быть null для старых/неактивных точек)

### Безопасность
- [ ] SMS-код видят только водитель, логист и админ организации-исполнителя
- [ ] Другие организации не видят SMS-код

---

## Что нужно сделать

### Backend (7 изменений)
1. ❌ Миграция БД - добавить поле `last_sms_code`
2. ❌ `CargoLoadingHistory.java` - добавить поле и getter/setter
3. ❌ `DriverService.java` - сохранять код и отправлять логисту
4. ❌ `CargoLoadingResponse.java` - добавить поле `lastSmsCode`
5. ❌ `CustomerMapper.java` - передавать `lastSmsCode` в DTO
6. ❌ `CourierWaybillDetailResponse.java` - добавить `DeliveryPointInfo`
7. ❌ `CourierIntegrationService.java` - возвращать точки с SMS-кодами

### Testing
8. ❌ Проверить сохранение в БД
9. ❌ Проверить push логисту
10. ❌ Проверить API responses

---

## Impact Analysis

### Backward Compatibility
✅ **Совместимо**: Добавление nullable поля не ломает старые клиенты

### Mobile App
✅ **Выиграет**: Мобилка сможет показывать SMS-код курьеру если нужно

### Frontend (Админка логиста)
🟡 **Требует обновления**: Нужно добавить отображение SMS-кода в UI

---

## Estimated

**Backend**: 2 часа
- Миграция БД: 15 мин
- Entity и DTO: 30 мин
- Логика сохранения и отправки: 45 мин
- Обновление API: 30 мин

**Testing**: 1 час

**Итого**: 3 часа

---

**Приоритет**: HIGH - улучшает операционную эффективность
**Риски**: Минимальные, backward compatible изменения