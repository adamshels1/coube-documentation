# 12. Добавление orders[] и данных о фото в CargoLoadingResponse

**Дата создания**: 2025-11-01
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali (Mobile Dev)

---

## Проблема

В текущем API response для транспортировок курьерской доставки не хватает критически важной информации о заказах и загруженных фотографиях.

**Текущая ситуация**:
- ❌ В `cargoLoadings[]` НЕ возвращается массив `orders[]` с заказами для каждой точки
- ❌ Нет информации о загруженных фото подтверждения доставки
- ❌ Мобилка/фронт не знает какие заказы находятся в каждой точке
- ❌ Невозможно отследить статусы отдельных заказов внутри точки

**Проблема для клиентов**:
1. Невозможно увидеть список заказов в точке доставки
2. Нет трек-номеров для отслеживания
3. Нет информации о товарных позициях
4. Нет доступа к фото подтверждений доставки

---

## Решение

Расширить `CargoLoadingResponse` DTO для включения:
1. **orders[]** - массив заказов курьерской доставки для каждой точки
2. **photoUrls[]** - массив URL загруженных фото для точки
3. **deliveryConfirmation** - данные о подтверждении доставки

---

## Изменения в коде

### 1. Создать новые DTO для заказов курьерской доставки

**Файл**: `src/main/java/kz/coube/backend/customer/dto/CourierOrderResponse.java`

```java
package kz.coube.backend.customer.dto;

import java.time.LocalDateTime;
import java.util.List;

/**
 * DTO для отображения информации о заказе в точке доставки
 */
public record CourierOrderResponse(
    Long id,
    String trackNumber,
    String externalId,
    String orderLoadType,  // "load" или "unload"
    String status,          // "pending", "delivered", "not_delivered", "returned"
    String statusReason,    // Причина недоставки
    LocalDateTime statusDatetime,
    LocalDateTime deliveryDatetime,
    List<CourierOrderPositionResponse> positions,
    String deliveryPhotoUrl,    // URL фото подтверждения
    String smsCodeUsed,         // Использованный SMS код
    String courierComment       // Комментарий курьера
) {}
```

**Файл**: `src/main/java/kz/coube/backend/customer/dto/CourierOrderPositionResponse.java`

```java
package kz.coube.backend.customer.dto;

/**
 * DTO для позиции товара в заказе
 */
public record CourierOrderPositionResponse(
    String positionCode,
    String positionShortname,
    Integer quantity,
    Integer returnedQuantity  // Количество возвращенных
) {}
```

### 2. Обновить CargoLoadingResponse.java

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
        Boolean isDriverAtLocation,
        Boolean isSmsRequired,      // Из задачи 11
        Boolean isPhotoRequired     // Из задачи 11
) {}
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
        Boolean isSmsRequired,
        Boolean isPhotoRequired,
        List<CourierOrderResponse> orders,      // ⭐ NEW - массив заказов
        List<String> photoUrls,                 // ⭐ NEW - URL фото точки
        CourierDeliveryConfirmation deliveryConfirmation  // ⭐ NEW - подтверждение доставки
) {}
```

### 3. Создать DTO для подтверждения доставки

**Файл**: `src/main/java/kz/coube/backend/customer/dto/CourierDeliveryConfirmation.java`

```java
package kz.coube.backend.customer.dto;

import java.time.LocalDateTime;

/**
 * DTO для информации о подтверждении доставки
 */
public record CourierDeliveryConfirmation(
    LocalDateTime confirmedAt,      // Время подтверждения
    String confirmedBy,             // Кто подтвердил (имя получателя)
    String confirmationType,        // "SMS", "PHOTO", "SIGNATURE"
    String smsCode,                // Использованный SMS код
    String signatureUrl,           // URL подписи (если есть)
    Boolean isFullyDelivered      // Все ли заказы доставлены
) {}
```

### 4. Обновить CustomerMapper.java

**Файл**: `src/main/java/kz/coube/backend/customer/mapper/CustomerMapper.java`

```java
@Component
@RequiredArgsConstructor
public class CustomerMapper {

    private final CourierOrderRepository courierOrderRepository;
    private final FileService fileService;

    public CargoLoadingResponse toTransportationCargo(CargoLoadingHistory cargoLoading) {
        // Получаем заказы для этой точки
        List<CourierOrderResponse> orders = getOrdersForCargoLoading(cargoLoading);

        // Получаем URL фото
        List<String> photoUrls = getPhotoUrlsForCargoLoading(cargoLoading);

        // Получаем данные о подтверждении доставки
        CourierDeliveryConfirmation confirmation = getDeliveryConfirmation(cargoLoading);

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
            cargoLoading.getIsSmsRequired(),
            cargoLoading.getIsPhotoRequired(),
            orders,                    // ⭐ NEW
            photoUrls,                 // ⭐ NEW
            confirmation               // ⭐ NEW
        );
    }

    private List<CourierOrderResponse> getOrdersForCargoLoading(CargoLoadingHistory cargoLoading) {
        // Получаем заказы из БД
        List<CourierRouteOrder> orders = courierOrderRepository
            .findByCargoLoadingId(cargoLoading.getId());

        return orders.stream()
            .map(this::toCourierOrderResponse)
            .toList();
    }

    private CourierOrderResponse toCourierOrderResponse(CourierRouteOrder order) {
        // Получаем URL фото если есть
        String photoUrl = order.getDeliveryPhotoId() != null
            ? fileService.getFileUrl(order.getDeliveryPhotoId())
            : null;

        // Получаем позиции товаров
        List<CourierOrderPositionResponse> positions = order.getPositions().stream()
            .map(pos -> new CourierOrderPositionResponse(
                pos.getPositionCode(),
                pos.getPositionShortname(),
                pos.getQuantity(),
                pos.getReturnedQuantity()
            ))
            .toList();

        return new CourierOrderResponse(
            order.getId(),
            order.getTrackNumber(),
            order.getExternalId(),
            order.getOrderLoadType().toString(),
            order.getStatus() != null ? order.getStatus().toString() : "pending",
            order.getStatusReason(),
            order.getStatusDatetime(),
            order.getDeliveryDatetime(),
            positions,
            photoUrl,
            order.getSmsCodeUsed(),
            order.getCourierComment()
        );
    }

    private List<String> getPhotoUrlsForCargoLoading(CargoLoadingHistory cargoLoading) {
        // Получаем все фото связанные с точкой
        List<String> photoIds = courierOrderRepository
            .findPhotoIdsByCargoLoadingId(cargoLoading.getId());

        return photoIds.stream()
            .filter(Objects::nonNull)
            .map(fileService::getFileUrl)
            .toList();
    }

    private CourierDeliveryConfirmation getDeliveryConfirmation(CargoLoadingHistory cargoLoading) {
        // Проверяем есть ли подтверждение доставки
        if (cargoLoading.getDepartureDateTime() == null) {
            return null; // Еще не покинули точку
        }

        // Получаем данные о подтверждении
        List<CourierRouteOrder> orders = courierOrderRepository
            .findByCargoLoadingId(cargoLoading.getId());

        boolean allDelivered = orders.stream()
            .allMatch(o -> "delivered".equals(o.getStatus()));

        String smsCode = orders.stream()
            .map(CourierRouteOrder::getSmsCodeUsed)
            .filter(Objects::nonNull)
            .findFirst()
            .orElse(null);

        return new CourierDeliveryConfirmation(
            cargoLoading.getDepartureDateTime(),
            cargoLoading.getContactPersonName(),
            cargoLoading.getIsSmsRequired() ? "SMS" : "PHOTO",
            smsCode,
            null, // signature URL если будет реализовано
            allDelivered
        );
    }
}
```

### 5. Создать Repository для заказов

**Файл**: `src/main/java/kz/coube/backend/courier/repository/CourierOrderRepository.java`

```java
package kz.coube.backend.courier.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface CourierOrderRepository extends JpaRepository<CourierRouteOrder, Long> {

    /**
     * Найти все заказы для точки маршрута
     */
    List<CourierRouteOrder> findByCargoLoadingId(Long cargoLoadingId);

    /**
     * Найти все ID фото для точки маршрута
     */
    @Query("""
        SELECT o.deliveryPhotoId
        FROM CourierRouteOrder o
        WHERE o.cargoLoadingId = :cargoLoadingId
        AND o.deliveryPhotoId IS NOT NULL
    """)
    List<String> findPhotoIdsByCargoLoadingId(@Param("cargoLoadingId") Long cargoLoadingId);

    /**
     * Найти заказы по трек-номерам
     */
    List<CourierRouteOrder> findByTrackNumberIn(List<String> trackNumbers);
}
```

---

## API Response Examples

### До изменений

```json
GET /api/v1/customer/transportations/1269
{
  "transportationCargoInfoResponse": {
    "cargoLoadings": [{
      "id": 2738,
      "loadingType": {
        "code": "UNLOADING"
      },
      "orderNum": 2,
      "address": "Алматы, мкр. Самал-2, дом 22, кв. 12",
      "point": {
        "lon": 76.9562,
        "lat": 43.2385
      },
      "contactNumber": "+77478777626",
      "contactName": "Иванов Иван Иванович",
      "isSmsRequired": true,
      "isPhotoRequired": true
      // ❌ НЕТ orders[]
      // ❌ НЕТ photoUrls[]
      // ❌ НЕТ deliveryConfirmation
    }]
  }
}
```

### После изменений

```json
GET /api/v1/customer/transportations/1269
{
  "transportationCargoInfoResponse": {
    "cargoLoadings": [{
      "id": 2738,
      "loadingType": {
        "code": "UNLOADING"
      },
      "orderNum": 2,
      "address": "Алматы, мкр. Самал-2, дом 22, кв. 12",
      "point": {
        "lon": 76.9562,
        "lat": 43.2385
      },
      "contactNumber": "+77478777626",
      "contactName": "Иванов Иван Иванович",
      "isSmsRequired": true,
      "isPhotoRequired": true,
      "orders": [                           // ✅ NEW
        {
          "id": 1001,
          "trackNumber": "TRACK-85",
          "externalId": "ORDER-TEEZ-001",
          "orderLoadType": "unload",
          "status": "delivered",
          "statusReason": null,
          "statusDatetime": "2025-01-07T10:15:00Z",
          "deliveryDatetime": "2025-01-07T10:15:00Z",
          "positions": [
            {
              "positionCode": "POS-001",
              "positionShortname": "Товар 1",
              "quantity": 1,
              "returnedQuantity": 0
            },
            {
              "positionCode": "POS-002",
              "positionShortname": "Товар 2",
              "quantity": 1,
              "returnedQuantity": 0
            }
          ],
          "deliveryPhotoUrl": "https://s3.coube.kz/courier/photos/1234.jpg",
          "smsCodeUsed": "5678",
          "courierComment": null
        }
      ],
      "photoUrls": [                       // ✅ NEW
        "https://s3.coube.kz/courier/photos/1234.jpg"
      ],
      "deliveryConfirmation": {           // ✅ NEW
        "confirmedAt": "2025-01-07T10:20:00Z",
        "confirmedBy": "Иванов Иван Иванович",
        "confirmationType": "SMS",
        "smsCode": "5678",
        "signatureUrl": null,
        "isFullyDelivered": true
      }
    }]
  }
}
```

### Для мобильного приложения (GET /api/v1/driver/orders)

```json
{
  "content": [{
    "transportationCargoInfoResponse": {
      "cargoLoadings": [{
        "id": 2738,
        "address": "Алматы, мкр. Самал-2, дом 22, кв. 12",
        "contactNumber": "+77478777626",
        "contactName": "Иванов Иван Иванович",
        "isActive": true,
        "isDriverAtLocation": true,
        "isSmsRequired": true,
        "isPhotoRequired": true,
        "orders": [                        // ✅ Заказы в точке
          {
            "id": 1001,
            "trackNumber": "TRACK-85",
            "externalId": "ORDER-TEEZ-001",
            "status": "pending",          // Еще не доставлен
            "positions": [
              {
                "positionCode": "POS-001",
                "positionShortname": "Товар 1",
                "quantity": 1
              }
            ],
            "deliveryPhotoUrl": null      // Фото еще нет
          }
        ],
        "photoUrls": [],                  // Фото еще не загружены
        "deliveryConfirmation": null      // Еще не подтверждено
      }]
    }
  }]
}
```

---

## База данных

### Таблица courier_route_order (уже существует из задачи 01)

```sql
CREATE TABLE courier_route_order (
    id BIGSERIAL PRIMARY KEY,
    cargo_loading_id BIGINT NOT NULL REFERENCES gis.cargo_loading_history(id),
    track_number VARCHAR(100) NOT NULL,
    external_id VARCHAR(100),
    order_load_type VARCHAR(50) NOT NULL,
    status VARCHAR(50),
    status_reason VARCHAR(255),
    status_datetime TIMESTAMP,
    delivery_datetime TIMESTAMP,
    delivery_photo_id VARCHAR(255),
    sms_code_used VARCHAR(10),
    courier_comment TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE(track_number, cargo_loading_id)
);

CREATE INDEX idx_courier_route_order_cargo_loading ON courier_route_order(cargo_loading_id);
CREATE INDEX idx_courier_route_order_track ON courier_route_order(track_number);
```

### Таблица courier_order_position (уже существует из задачи 01)

```sql
CREATE TABLE courier_order_position (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES courier_route_order(id),
    position_code VARCHAR(100) NOT NULL,
    position_shortname VARCHAR(255),
    quantity INTEGER DEFAULT 1,
    returned_quantity INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_courier_order_position_order ON courier_order_position(order_id);
```

---

## Тестирование

### 1. Проверить GET /api/v1/customer/transportations/{id}

```bash
curl -X GET "http://localhost:5173/api/v1/customer/transportations/1269" \
  -H "Authorization: Bearer {token}"
```

**Ожидаемый результат**:
- ✅ Каждый `cargoLoading` содержит массив `orders[]`
- ✅ Для доставленных заказов есть `deliveryPhotoUrl`
- ✅ Если точка завершена, есть `deliveryConfirmation`

### 2. Проверить GET /api/v1/driver/orders

```bash
curl -X GET "https://stage-platform.coube.kz/api/v1/driver/orders" \
  -H "Authorization: Bearer {driver_token}"
```

**Ожидаемый результат**:
- ✅ Водитель видит заказы в каждой точке
- ✅ Видны трек-номера и позиции товаров
- ✅ Для завершенных доставок отображаются фото

### 3. Проверить изменение статуса заказа

```bash
# Доставить заказ
curl -X PUT "https://stage-platform.coube.kz/api/v1/courier/orders/1269/courier-orders/1001/status" \
  -H "Authorization: Bearer {driver_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "delivered",
    "smsCode": "1234",
    "photoId": "550e8400-e29b-41d4-a716-446655440000"
  }'

# Проверить обновление
curl -X GET "http://localhost:5173/api/v1/customer/transportations/1269" \
  -H "Authorization: Bearer {token}"
```

**Ожидаемый результат**:
- ✅ Статус заказа изменился на `delivered`
- ✅ Появился `deliveryPhotoUrl` с ссылкой на фото
- ✅ Заполнен `smsCodeUsed`

---

## Testing Checklist

### API Response Structure
- [ ] `orders[]` возвращается для каждого `cargoLoading`
- [ ] Каждый order содержит `trackNumber` и `externalId`
- [ ] Позиции товаров (`positions[]`) правильно отображаются
- [ ] URL фото корректно формируются через FileService

### Статусы заказов
- [ ] Статус `pending` для новых заказов
- [ ] Статус `delivered` после успешной доставки
- [ ] Статус `not_delivered` при недоставке
- [ ] Статус `returned` при возврате на склад

### Фото подтверждения
- [ ] `deliveryPhotoUrl` появляется после загрузки фото
- [ ] `photoUrls[]` содержит все фото точки
- [ ] URL фото доступны для скачивания

### Подтверждение доставки
- [ ] `deliveryConfirmation` заполняется после завершения точки
- [ ] `confirmationType` корректно определяется (SMS/PHOTO)
- [ ] `isFullyDelivered` правильно вычисляется

### Совместимость
- [ ] Старые клиенты работают (nullable поля)
- [ ] FLT перевозки не затронуты
- [ ] Существующие тесты проходят

---

## Зависимости

### Требуется до начала
- ✅ Таблица `courier_route_order` (из задачи 01-mvp-plan.md)
- ✅ Таблица `courier_order_position` (из задачи 01-mvp-plan.md)
- ✅ FileService для генерации URL фото
- ✅ Поля `isSmsRequired` и `isPhotoRequired` (из задачи 11)

### Блокирует
- 🔒 Мобильное приложение - отображение заказов в точках
- 🔒 Веб-интерфейс - просмотр деталей доставки
- 🔒 TEEZ интеграция - получение статусов заказов

---

## Оценка времени

### Backend разработка: 4-6 часов
- Entity и Repository: 1 час
- DTO и маппинг: 2 часа
- Сервисная логика: 1-2 часа
- Тестирование: 1 час

### Frontend/Mobile адаптация: 2-3 часа
- Обновление типов: 30 минут
- UI для отображения заказов: 1-2 часа
- Тестирование: 30 минут

**Общая оценка**: 6-9 часов

---

## Риски

### Технические
- 🟡 **Производительность**: При большом количестве заказов может замедлиться загрузка
  - **Митигация**: Добавить пагинацию или ленивую загрузку

- 🟡 **Размер response**: Увеличится размер JSON ответа
  - **Митигация**: Опциональный параметр `includeOrders=true`

### Бизнес
- 🟢 **Минимальные**: Расширение существующего функционала

---

## Альтернативные решения

### Вариант 1: Отдельный endpoint для заказов
```
GET /api/v1/customer/transportations/{id}/cargo-loadings/{loadingId}/orders
```
**Плюсы**: Меньше данных в основном response
**Минусы**: Дополнительные запросы, усложнение клиента

### Вариант 2: GraphQL
**Плюсы**: Гибкость запросов
**Минусы**: Требует внедрения GraphQL инфраструктуры

### Выбранное решение
Расширение существующего DTO - оптимальный баланс между удобством и производительностью.

---

## References

- **Entity**: `CourierRouteOrder.java` (из задачи 01)
- **DTO**: `CargoLoadingResponse.java`
- **Mapper**: `CustomerMapper.java`
- **Service**: `CourierIntegrationService.java`
- **Controller**: `CustomerTransportationController.java`, `DriverController.java`
- **Связанные задачи**: 01-mvp-plan.md, 11-add-sms-photo-required-fields.md

---

## Notes

1. **Критически важно**: Эта задача блокирует полноценную работу курьерской доставки
2. **Backward compatibility**: Все новые поля nullable для совместимости
3. **Performance**: Рассмотреть кеширование для часто запрашиваемых данных
4. **Security**: URL фото должны быть защищены (проверка прав доступа)

---

**Приоритет**: HIGH - блокирует мобильное приложение и веб-интерфейс
**Estimated**: 6-9 часов (backend + frontend)
**Dependencies**: Задачи 01 и 11 должны быть выполнены
**Статус**: TO DO