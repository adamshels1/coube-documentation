# 11. Добавление полей isSmsRequired и isPhotoRequired в CargoLoadingResponse

**Дата создания**: 2025-10-29
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali (Mobile Dev)

---

## Проблема

Мобильное приложение не знает, когда нужно показывать SMS подтверждение или запрашивать фото при доставке.

**Текущая ситуация**:
- ✅ Entity `CargoLoadingHistory` имеет поля `is_sms_required` и `is_photo_required` (строки 97-101)
- ✅ Endpoint обновления статуса с SMS уже реализован (`PUT /api/v1/courier/orders/{id}/courier-orders/{orderId}/status`)
- ❌ Поля НЕ возвращаются в API `GET /api/v1/driver/orders`
- ❌ Мобилка не знает когда показывать UI для SMS подтверждения

**Проблема для мобилки**: Невозможно понять нужно ли показывать кнопку "Подтвердить - СМС" когда курьер прибывает на точку.

---

## Решение

Добавить поля `isSmsRequired` и `isPhotoRequired` в DTO `CargoLoadingResponse`, чтобы мобильное приложение могло:
1. Показывать кнопку SMS подтверждения только когда `isSmsRequired = true`
2. Требовать фото только когда `isPhotoRequired = true`
3. Автоматически отправлять SMS клиенту при прибытии на точку

---

## Изменения в коде

### 1. Обновить CargoLoadingResponse.java

**Файл**: `src/main/java/kz/coube/backend/customer/dto/CargoLoadingResponse.java`

**Было**:
```java
public record CargoLoadingResponse(
        Long id,
        LoadingType loadingType,
        Integer orderNum,
        String binShipper,
        LocalDateTime loadingDateTime,
        String address,
        GeoPointDto point,
        String commentary,
        BigDecimal weight,
        WeightUnit weightUnit,
        BigDecimal volume,
        DictionaryResponse loadingMethod,
        DictionaryResponse loadingOperation,
        Integer loadingTimeHours,
        String contactNumber,
        String contactName,
        Boolean isActive,
        Boolean isDriverAtLocation) {}
```

**Стало**:
```java
public record CargoLoadingResponse(
        Long id,
        LoadingType loadingType,
        Integer orderNum,
        String binShipper,
        LocalDateTime loadingDateTime,
        String address,
        GeoPointDto point,
        String commentary,
        BigDecimal weight,
        WeightUnit weightUnit,
        BigDecimal volume,
        DictionaryResponse loadingMethod,
        DictionaryResponse loadingOperation,
        Integer loadingTimeHours,
        String contactNumber,
        String contactName,
        Boolean isActive,
        Boolean isDriverAtLocation,
        Boolean isSmsRequired,      // ⭐ NEW
        Boolean isPhotoRequired     // ⭐ NEW
) {}
```

---

### 2. Обновить CustomerMapper.java

**Файл**: `src/main/java/kz/coube/backend/customer/mapper/CustomerMapper.java`

**Метод**: `toTransportationCargo` (строки ~53-76)

**Было**:
```java
public CargoLoadingResponse toTransportationCargo(CargoLoadingHistory cargoLoading) {
    return new CargoLoadingResponse(
        cargoLoading.getId(),
        cargoLoading.getLoadingType(),
        cargoLoading.getOrderNum(),
        cargoLoading.getShipperBin(),
        cargoLoading.getLoadingDatetime(),
        cargoLoading.getAddress(),
        GeoPointDto.builder()
            .lon(cargoLoading.getLocation().getX())
            .lat(cargoLoading.getLocation().getY())
            .build(),
        cargoLoading.getCommentary(),
        cargoLoading.getWeight(),
        cargoLoading.getWeightUnit(),
        cargoLoading.getVolume(),
        DictionaryResponse.fromDictionary(cargoLoading.getLoadingMethod()),
        DictionaryResponse.fromDictionary(cargoLoading.getLoadingOperation()),
        cargoLoading.getLoadingTimeHours(),
        cargoLoading.getContactNumber(),
        cargoLoading.getContactPersonName(),
        cargoLoading.getIsActive() != null ? cargoLoading.getIsActive() : false,
        cargoLoading.getIsDriverAtLocation() != null ? cargoLoading.getIsDriverAtLocation() : false
    );
}
```

**Стало**:
```java
public CargoLoadingResponse toTransportationCargo(CargoLoadingHistory cargoLoading) {
    return new CargoLoadingResponse(
        cargoLoading.getId(),
        cargoLoading.getLoadingType(),
        cargoLoading.getOrderNum(),
        cargoLoading.getShipperBin(),
        cargoLoading.getLoadingDatetime(),
        cargoLoading.getAddress(),
        GeoPointDto.builder()
            .lon(cargoLoading.getLocation().getX())
            .lat(cargoLoading.getLocation().getY())
            .build(),
        cargoLoading.getCommentary(),
        cargoLoading.getWeight(),
        cargoLoading.getWeightUnit(),
        cargoLoading.getVolume(),
        DictionaryResponse.fromDictionary(cargoLoading.getLoadingMethod()),
        DictionaryResponse.fromDictionary(cargoLoading.getLoadingOperation()),
        cargoLoading.getLoadingTimeHours(),
        cargoLoading.getContactNumber(),
        cargoLoading.getContactPersonName(),
        cargoLoading.getIsActive() != null ? cargoLoading.getIsActive() : false,
        cargoLoading.getIsDriverAtLocation() != null ? cargoLoading.getIsDriverAtLocation() : false,
        cargoLoading.getIsSmsRequired(),      // ⭐ NEW
        cargoLoading.getIsPhotoRequired()     // ⭐ NEW
    );
}
```

---

### 3. Добавить роль DRIVER в CourierWaybillController

**Файл**: `src/main/java/kz/coube/backend/courier/controller/CourierWaybillController.java`

**Проблема**: Endpoint обновления статуса `PUT /api/v1/courier/orders/{id}/courier-orders/{orderId}/status` уже реализован (строка 81), но доступен только для ролей LOGISTICIAN и ADMIN. Водители (роль DRIVER) не могут его вызвать.

**Было** (строки ~18-22):
```java
@RestController
@AuthorizationRequired(roles = {
        KeycloakRole.LOGISTICIAN,
        KeycloakRole.ADMIN
})
@RequestMapping("/api/v1/courier")
@RequiredArgsConstructor
public class CourierWaybillController {
```

**Стало**:
```java
@RestController
@AuthorizationRequired(roles = {
        KeycloakRole.LOGISTICIAN,
        KeycloakRole.ADMIN,
        KeycloakRole.DRIVER        // ⭐ NEW - добавить доступ для водителей
})
@RequestMapping("/api/v1/courier")
@RequiredArgsConstructor
public class CourierWaybillController {
```

---

## API Response Examples

### До изменений
```json
GET /api/v1/driver/orders
{
  "content": [{
    "transportationCargoInfoResponse": {
      "cargoLoadings": [{
        "id": 2617,
        "address": "Алматы, мкр. Самал-2",
        "contactNumber": "+77771234567",
        "isActive": true,
        "isDriverAtLocation": true
        // ❌ Нет полей isSmsRequired и isPhotoRequired
      }]
    }
  }]
}
```

### После изменений
```json
GET /api/v1/driver/orders
{
  "content": [{
    "transportationCargoInfoResponse": {
      "cargoLoadings": [{
        "id": 2617,
        "address": "Алматы, мкр. Самал-2",
        "contactNumber": "+77771234567",
        "isActive": true,
        "isDriverAtLocation": true,
        "isSmsRequired": true,      // ✅ НОВОЕ ПОЛЕ
        "isPhotoRequired": false    // ✅ НОВОЕ ПОЛЕ
      }]
    }
  }]
}
```

---

## Как это работает на мобилке

### 1. Водитель прибывает на точку
```typescript
// Мобилка получает orderAtLocation
const orderAtLocation = order.cargoLoadings.find(el => el.isDriverAtLocation);

if (orderAtLocation.isSmsRequired) {
  // ✅ Показать кнопку "Подтвердить - СМС"
  // ✅ Автоматически отправить SMS клиенту
}

if (orderAtLocation.isPhotoRequired) {
  // ✅ Показать обязательную загрузку фото
}
```

### 2. Водитель подтверждает SMS
```typescript
PUT /api/v1/courier/orders/1229/courier-orders/2617/status
{
  "status": "DELIVERED",
  "smsCode": "1234"  // Код введенный клиентом
}
```

---

## Тестирование

### 1. Проверить GET /api/v1/driver/orders (список заявок)

**Шаг 1**: Добавить тестовые данные в БД
```sql
UPDATE gis.cargo_loading_history
SET
    is_sms_required = true,
    is_photo_required = false
WHERE id = 2617;
```

**Шаг 2**: Вызвать API
```bash
curl -X GET "https://stage-platform.coube.kz/api/v1/driver/orders" \
  -H "Authorization: Bearer {driver_token}"
```

**Ожидаемый результат**:
```json
{
  "cargoLoadings": [{
    "id": 2617,
    "isSmsRequired": true,
    "isPhotoRequired": false
  }]
}
```

---

### 2. Проверить GET /api/v1/driver/orders/{transportationId} (одна заявка)

**Важно**: Этот endpoint тоже использует `CargoLoadingResponse`, поэтому автоматически получит новые поля! ✅

**Шаг 1**: Вызвать API для одной заявки
```bash
curl -X GET "https://stage-platform.coube.kz/api/v1/driver/orders/1229" \
  -H "Authorization: Bearer {driver_token}"
```

**Ожидаемый результат**:
```json
{
  "transportationMainInfoResponse": {
    "id": 1229
  },
  "transportationCargoInfoResponse": {
    "cargoLoadings": [{
      "id": 2617,
      "isSmsRequired": true,
      "isPhotoRequired": false
    }]
  }
}
```

---

### 3. Проверить PUT endpoint с ролью DRIVER

**До изменений**: 403 Forbidden
```bash
curl -X PUT "https://stage-platform.coube.kz/api/v1/courier/orders/1229/courier-orders/2617/status" \
  -H "Authorization: Bearer {driver_token}" \
  -H "Content-Type: application/json" \
  -d '{"status": "DELIVERED", "smsCode": "1234"}'

# ❌ Response: 403 Forbidden
```

**После изменений**: 200 OK
```bash
curl -X PUT "https://stage-platform.coube.kz/api/v1/courier/orders/1229/courier-orders/2617/status" \
  -H "Authorization: Bearer {driver_token}" \
  -H "Content-Type: application/json" \
  -d '{"status": "DELIVERED", "smsCode": "1234"}'

# ✅ Response: 200 OK
{
  "orderId": 2617,
  "trackNumber": "TRACK001",
  "status": "DELIVERED",
  "statusDatetime": "2025-10-29T15:30:00"
}
```

---

## Что уже готово

✅ **Entity**: `CargoLoadingHistory` имеет поля (строки 97-101):
```java
@Column(name = "is_sms_required")
private Boolean isSmsRequired;

@Column(name = "is_photo_required")
private Boolean isPhotoRequired;
```

✅ **Endpoint обновления статуса**: Полностью реализован в `CourierIntegrationService.updateStatus()` (строки 407-454)

✅ **Валидатор**: `CourierOrderStatusValidator` проверяет SMS код (строки 24-28):
```java
if (point.getIsSmsRequired() &&
    request.status() == CourierOrderStatus.DELIVERED &&
    StringUtils.isBlank(request.smsCode())) {
    throw new ValidationException("SMS code is required for this delivery point");
}
```

✅ **Мобилка**: Полностью готова, ждет только эти 2 поля

✅ **Оба endpoint'а автоматически обновятся**:
- `GET /api/v1/driver/orders` (список) - используется на главном экране
- `GET /api/v1/driver/orders/{id}` (одна заявка) - используется при открытии деталей

Оба используют `CargoLoadingResponse`, поэтому одно изменение = оба endpoint'а обновлены! 🎯

---

## Что нужно сделать

### Backend (3 простых изменения)
1. ❌ `CargoLoadingResponse.java` - добавить 2 поля в конец record
2. ❌ `CustomerMapper.java` - добавить 2 поля в метод `toTransportationCargo()`
3. ❌ `CourierWaybillController.java` - добавить `KeycloakRole.DRIVER` в `@AuthorizationRequired`

### Testing
4. ❌ Проверить GET /api/v1/driver/orders возвращает новые поля (список)
5. ❌ Проверить GET /api/v1/driver/orders/{id} возвращает новые поля (одна заявка)
6. ❌ Проверить PUT endpoint доступен для роли DRIVER

---

## Testing Checklist

### API Response (GET /api/v1/driver/orders)
- [ ] Поле `isSmsRequired` возвращается в response (список заявок)
- [ ] Поле `isPhotoRequired` возвращается в response (список заявок)
- [ ] Поля nullable (могут быть null)
- [ ] Значения соответствуют БД

### API Response (GET /api/v1/driver/orders/{id})
- [ ] Поле `isSmsRequired` возвращается в response (одна заявка)
- [ ] Поле `isPhotoRequired` возвращается в response (одна заявка)
- [ ] Endpoint работает для водителя (роль DRIVER)

### Доступ к endpoint
- [ ] Роль DRIVER может вызвать PUT endpoint
- [ ] Роль LOGISTICIAN может вызвать PUT endpoint
- [ ] Роль ADMIN может вызвать PUT endpoint
- [ ] Unauthorized получает 401

### Валидация SMS
- [ ] Если `isSmsRequired=true` и статус DELIVERED, SMS код обязателен
- [ ] Если `isSmsRequired=false`, SMS код необязателен
- [ ] Корректный SMS код сохраняется в `sms_code_used`

---

## Migration не требуется

**Важно**: Поля `is_sms_required` и `is_photo_required` уже существуют в таблице `cargo_loading_history` (migration `V20250715143112__add_courier_fields.sql`).

Изменения только в **DTO и маппере**, миграции БД не нужны! ✅

---

## Impact Analysis

### Backward Compatibility
✅ **Совместимо**: Добавление nullable полей в конец record не ломает старые клиенты

### Mobile App
✅ **Готово**: Мобилка уже имеет типы и логику для этих полей
```typescript
// src/api/types.ts
export interface CargoLoadings {
  // ... existing fields
  isSmsRequired?: boolean;   // ✅ Уже добавлено
  isPhotoRequired?: boolean; // ✅ Уже добавлено
}
```

### Integration (TEEZ)
🟡 **Нейтрально**: TEEZ не использует эти поля, влияния нет

---

## References

- **Entity**: `CargoLoadingHistory.java` (строки 97-101)
- **DTO**: `CargoLoadingResponse.java`
- **Mapper**: `CustomerMapper.java` (строки 53-76)
- **Controller**: `CourierWaybillController.java` (строки 18-22, 81-95)
- **Service**: `CourierIntegrationService.java` (строки 407-454)
- **Validator**: `CourierOrderStatusValidator.java` (строки 24-28)
- **Migration**: `V20250715143112__add_courier_fields.sql`
- **Mobile Task**: `/tasks/backend/courier-delivery-integration-mvp/README.md`

---

## Notes

1. **Простая задача**: Всего 3 изменения в коде, никаких миграций БД
2. **Высокий приоритет**: Блокирует мобильное приложение
3. **Estimated**: 30 минут разработки + 15 минут тестирования
4. **Риски**: Минимальные, backward compatible изменения

---

**Приоритет**: HIGH - блокирует мобильное приложение
**Estimated**: 45 минут (разработка + тестирование)
**Dependencies**: Нет
