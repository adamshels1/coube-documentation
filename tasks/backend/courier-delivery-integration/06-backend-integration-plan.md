# 06. План интеграции в существующий backend

## Обзор текущей архитектуры

### Структура модулей
Coube Backend построен на модульной архитектуре:
- `applications` - заявки на перевозки
- `driver` - функционал для водителей
- `customer` - функционал для заказчиков
- `executor` - функционал для перевозчиков
- `dictionaries` - справочники
- `auth` - аутентификация и авторизация (Keycloak)
- `organization` - управление организациями и сотрудниками
- `route` - маршруты перевозок
- `notifications` - система уведомлений

### Текущий функционал водителей

**Существующая роль**: `KeycloakRole.DRIVER`  
**Контроллер**: `DriverController` (`/api/v1/driver`)  
**Основные эндпоинты**:
- `GET /orders` - список заказов водителя
- `GET /orders/{id}` - детали заказа
- `PUT /orders/{id}/accept` - принять заказ
- `PUT /orders/{id}/reject` - отклонить заказ
- `PUT /orders/{id}/start` - начать выполнение
- `PUT /orders/{id}/arrival` - прибытие на точку
- `PUT /orders/{id}/departure` - отправление с точки
- `POST /orders/{id}/sos` - SOS сигнал
- `GET /profile/{employeeId}` - профиль водителя

### Текущие типы перевозок

**Enum**: `TransportationType`  
**Значения**:
- `FTL` - Магистральные перевозки
- `BULK` - Сыпучие материалы
- `CITY` - Перевозки по городу
- `LTL` - Сборные перевозки

### Текущие роли

**Enum**: `KeycloakRole`  
**Org roles**: `EXECUTOR`, `CUSTOMER`  
**Admin roles**: `CEO`, `ADMIN`, `SIGNER`  
**Employee roles**: `DRIVER`, `LOGISTICIAN`, `ACCOUNTANT`  
**Super admin**: `SUPER_ADMIN`

---

## Изменения в существующих компонентах

### 1. Enum `TransportationType`

**Файл**: `/src/main/java/kz/coube/backend/dictionaries/enumeration/TransportationType.java`

**Добавить**:
```java
public enum TransportationType {
  FTL,
  BULK,
  CITY,
  LTL,
  COURIER_DELIVERY; // ← НОВОЕ: Курьерская доставка (универсальная для всех маркетплейсов)

  // ... existing methods
}
```

**Добавить в messages.properties**:
```properties
enum.transportation-type.COURIER_DELIVERY.kk=Курьерлік жеткізу
enum.transportation-type.COURIER_DELIVERY.ru=Курьерская доставка
enum.transportation-type.COURIER_DELIVERY.en=Courier delivery
enum.transportation-type.COURIER_DELIVERY.zh=快递
```

### 2. Enum `KeycloakRole`

**Файл**: `/src/main/java/kz/coube/backend/auth/roles/KeycloakRole.java`

**НЕ ТРЕБУЕТСЯ** изменений!  
Используем существующую роль `DRIVER` для курьеров.  
Различие между FLT-водителем и курьером определяется типом заявки и назначенным транспортом.

**Логика разделения**:
- `DRIVER` + `TransportationType.FTL/BULK/CITY/LTL` = обычный водитель
- `DRIVER` + `TransportationType.COURIER_DELIVERY` = курьер

### 3. Entity `Transportation`

**Файл**: `/src/main/java/kz/coube/backend/applications/entity/Transportation.java`

**Добавить поля**:
```java
@Entity
@Table(name = "transportation", schema = "applications")
public class Transportation {
  
  // ... existing fields
  
  // Новые поля для курьерской доставки
  @Column(name = "source_system")
  private String sourceSystem; // TEEZ_PVZ, KASPI, WILDBERRIES, OZON
  
  @Column(name = "external_waybill_id")
  private String externalWaybillId;
  
  @Column(name = "delivery_type")
  private String deliveryType; // courier, marketplacedelivery
  
  @Column(name = "responsible_courier_warehouse_id")
  private String responsibleCourierWarehouseId;
  
  @Column(name = "target_delivery_day")
  private LocalDate targetDeliveryDay;
  
  @Column(name = "validation_status")
  @Enumerated(EnumType.STRING)
  private CourierValidationStatus validationStatus; // imported_draft, validated, assigned, in_route, completed, closed
  
  // One-to-Many relationship
  @OneToMany(mappedBy = "transportation", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<CourierRoutePoint> routePoints = new ArrayList<>();
}
```

**Добавить enum**:
```java
public enum CourierValidationStatus {
  IMPORTED_DRAFT,
  VALIDATED,
  ASSIGNED,
  IN_ROUTE,
  COMPLETED,
  CLOSED
}
```

### 4. Добавить таблицу связи Employee ↔ PrimaryPickupPoint

**Файл**: `/src/main/java/kz/coube/backend/organization/entity/Employee.java`

**Добавить поля**:
```java
@Entity
@Table(name = "employee", schema = "users")
public class Employee {
  
  // ... existing fields
  
  @Column(name = "primary_pickup_point_id")
  private String primaryPickupPointId; // для курьеров
  
  @Column(name = "integration_data", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String integrationData; // [{system: "TEEZ_PVZ", external_id: "123"}]
  
  @Column(name = "current_status")
  @Enumerated(EnumType.STRING)
  private EmployeeStatus currentStatus; // для водителей/курьеров
}
```

**Добавить enum**:
```java
public enum EmployeeStatus {
  FREE,
  IN_ROUTE,
  UNAVAILABLE
}
```

---

## Новые entity и репозитории

### 1. CourierRoutePoint

**Package**: `kz.coube.backend.applications.entity`

```java
@Entity
@Table(name = "courier_route_point", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierRoutePoint extends AuditEntity {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "transportation_id", nullable = false)
  private Transportation transportation;
  
  @Column(name = "sort_order", nullable = false)
  private Integer sortOrder;
  
  @Column(name = "is_courier_warehouse", nullable = false)
  private Boolean isCourierWarehouse;
  
  @Column(name = "warehouse_id")
  private String warehouseId;
  
  @Column(name = "address")
  private String address;
  
  @Column(name = "longitude")
  private BigDecimal longitude;
  
  @Column(name = "latitude")
  private BigDecimal latitude;
  
  @Column(name = "delivery_desired_datetime")
  private Instant deliveryDesiredDatetime;
  
  @Column(name = "delivery_desired_datetime_after")
  private Instant deliveryDesiredDatetimeAfter;
  
  @Column(name = "delivery_desired_datetime_before")
  private Instant deliveryDesiredDatetimeBefore;
  
  @Column(name = "is_sms_required")
  private Boolean isSmsRequired;
  
  @Column(name = "is_photo_required")
  private Boolean isPhotoRequired;
  
  @Column(name = "load_type")
  private String loadType; // unload, load
  
  @Column(name = "receiver_name")
  private String receiverName;
  
  @Column(name = "receiver_phone")
  private String receiverPhone;
  
  @Column(name = "comment", columnDefinition = "TEXT")
  private String comment;
  
  @Column(name = "status")
  @Enumerated(EnumType.STRING)
  private CourierPointStatus status;
  
  @Column(name = "status_datetime")
  private Instant statusDatetime;
  
  @OneToMany(mappedBy = "routePoint", cascade = CascadeType.ALL, orphanRemoval = true)
  @OrderBy("id ASC")
  private List<CourierRouteOrder> orders = new ArrayList<>();
}
```

### 2. CourierRouteOrder

```java
@Entity
@Table(name = "courier_route_order", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierRouteOrder extends AuditEntity {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "route_point_id", nullable = false)
  private CourierRoutePoint routePoint;
  
  @Column(name = "track_number", nullable = false, unique = true)
  private String trackNumber;
  
  @Column(name = "external_id", nullable = false)
  private String externalId;
  
  @Column(name = "teezpost_id")
  private String teezpostId;
  
  @Column(name = "load_type", nullable = false)
  private String loadType;
  
  @Column(name = "status", nullable = false)
  @Enumerated(EnumType.STRING)
  private CourierOrderStatus status;
  
  @Column(name = "status_reason")
  @Enumerated(EnumType.STRING)
  private CourierOrderStatusReason statusReason;
  
  @Column(name = "status_datetime")
  private Instant statusDatetime;
  
  @Column(name = "sms_code_used")
  private String smsCodeUsed;
  
  @Column(name = "photo_id")
  private UUID photoId;
  
  @Column(name = "courier_comment", columnDefinition = "TEXT")
  private String courierComment;
  
  @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
  private List<CourierRoutePosition> positions = new ArrayList<>();
}
```

### 3. CourierRoutePosition

```java
@Entity
@Table(name = "courier_route_position", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierRoutePosition extends AuditEntity {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "order_id", nullable = false)
  private CourierRouteOrder order;
  
  @Column(name = "position_code", nullable = false)
  private String positionCode;
  
  @Column(name = "position_shortname", nullable = false)
  private String positionShortname;
  
  @Column(name = "quantity")
  private Integer quantity = 1;
  
  @Column(name = "returned_quantity")
  private Integer returnedQuantity = 0;
}
```

### 4. CourierWarehouse (Dictionary)

**Package**: `kz.coube.backend.dictionaries.entity`

```java
@Entity
@Table(name = "courier_warehouse", schema = "dictionaries")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierWarehouse extends AuditEntity {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @Column(name = "name", nullable = false)
  private String name;
  
  @Column(name = "is_pickup_point", nullable = false)
  private Boolean isPickupPoint;
  
  @Column(name = "integration_system", nullable = false)
  private String integrationSystem; // TEEZ_PVZ
  
  @Column(name = "external_id", nullable = false)
  private String externalId;
  
  @Column(name = "address", nullable = false)
  private String address;
  
  @Column(name = "longitude")
  private BigDecimal longitude;
  
  @Column(name = "latitude")
  private BigDecimal latitude;
  
  @Column(name = "is_active", nullable = false)
  private Boolean isActive = true;
}
```

### 5. CourierRouteLog

```java
@Entity
@Table(name = "courier_route_log", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierRouteLog {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @Column(name = "transportation_id", nullable = false)
  private Long transportationId;
  
  @Column(name = "event_type", nullable = false)
  @Enumerated(EnumType.STRING)
  private CourierEventType eventType;
  
  @Column(name = "event_datetime", nullable = false)
  private Instant eventDatetime;
  
  @Column(name = "actor_id")
  private Long actorId;
  
  @Column(name = "actor_type")
  @Enumerated(EnumType.STRING)
  private CourierActorType actorType;
  
  @Column(name = "details", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String details;
  
  @Column(name = "description", columnDefinition = "TEXT")
  private String description;
  
  @Column(name = "created_at", nullable = false)
  private Instant createdAt;
  
  @Column(name = "created_by", nullable = false)
  private String createdBy;
}
```

### 6. CourierIntegrationLog

```java
@Entity
@Table(name = "courier_integration_log", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierIntegrationLog {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @Column(name = "integration_type", nullable = false)
  @Enumerated(EnumType.STRING)
  private IntegrationType integrationType; // incoming, outgoing
  
  @Column(name = "source_system", nullable = false)
  private String sourceSystem; // TEEZ_PVZ
  
  @Column(name = "endpoint", nullable = false)
  private String endpoint;
  
  @Column(name = "http_method", nullable = false)
  private String httpMethod;
  
  @Column(name = "object_type", nullable = false)
  private String objectType; // waybill, order_result
  
  @Column(name = "object_id")
  private String objectId;
  
  @Column(name = "request_payload", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String requestPayload;
  
  @Column(name = "response_payload", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String responsePayload;
  
  @Column(name = "http_status_code")
  private Integer httpStatusCode;
  
  @Column(name = "status", nullable = false)
  @Enumerated(EnumType.STRING)
  private IntegrationStatus status; // success, failure, retry
  
  @Column(name = "error_message", columnDefinition = "TEXT")
  private String errorMessage;
  
  @Column(name = "retry_count")
  private Integer retryCount = 0;
  
  @Column(name = "request_datetime", nullable = false)
  private Instant requestDatetime;
  
  @Column(name = "response_datetime")
  private Instant responseDatetime;
  
  @Column(name = "created_at", nullable = false)
  private Instant createdAt;
}
```

---

## Новые Enums

```java
// Package: kz.coube.backend.dictionaries.enumeration

public enum CourierPointStatus {
  PENDING,
  ARRIVED,
  COMPLETED,
  SKIPPED
}

public enum CourierOrderStatus {
  PENDING,
  DELIVERED,
  RETURNED,
  PARTIALLY_RETURNED,
  NOT_DELIVERED,
  NOT_REACHED
}

public enum CourierOrderStatusReason {
  CUSTOMER_NOT_AVAILABLE,
  CUSTOMER_POSTPONED,
  FORCE_MAJEURE
}

public enum CourierEventType {
  IMPORTED,
  VALIDATED,
  ASSIGNED,
  STARTED,
  POINT_COMPLETED,
  COMPLETED,
  CLOSED
}

public enum CourierActorType {
  LOGIST,
  COURIER,
  SYSTEM,
  INTEGRATION
}

public enum IntegrationType {
  INCOMING,
  OUTGOING
}

public enum IntegrationStatus {
  SUCCESS,
  FAILURE,
  RETRY
}
```

---

## Новые контроллеры

### 1. CourierIntegrationController

**Package**: `kz.coube.backend.integration.api`  
**Base Path**: `/api/v1/integration/teez`

**Эндпоинты**:
- `POST /waybills` - создание/обновление маршрутного листа
- `PUT /waybills/{externalWaybillId}` - обновление черновика
- `GET /waybills/{externalWaybillId}` - получение маршрутного листа
- `GET /waybills/{externalWaybillId}/orders` - статусы заказов
- `POST /problem-address` - пометка проблемного адреса

**Авторизация**: Отдельный Keycloak client с scope `courier:integration`

### 2. CourierLogistController

**Package**: `kz.coube.backend.courier.api`  
**Base Path**: `/api/v1/courier`  
**Roles**: `LOGISTICIAN`, `ADMIN`, `CEO`

**Эндпоинты**:
- `GET /waybills` - список маршрутных листов
- `GET /waybills/{id}` - детали маршрутного листа
- `PUT /waybills/{id}` - редактирование маршрута
- `POST /waybills/{id}/validate` - валидация маршрута
- `POST /waybills/{id}/assign` - назначение курьера
- `POST /waybills/{id}/unassign` - снятие курьера
- `POST /waybills/{id}/close` - закрытие маршрута
- `GET /couriers` - список курьеров
- `POST /couriers` - создание курьера
- `PATCH /couriers/{id}` - обновление курьера

### 3. CourierMobileController

**Package**: `kz.coube.backend.courier.api`  
**Base Path**: `/api/v1/courier/mobile`  
**Roles**: `DRIVER` (курьеры)

**Эндпоинты**:
- `GET /waybills/active` - активный маршрут
- `GET /waybills/history` - история маршрутов
- `POST /waybills/{id}/accept` - принять маршрут
- `POST /waybills/{id}/decline` - отклонить маршрут
- `POST /waybills/{id}/start` - начать маршрут
- `POST /waybills/{id}/points/{pointId}/status` - изменить статус точки
- `POST /waybills/{id}/complete` - завершить маршрут
- `POST /waybills/{id}/finish` - подтвердить возврат на склад
- `POST /upload-photo` - загрузить фото
- `POST /location` - отправить геолокацию
- `GET /dashboard` - сводка для курьера
- `POST /report-problem` - сообщить о проблеме
- `POST /sos` - экстренный вызов

**Использует существующий**:
- `DriverLocationController` - для геолокации (уже есть!)

---

## Новые сервисы

### 1. CourierIntegrationService

**Ответственность**:
- Прием маршрутных листов от TEEZ_PVZ
- Валидация входящих данных
- Создание/обновление Transportation с типом COURIER_DELIVERY
- Логирование интеграций

### 2. CourierWaybillService

**Ответственность**:
- CRUD операции с маршрутными листами
- Валидация маршрутов логистом
- Назначение/снятие курьеров
- Управление статусами

### 3. CourierMobileService

**Ответственность**:
- Работа с маршрутами курьера
- Обработка статусов точек и заказов
- Загрузка фото подтверждений
- SOS функционал (переиспользовать из DriverService)

### 4. CourierResultsService

**Ответственность**:
- Формирование результатов для отправки в TEEZ
- Постановка в очередь
- Ретраи

### 5. CourierWarehouseService

**Ответственность**:
- Управление справочником складов/ПВЗ
- Загрузка из внешних систем

---

## Репозитории

```java
// Package: kz.coube.backend.applications.repository

public interface CourierRoutePointRepository extends JpaRepository<CourierRoutePoint, Long> {
  List<CourierRoutePoint> findByTransportationIdOrderBySortOrderAsc(Long transportationId);
}

public interface CourierRouteOrderRepository extends JpaRepository<CourierRouteOrder, Long> {
  Optional<CourierRouteOrder> findByTrackNumber(String trackNumber);
  List<CourierRouteOrder> findByRoutePointId(Long routePointId);
}

public interface CourierRoutePositionRepository extends JpaRepository<CourierRoutePosition, Long> {
  List<CourierRoutePosition> findByOrderId(Long orderId);
}

public interface CourierRouteLogRepository extends JpaRepository<CourierRouteLog, Long> {
  List<CourierRouteLog> findByTransportationIdOrderByEventDatetimeDesc(Long transportationId);
}

public interface CourierIntegrationLogRepository extends JpaRepository<CourierIntegrationLog, Long> {
  List<CourierIntegrationLog> findByObjectTypeAndObjectId(String objectType, String objectId);
  List<CourierIntegrationLog> findByStatusAndRetryCountLessThan(IntegrationStatus status, Integer maxRetries);
}

// Package: kz.coube.backend.dictionaries.repository

public interface CourierWarehouseRepository extends JpaRepository<CourierWarehouse, Long> {
  Optional<CourierWarehouse> findByIntegrationSystemAndExternalId(String integrationSystem, String externalId);
  List<CourierWarehouse> findByIsActiveTrue();
}
```

---

## DTO классы

### Request DTOs

```java
// Package: kz.coube.backend.integration.dto

@Data @Builder
public class WaybillImportRequest {
  private String sourceSystem;
  private WaybillHeader waybill;
  private List<DeliveryPoint> deliveries;
}

@Data
public class WaybillHeader {
  private String id;
  private String deliveryType;
  private String responsibleCourierWarehouseId;
  private LocalDate targetDeliveryDay;
}

@Data
public class DeliveryPoint {
  private Integer sort;
  private Boolean isCourierWarehouse;
  private String loadType;
  private Instant deliveryDesiredDatetime;
  private Instant deliveryDesiredDatetimeAfter;
  private Instant deliveryDesiredDatetimeBefore;
  private String warehouseId;
  private String address;
  private Boolean isSmsRequired;
  private Boolean isPhotoRequired;
  private String comment;
  private ReceiverInfo receiver;
  private List<OrderInfo> orders;
}

@Data
public class ReceiverInfo {
  private String name;
  private String phone;
}

@Data
public class OrderInfo {
  private String trackNumber;
  private String externalId;
  private String teezpostId;
  private String orderLoadType;
  private List<PositionInfo> positions;
}

@Data
public class PositionInfo {
  private String positionCode;
  private String positionShortname;
}
```

### Response DTOs

```java
// Package: kz.coube.backend.courier.dto

@Data @Builder
public class WaybillImportResponse {
  private String status; // imported, updated, locked, validation_failed
  private Long transportationId;
  private String externalWaybillId;
  private String validationStatus;
  private Instant createdAt;
  private Instant updatedAt;
  private Integer routePointsCount;
  private Integer ordersCount;
  private String message;
  private List<ValidationError> errors;
}

@Data @Builder
public class ValidationError {
  private String field;
  private String code;
  private String message;
  private Object value;
}

@Data @Builder
public class CourierWaybillResponse {
  private Long id;
  private String externalWaybillId;
  private String sourceSystem;
  private String deliveryType;
  private String validationStatus;
  // ... все поля из спецификации API
}
```

---

## Миграции Flyway

**Расположение**: `/src/main/resources/db/migration/`

**Файлы** (по порядку):
1. `V2025_01_15_01__add_courier_delivery_transport_type.sql`
2. `V2025_01_15_02__add_courier_fields_to_transportation.sql`
3. `V2025_01_15_03__add_courier_fields_to_employee.sql`
4. `V2025_01_15_04__create_courier_route_point_table.sql`
5. `V2025_01_15_05__create_courier_route_order_table.sql`
6. `V2025_01_15_06__create_courier_route_position_table.sql`
7. `V2025_01_15_07__create_courier_route_log_table.sql`
8. `V2025_01_15_08__create_courier_integration_log_table.sql`
9. `V2025_01_15_09__create_courier_warehouse_table.sql`
10. `V2025_01_15_10__add_courier_enums_and_constraints.sql`

---

## Конфигурация

### application.yml

```yaml
courier:
  integration:
    marketplaces:
      teez:
        enabled: true
        api-url: ${TEEZ_API_URL:https://teez-api.example.com}
        api-token: ${TEEZ_API_TOKEN}
        endpoint: /api/waybill/results
      kaspi:
        enabled: false
        api-url: ${KASPI_API_URL}
        api-token: ${KASPI_API_TOKEN}
        endpoint: /api/v1/courier/delivery-results
      wildberries:
        enabled: false
        api-url: ${WILDBERRIES_API_URL}
        api-token: ${WILDBERRIES_API_TOKEN}
        endpoint: /api/v3/delivery/results
    retry:
      max-attempts: 48
      interval-minutes: 30
      max-duration-hours: 24
    rate-limit:
      requests-per-minute: 60
  
  mobile:
    location-tracking:
      interval-seconds: 30
      accuracy-threshold-meters: 100
    
    photo:
      max-size-mb: 5
      allowed-formats: [JPEG, PNG]
      storage-path: courier/photos
```

### Keycloak Configuration

**Новый клиент**: `coube-integration-teez`
- **Grant Type**: Client Credentials
- **Scope**: `courier:integration`
- **Service Account**: enabled

---

## Планы тестирования

### Unit Tests

1. `CourierIntegrationServiceTest` - тесты импорта маршрутных листов
2. `CourierWaybillServiceTest` - тесты валидации и назначения
3. `CourierMobileServiceTest` - тесты мобильного API
4. `CourierResultsServiceTest` - тесты отправки результатов

### Integration Tests

1. `CourierIntegrationControllerIT` - тесты REST API интеграции
2. `CourierLogistControllerIT` - тесты веб-интерфейса
3. `CourierMobileControllerIT` - тесты мобильного API
4. `CourierWorkflowIT` - end-to-end тесты полного цикла

---

## Поэтапное внедрение

### Фаза 1: Database & Entities (Week 1)
- Создание миграций БД
- Создание Entity классов
- Создание репозиториев
- Unit тесты для репозиториев

### Фаза 2: Integration API (Week 2)
- CourierIntegrationService
- CourierIntegrationController
- Валидация входящих данных
- Логирование интеграций
- Integration tests

### Фаза 3: Logist Web API (Week 3)
- CourierWaybillService
- CourierLogistController
- Управление курьерами
- Аналитика и отчеты

### Фаза 4: Mobile API (Week 4)
- CourierMobileService
- CourierMobileController
- Интеграция с DriverLocationService
- Фото загрузка

### Фаза 5: Outgoing Integration (Week 5)
- CourierResultsService
- Очередь и ретраи
- Мониторинг и алерты

### Фаза 6: Testing & Documentation (Week 6)
- End-to-end тесты
- Performance тесты
- Документация API (Swagger)
- Инструкции для TEEZ
