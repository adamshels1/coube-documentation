# 10. Упрощенный MVP план курьерской доставки

## 🎯 Цель: Максимальное переиспользование существующего кода

**Основной принцип**: Курьерская доставка = обычная Transportation с типом `COURIER_DELIVERY`

---

## ✅ Что переиспользуем (уже готово)

### 1. Entity и связи
- ✅ **Transportation** - основная сущность заявки
- ✅ **TransportationRouteHistory** - версии маршрута
- ✅ **CargoLoadingHistory** - точки маршрута (используем как точки доставки!)
- ✅ **Employee** - водитель/курьер (одна и та же роль)
- ✅ **Organization** - заказчик/исполнитель

### 2. API Controllers
- ✅ **DriverController** - 95% функционала для курьера готов:
  - `GET /orders` - список заявок
  - `GET /orders/{id}` - детали заявки
  - `PUT /orders/{id}/accept` - принять
  - `PUT /orders/{id}/reject` - отклонить
  - `PUT /orders/{id}/start` - начать выполнение
  - `PUT /orders/{id}/arrival` - прибытие на точку
  - `PUT /orders/{id}/departure` - отбытие с точки
  - `POST /orders/{id}/sos` - SOS
  - `GET /profile/{employeeId}` - профиль

### 3. Services
- ✅ **DriverService** - вся логика работы с заявками
- ✅ **TransportationService** - создание/обновление Transportation
- ✅ **TransportationRouteService** - управление маршрутами
- ✅ **DriverLocationService** - геолокация
- ✅ **FileService** - загрузка фото
- ✅ **NotificationService** - уведомления

### 4. Существующие Enums
- ✅ **TransportationType**: FTL, BULK, CITY, LTL
- ✅ **TransportationStatus**: FORMING, CREATED, DRIVER_ACCEPTED, ON_THE_WAY, FINISHED, etc.
- ✅ **LoadingType**: LOADING, UNLOADING

---

## 🆕 Что нужно добавить (минимум)

### 1. Расширение Enums

#### TransportationType (добавить 1 значение)
```java
public enum TransportationType {
  FTL,
  BULK,
  CITY,
  LTL,
  COURIER_DELIVERY; // ← НОВОЕ: Курьерская доставка

  // ... existing methods
}
```

**Локализация** (messages.properties):
```properties
enum.transportation-type.COURIER_DELIVERY.kk=Курьерлік жеткізу
enum.transportation-type.COURIER_DELIVERY.ru=Курьерская доставка
enum.transportation-type.COURIER_DELIVERY.en=Courier delivery
enum.transportation-type.COURIER_DELIVERY.zh=快递
```

### 2. Расширение Transportation (3 поля)

```java
@Entity
@Table(name = "transportation", schema = "applications")
public class Transportation extends BaseIdEntity {
  
  // ... existing fields
  
  // Новые поля для курьерской доставки
  @Column(name = "source_system")
  private String sourceSystem; // TEEZ_PVZ, KASPI, WILDBERRIES, OZON
  
  @Column(name = "external_waybill_id")
  private String externalWaybillId; // ID маршрутного листа из внешней системы
  
  // Используем СУЩЕСТВУЮЩИЙ TransportationStatus для статусов!
  // FORMING → SIGNED_CUSTOMER → WAITING_DRIVER_CONFIRMATION → DRIVER_ACCEPTED → ON_THE_WAY → FINISHED
}
```

### 3. Расширение CargoLoadingHistory (переиспользуем как точки доставки)

**Используем существующие поля**:
- ✅ `orderNum` → порядок точки в маршруте (sort_order)
- ✅ `loadingType` → LOADING/UNLOADING (загрузка/разгрузка)
- ✅ `address` → адрес доставки
- ✅ `location` → координаты (Point)
- ✅ `loadingDatetime` → желаемое время доставки
- ✅ `contactPersonName` → имя получателя
- ✅ `contactNumber` → телефон получателя
- ✅ `commentary` → комментарий
- ✅ `isDriverAtLocation` → курьер на точке

**Добавляем 3 поля**:
```java
@Column(name = "is_sms_required")
private Boolean isSmsRequired; // требуется SMS подтверждение

@Column(name = "is_photo_required")
private Boolean isPhotoRequired; // требуется фото

@Column(name = "courier_warehouse_id")
private String courierWarehouseId; // ID склада/ПВЗ для точек-складов
```

### 4. Новая таблица: courier_route_order (заказы внутри точки)

```sql
CREATE TABLE IF NOT EXISTS applications.courier_route_order (
  id BIGSERIAL PRIMARY KEY,
  
  -- Связь с точкой маршрута (переиспользуем CargoLoadingHistory!)
  cargo_loading_history_id BIGINT NOT NULL REFERENCES gis.cargo_loading_history(id) ON DELETE CASCADE,
  
  -- Данные заказа
  track_number TEXT NOT NULL UNIQUE,
  external_id TEXT NOT NULL,
  load_type TEXT NOT NULL, -- load/unload (для точки может быть несколько заказов с разными операциями)
  
  -- Статус заказа
  status TEXT NOT NULL DEFAULT 'pending', -- pending, delivered, returned, partially_returned, not_delivered
  status_reason TEXT, -- customer_not_available, customer_postponed, force_majeure
  status_datetime TIMESTAMP,
  
  -- Подтверждения
  sms_code_used TEXT,
  photo_id UUID REFERENCES files.file_meta_info(id),
  courier_comment TEXT,
  
  -- Позиции заказа (JSON - не нужна отдельная таблица!)
  positions JSONB, -- [{"code": "POS-001", "name": "Товар 1", "qty": 2, "returned_qty": 0}, ...]
  
  -- Аудит
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by TEXT NOT NULL
);

CREATE INDEX idx_courier_order_cargo_loading ON applications.courier_route_order(cargo_loading_history_id);
CREATE INDEX idx_courier_order_track_number ON applications.courier_route_order(track_number);
CREATE INDEX idx_courier_order_status ON applications.courier_route_order(status);

COMMENT ON TABLE applications.courier_route_order IS 'Заказы курьерской доставки в точках маршрута';
COMMENT ON COLUMN applications.courier_route_order.positions IS 'Позиции заказа в JSON формате';
```

**Entity**:
```java
@Entity
@Table(name = "courier_route_order", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierRouteOrder extends AuditEntity {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "cargo_loading_history_id", nullable = false)
  private CargoLoadingHistory cargoLoadingHistory; // ← Используем существующую таблицу!
  
  @Column(name = "track_number", nullable = false, unique = true)
  private String trackNumber;
  
  @Column(name = "external_id", nullable = false)
  private String externalId;
  
  @Column(name = "load_type", nullable = false)
  private String loadType; // load/unload
  
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
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "photo_id")
  private FileMetaInfo photo; // ← Переиспользуем существующую таблицу файлов!
  
  @Column(name = "courier_comment", columnDefinition = "TEXT")
  private String courierComment;
  
  @Column(name = "positions", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String positions; // JSON: [{"code": "...", "name": "...", "qty": 2, "returned_qty": 0}]
}
```

**Enums**:
```java
public enum CourierOrderStatus {
  PENDING,
  DELIVERED,
  RETURNED,
  PARTIALLY_RETURNED,
  NOT_DELIVERED
}

public enum CourierOrderStatusReason {
  CUSTOMER_NOT_AVAILABLE,
  CUSTOMER_POSTPONED,
  FORCE_MAJEURE
}
```

### 5. Новая таблица: courier_integration_log (логи интеграций)

```sql
CREATE TABLE IF NOT EXISTS applications.courier_integration_log (
  id BIGSERIAL PRIMARY KEY,
  
  -- Связь с заявкой
  transportation_id BIGINT REFERENCES applications.transportation(id) ON DELETE SET NULL,
  
  -- Направление вызова
  direction TEXT NOT NULL, -- incoming, outgoing
  
  -- Внешняя система
  source_system TEXT NOT NULL, -- TEEZ_PVZ, KASPI, WILDBERRIES, OZON
  
  -- HTTP запрос/ответ
  http_method TEXT NOT NULL, -- POST, GET, PUT
  endpoint TEXT NOT NULL,
  http_status_code INT,
  
  -- Payload
  request_payload JSONB,
  response_payload JSONB,
  
  -- Статус
  status TEXT NOT NULL, -- success, error, retry
  error_message TEXT,
  retry_count INT DEFAULT 0,
  
  -- Время
  request_datetime TIMESTAMP NOT NULL,
  response_datetime TIMESTAMP,
  
  -- Аудит
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_integration_log_transportation ON applications.courier_integration_log(transportation_id);
CREATE INDEX idx_integration_log_source ON applications.courier_integration_log(source_system);
CREATE INDEX idx_integration_log_status ON applications.courier_integration_log(status);
CREATE INDEX idx_integration_log_created ON applications.courier_integration_log(created_at DESC);

COMMENT ON TABLE applications.courier_integration_log IS 'Логи интеграций курьерской доставки с внешними системами';
```

**Entity**:
```java
@Entity
@Table(name = "courier_integration_log", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CourierIntegrationLog {
  
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;
  
  @ManyToOne(fetch = FetchType.LAZY)
  @JoinColumn(name = "transportation_id")
  private Transportation transportation;
  
  @Column(name = "direction", nullable = false)
  private String direction; // incoming, outgoing
  
  @Column(name = "source_system", nullable = false)
  private String sourceSystem;
  
  @Column(name = "http_method", nullable = false)
  private String httpMethod;
  
  @Column(name = "endpoint", nullable = false)
  private String endpoint;
  
  @Column(name = "http_status_code")
  private Integer httpStatusCode;
  
  @Column(name = "request_payload", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String requestPayload;
  
  @Column(name = "response_payload", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String responsePayload;
  
  @Column(name = "status", nullable = false)
  private String status; // success, error, retry
  
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

## 📋 Миграции БД (всего 4 миграции!)

### V2025_01_20_01__add_courier_delivery_type.sql
```sql
-- Добавляем новый тип перевозки
-- ВАЖНО: Flyway не поддерживает ALTER TYPE ... ADD VALUE в транзакции
-- Нужно выполнить отдельно или использовать IF NOT EXISTS проверку

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'COURIER_DELIVERY' AND enumtypid = 'transportation_type'::regtype) THEN
    ALTER TYPE dictionaries.transportation_type ADD VALUE 'COURIER_DELIVERY';
  END IF;
END
$$;

-- Добавляем локализацию в properties файлы вручную после применения миграции
```

### V2025_01_20_02__add_courier_fields_to_transportation.sql
```sql
-- Добавляем поля для курьерской доставки в Transportation
ALTER TABLE applications.transportation
ADD COLUMN IF NOT EXISTS source_system TEXT,
ADD COLUMN IF NOT EXISTS external_waybill_id TEXT,
ADD COLUMN IF NOT EXISTS courier_validation_status TEXT DEFAULT 'imported';

-- Индексы
CREATE INDEX IF NOT EXISTS idx_transportation_external_waybill 
ON applications.transportation(external_waybill_id, source_system) 
WHERE transportation_type = 'COURIER_DELIVERY';

CREATE INDEX IF NOT EXISTS idx_transportation_courier_validation 
ON applications.transportation(courier_validation_status) 
WHERE transportation_type = 'COURIER_DELIVERY';

-- Комментарии
COMMENT ON COLUMN applications.transportation.source_system IS 'Внешняя система-источник (TEEZ_PVZ, KASPI, WILDBERRIES, OZON)';
COMMENT ON COLUMN applications.transportation.external_waybill_id IS 'ID маршрутного листа из внешней системы';
COMMENT ON COLUMN applications.transportation.courier_validation_status IS 'Статус валидации курьерского маршрута (imported, validated, assigned, closed)';
```

### V2025_01_20_03__add_courier_fields_to_cargo_loading.sql
```sql
-- Добавляем поля для курьерской доставки в CargoLoadingHistory
ALTER TABLE gis.cargo_loading_history
ADD COLUMN IF NOT EXISTS is_sms_required BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS is_photo_required BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS courier_warehouse_id TEXT;

-- Индексы
CREATE INDEX IF NOT EXISTS idx_cargo_loading_courier_warehouse 
ON gis.cargo_loading_history(courier_warehouse_id) 
WHERE courier_warehouse_id IS NOT NULL;

-- Комментарии
COMMENT ON COLUMN gis.cargo_loading_history.is_sms_required IS 'Требуется SMS подтверждение для курьерской доставки';
COMMENT ON COLUMN gis.cargo_loading_history.is_photo_required IS 'Требуется фото подтверждение для курьерской доставки';
COMMENT ON COLUMN gis.cargo_loading_history.courier_warehouse_id IS 'ID склада/ПВЗ для точек-складов';
```

### V2025_01_20_04__create_courier_tables.sql
```sql
-- 1. Создаем таблицу заказов курьерской доставки
CREATE TABLE IF NOT EXISTS applications.courier_route_order (
  id BIGSERIAL PRIMARY KEY,
  cargo_loading_history_id BIGINT NOT NULL REFERENCES gis.cargo_loading_history(id) ON DELETE CASCADE,
  track_number TEXT NOT NULL UNIQUE,
  external_id TEXT NOT NULL,
  load_type TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  status_reason TEXT,
  status_datetime TIMESTAMP,
  sms_code_used TEXT,
  photo_id UUID REFERENCES files.file_meta_info(id),
  courier_comment TEXT,
  positions JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by TEXT NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_by TEXT NOT NULL
);

CREATE INDEX idx_courier_order_cargo_loading ON applications.courier_route_order(cargo_loading_history_id);
CREATE INDEX idx_courier_order_track_number ON applications.courier_route_order(track_number);
CREATE INDEX idx_courier_order_status ON applications.courier_route_order(status);

COMMENT ON TABLE applications.courier_route_order IS 'Заказы курьерской доставки в точках маршрута';
COMMENT ON COLUMN applications.courier_route_order.positions IS 'Позиции заказа в JSON: [{"code": "...", "name": "...", "qty": 2, "returned_qty": 0}]';

-- 2. Создаем таблицу логов интеграций
CREATE TABLE IF NOT EXISTS applications.courier_integration_log (
  id BIGSERIAL PRIMARY KEY,
  transportation_id BIGINT REFERENCES applications.transportation(id) ON DELETE SET NULL,
  direction TEXT NOT NULL,
  source_system TEXT NOT NULL,
  http_method TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  http_status_code INT,
  request_payload JSONB,
  response_payload JSONB,
  status TEXT NOT NULL,
  error_message TEXT,
  retry_count INT DEFAULT 0,
  request_datetime TIMESTAMP NOT NULL,
  response_datetime TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_integration_log_transportation ON applications.courier_integration_log(transportation_id);
CREATE INDEX idx_integration_log_source ON applications.courier_integration_log(source_system);
CREATE INDEX idx_integration_log_status ON applications.courier_integration_log(status);
CREATE INDEX idx_integration_log_created ON applications.courier_integration_log(created_at DESC);

COMMENT ON TABLE applications.courier_integration_log IS 'Логи интеграций курьерской доставки с внешними системами';
```

---

## 🏗️ Архитектура решения

### Связи между таблицами

```
Transportation (тип = COURIER_DELIVERY)
  ├── source_system: "TEEZ_PVZ"
  ├── external_waybill_id: "WB-2025-001"
  └── currentRouteHistory: TransportationRouteHistory
        └── cargoLoadingsHistory: List<CargoLoadingHistory>  ← ТОЧКИ МАРШРУТА
              ├── orderNum: 1, 2, 3, ... (порядок)
              ├── loadingType: LOADING/UNLOADING
              ├── address: "улица Пушкина, дом 1"
              ├── location: Point(lat, lon)
              ├── contactPersonName: "Иван Иванов"
              ├── contactNumber: "+77771234567"
              ├── is_sms_required: true
              ├── is_photo_required: true
              ├── courier_warehouse_id: "WH-001" (для складов)
              └── courierOrders: List<CourierRouteOrder>  ← ЗАКАЗЫ В ТОЧКЕ
                    ├── trackNumber: "TRACK-123"
                    ├── status: DELIVERED
                    ├── photo: FileMetaInfo
                    └── positions: JSON
```

### Преимущества подхода

✅ **Минимальные изменения**: только 3 поля в Transportation, 3 в CargoLoadingHistory  
✅ **Переиспользование**: 95% существующей логики работает без изменений  
✅ **Единая модель**: курьер = водитель с типом COURIER_DELIVERY  
✅ **Существующие API**: DriverController работает для курьеров  
✅ **Масштабируемость**: легко добавить новые поля в будущем  

---

## 🚀 Новый код (Services + Controllers)

### 1. CourierIntegrationService (новый)

```java
package kz.coube.backend.courier.service;

@Service
@RequiredArgsConstructor
@Slf4j
public class CourierIntegrationService {
  
  private final TransportationService transportationService; // ← Существующий!
  private final TransportationRouteService routeService; // ← Существующий!
  private final CourierRouteOrderRepository courierOrderRepo;
  private final CourierIntegrationLogRepository integrationLogRepo;
  
  /**
   * Импорт маршрутного листа от внешней системы (TEEZ, Kaspi, etc.)
   */
  @Transactional
  public Transportation importWaybill(WaybillImportRequest request) {
    Instant startTime = Instant.now();
    
    try {
      // 1. Проверяем дубликаты
      Optional<Transportation> existing = transportationService
          .findByExternalWaybillId(request.getSourceSystem(), request.getWaybill().getId());
      
      if (existing.isPresent()) {
        // Если статус FORMING - можно обновить, иначе - locked
        Transportation t = existing.get();
        if (!TransportationStatus.FORMING.equals(t.getStatus())) {
          throw new BusinessException("Waybill already processed and cannot be updated");
        }
        // Обновляем существующий
        return updateWaybill(t, request);
      }
      
      // 2. Создаем новую Transportation
      Transportation transportation = new Transportation();
      transportation.setTransportationType(TransportationType.COURIER_DELIVERY);
      transportation.setSourceSystem(request.getSourceSystem());
      transportation.setExternalWaybillId(request.getWaybill().getId());
      transportation.setStatus(TransportationStatus.FORMING); // Черновик
      transportation.setFillingStep(TransportationFillingStep.ROUTE); // Маршрут заполняется из импорта
      
      // Создаем рейс через существующий сервис
      TransportationRouteHistory route = transportationRouteService.createInitialRoute(
          transportation,
          cargoLoadingRequests
      );
      transportation.setCurrentRouteHistory(route);
      
      // TODO: заполнить организацию заказчика (определить по source_system)
      // transportation.setCustomerOrganization(...);
      
      transportation = transportationService.save(transportation);
      
      // 3. Создаем маршрут через существующий сервис
      TransportationRouteHistory routeHistory = createRouteFromWaybill(transportation, request);
      transportation.setCurrentRouteHistory(routeHistory);
      transportation = transportationService.save(transportation);
      
      // 4. Логируем успешный импорт
      logIntegration("incoming", request.getSourceSystem(), "POST", "/waybills", 
                     200, toJson(request), toJson(transportation), "success", null, transportation);
      
      log.info("Imported waybill {} from {}", request.getWaybill().getId(), request.getSourceSystem());
      
      return transportation;
      
    } catch (Exception e) {
      // Логируем ошибку
      logIntegration("incoming", request.getSourceSystem(), "POST", "/waybills",
                     500, toJson(request), null, "error", e.getMessage(), null);
      throw e;
    }
  }
  
  /**
   * Создание маршрута из данных импорта
   */
  private TransportationRouteHistory createRouteFromWaybill(
      Transportation transportation, 
      WaybillImportRequest request) {
    
    // Используем существующий TransportationRouteService!
    TransportationRouteHistory routeHistory = new TransportationRouteHistory();
    routeHistory.setTransportation(transportation);
    routeHistory.setVersionNumber(1);
    routeHistory.setStatus(RouteHistoryStatus.ACTIVE);
    routeHistory.setChangeType(RouteHistoryChangeType.INITIAL);
    routeHistory.setCreatedAt(LocalDateTime.now());
    routeHistory.setCreatedBy("SYSTEM_IMPORT");
    
    List<CargoLoadingHistory> cargoLoadings = new ArrayList<>();
    
    // Создаем точки маршрута из delivery points
    for (DeliveryPoint point : request.getDeliveries()) {
      CargoLoadingHistory clh = new CargoLoadingHistory();
      clh.setRouteHistory(routeHistory);
      clh.setOrderNum(point.getSort());
      clh.setLoadingType(mapLoadType(point.getLoadType()));
      clh.setAddress(point.getAddress());
      clh.setLoadingDatetime(toLocalDateTime(point.getDeliveryDesiredDatetime()));
      clh.setContactPersonName(point.getReceiver() != null ? point.getReceiver().getName() : null);
      clh.setContactNumber(point.getReceiver() != null ? point.getReceiver().getPhone() : null);
      clh.setCommentary(point.getComment());
      clh.setIsSmsRequired(point.getIsSmsRequired());
      clh.setIsPhotoRequired(point.getIsPhotoRequired());
      clh.setCourierWarehouseId(point.getWarehouseId());
      clh.setIsActive(true);
      clh.setIsDriverAtLocation(false);
      clh.setAction(CargoLoadingHistoryAction.CREATED);
      
      // Геокодирование (если координаты не переданы)
      if (point.getLatitude() != null && point.getLongitude() != null) {
        clh.setLocation(createPoint(point.getLatitude(), point.getLongitude()));
      } else {
        // TODO: вызвать сервис геокодирования
      }
      
      cargoLoadings.add(clh);
      
      // Создаем заказы для точки
      if (point.getOrders() != null) {
        for (OrderInfo order : point.getOrders()) {
          CourierRouteOrder courierOrder = new CourierRouteOrder();
          courierOrder.setCargoLoadingHistory(clh);
          courierOrder.setTrackNumber(order.getTrackNumber());
          courierOrder.setExternalId(order.getExternalId());
          courierOrder.setLoadType(order.getOrderLoadType());
          courierOrder.setStatus(CourierOrderStatus.PENDING);
          courierOrder.setPositions(toJson(order.getPositions())); // JSON
          courierOrder.setCreatedBy("SYSTEM_IMPORT");
          courierOrder.setUpdatedBy("SYSTEM_IMPORT");
          
          courierOrderRepo.save(courierOrder);
        }
      }
    }
    
    routeHistory.setCargoLoadingsHistory(cargoLoadings);
    return routeService.save(routeHistory); // ← Используем существующий сервис!
  }
  
  /**
   * Получение статусов заказов для внешней системы
   */
  @Transactional(readOnly = true)
  public List<OrderStatusDto> getOrderStatuses(String externalWaybillId, String sourceSystem) {
    Transportation transportation = transportationService
        .findByExternalWaybillId(sourceSystem, externalWaybillId)
        .orElseThrow(() -> new NotFoundException("Waybill not found"));
    
    // Получаем все заказы из всех точек маршрута
    List<CargoLoadingHistory> points = transportation.getCargoLoadings();
    
    return points.stream()
        .flatMap(point -> courierOrderRepo.findByCargoLoadingHistoryId(point.getId()).stream())
        .map(this::toOrderStatusDto)
        .collect(Collectors.toList());
  }
  
  private void logIntegration(String direction, String sourceSystem, String method, 
                               String endpoint, Integer statusCode, String request, 
                               String response, String status, String error,
                               Transportation transportation) {
    CourierIntegrationLog log = new CourierIntegrationLog();
    log.setTransportation(transportation);
    log.setDirection(direction);
    log.setSourceSystem(sourceSystem);
    log.setHttpMethod(method);
    log.setEndpoint(endpoint);
    log.setHttpStatusCode(statusCode);
    log.setRequestPayload(request);
    log.setResponsePayload(response);
    log.setStatus(status);
    log.setErrorMessage(error);
    log.setRequestDatetime(Instant.now());
    log.setResponseDatetime(Instant.now());
    log.setCreatedAt(Instant.now());
    integrationLogRepo.save(log);
  }
  
  // Вспомогательные методы маппинга...
}
```

### 2. CourierIntegrationController (новый)

```java
package kz.coube.backend.courier.api;

@RestController
@RequestMapping("/api/v1/integration")
@RequiredArgsConstructor
@Tag(name = "Courier Integration", description = "API для интеграции с внешними системами (TEEZ, Kaspi, Wildberries, Ozon)")
public class CourierIntegrationController {
  
  private final CourierIntegrationService courierIntegrationService;
  
  @PostMapping("/waybills")
  @Operation(summary = "Импорт маршрутного листа от внешней системы")
  public ResponseEntity<WaybillImportResponse> importWaybill(
      @Valid @RequestBody WaybillImportRequest request) {
    
    Transportation transportation = courierIntegrationService.importWaybill(request);
    
    WaybillImportResponse response = WaybillImportResponse.builder()
        .status(transportation.getStatus().name()) // FORMING
        .transportationId(transportation.getId())
        .externalWaybillId(transportation.getExternalWaybillId())
        .createdAt(transportation.getCreatedAt())
        .message("Waybill imported successfully")
        .build();
    
    return ResponseEntity.ok(response);
  }
  
  @GetMapping("/waybills/{externalWaybillId}/orders")
  @Operation(summary = "Получить статусы заказов маршрутного листа")
  public ResponseEntity<List<OrderStatusDto>> getOrderStatuses(
      @PathVariable String externalWaybillId,
      @RequestParam String sourceSystem) {
    
    List<OrderStatusDto> statuses = courierIntegrationService.getOrderStatuses(externalWaybillId, sourceSystem);
    return ResponseEntity.ok(statuses);
  }
}
```

### 3. Дополнение в DriverController (1 метод!)

```java
// Добавить в существующий DriverController

@PutMapping("orders/{transportationId}/courier-orders/{orderId}/status")
@Operation(summary = "Обновить статус заказа курьерской доставки")
public ResponseEntity<CourierOrderStatusResponse> updateCourierOrderStatus(
    @PathVariable Long transportationId,
    @PathVariable Long orderId,
    @Valid @RequestBody CourierOrderStatusUpdateRequest request) {
  
  CourierRouteOrder order = courierOrderService.updateStatus(transportationId, orderId, request);
  
  return ResponseEntity.ok(CourierOrderStatusResponse.builder()
      .orderId(order.getId())
      .trackNumber(order.getTrackNumber())
      .status(order.getStatus())
      .statusDatetime(order.getStatusDatetime())
      .build());
}
```

### 4. CourierOrderService (новый, простой)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CourierOrderService {
  
  private final CourierRouteOrderRepository courierOrderRepo;
  private final FileService fileService; // ← Существующий!
  
  @Transactional
  public CourierRouteOrder updateStatus(Long transportationId, Long orderId, 
                                        CourierOrderStatusUpdateRequest request) {
    
    CourierRouteOrder order = courierOrderRepo.findById(orderId)
        .orElseThrow(() -> new NotFoundException("Order not found"));
    
    // Проверка что заказ принадлежит данной transportation
    if (!order.getCargoLoadingHistory().getRouteHistory().getTransportation().getId().equals(transportationId)) {
      throw new AccessDeniedException("Order does not belong to this transportation");
    }
    
    // Обновляем статус
    order.setStatus(request.getStatus());
    order.setStatusReason(request.getStatusReason());
    order.setStatusDatetime(Instant.now());
    order.setSmsCodeUsed(request.getSmsCode());
    order.setCourierComment(request.getComment());
    
    // Обновляем возвращенные позиции (если частичный возврат)
    if (request.getReturnedPositions() != null) {
      // Обновляем JSON с возвращенными количествами
      // TODO: implement JSON update logic
    }
    
    return courierOrderRepo.save(order);
  }
  
  @Transactional
  public CourierRouteOrder uploadPhoto(Long orderId, MultipartFile file) {
    CourierRouteOrder order = courierOrderRepo.findById(orderId)
        .orElseThrow(() -> new NotFoundException("Order not found"));
    
    // Используем существующий FileService!
    FileMetaInfo photoMeta = fileService.uploadFile(file, "courier/photos");
    order.setPhoto(photoMeta);
    
    return courierOrderRepo.save(order);
  }
}
```

### 5. CourierResultsService (отправка результатов в TEEZ)

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CourierResultsService {
  
  private final TransportationService transportationService;
  private final CourierRouteOrderRepository courierOrderRepo;
  private final CourierIntegrationLogRepository integrationLogRepo;
  private final RestTemplate restTemplate; // или WebClient
  
  @Value("${courier.integration.teez.api-url}")
  private String teezApiUrl;
  
  /**
   * Синхронная отправка результатов при закрытии маршрута
   */
  @Transactional
  public void sendResultsSync(Long transportationId) {
    Transportation transportation = transportationService.findById(transportationId);
    
    if (!TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType())) {
      throw new BusinessException("Not a courier delivery transportation");
    }
    
    // Формируем payload результатов
    WaybillResultsPayload payload = buildResultsPayload(transportation);
    
    Instant startTime = Instant.now();
    try {
      // Отправляем синхронно
      String url = determineMarketplaceUrl(transportation.getSourceSystem());
      ResponseEntity<String> response = restTemplate.postForEntity(
          url + "/api/waybill/results",
          payload,
          String.class
      );
      
      // Логируем успех
      logIntegration(transportation, "outgoing", "POST", "/api/waybill/results",
                     response.getStatusCodeValue(), toJson(payload), 
                     response.getBody(), "success", null);
      
      log.info("Results sent successfully for transportation {}", transportationId);
      
    } catch (Exception e) {
      // Логируем ошибку
      logIntegration(transportation, "outgoing", "POST", "/api/waybill/results",
                     500, toJson(payload), null, "error", e.getMessage());
      
      log.error("Failed to send results for transportation {}", transportationId, e);
      throw new IntegrationException("Failed to send results to " + transportation.getSourceSystem(), e);
    }
  }
  
  private WaybillResultsPayload buildResultsPayload(Transportation transportation) {
    List<CargoLoadingHistory> points = transportation.getCargoLoadings();
    
    List<DeliveryResultDto> deliveryResults = new ArrayList<>();
    
    for (CargoLoadingHistory point : points) {
      List<CourierRouteOrder> orders = courierOrderRepo.findByCargoLoadingHistoryId(point.getId());
      
      for (CourierRouteOrder order : orders) {
        DeliveryResultDto result = DeliveryResultDto.builder()
            .trackNumber(order.getTrackNumber())
            .externalId(order.getExternalId())
            .status(mapToExternalStatus(order.getStatus()))
            .statusReason(order.getStatusReason() != null ? order.getStatusReason().name() : null)
            .deliveryDatetime(order.getStatusDatetime())
            .photoUrl(order.getPhoto() != null ? order.getPhoto().getUrl() : null)
            .courierComment(order.getCourierComment())
            .build();
        
        deliveryResults.add(result);
      }
    }
    
    return WaybillResultsPayload.builder()
        .waybillId(transportation.getExternalWaybillId())
        .completedAt(Instant.now())
        .deliveryResults(deliveryResults)
        .build();
  }
  
  private String determineMarketplaceUrl(String sourceSystem) {
    // TODO: читать из конфигурации
    return switch (sourceSystem) {
      case "TEEZ_PVZ" -> teezApiUrl;
      case "KASPI" -> kaspiApiUrl;
      // ... etc
      default -> throw new IllegalArgumentException("Unknown source system: " + sourceSystem);
    };
  }
  
  // Вспомогательные методы...
}
```

---

## 🔐 API Key аутентификация (упрощенная для MVP)

### Подход: Статический ключ в конфигурации

**Не используем** сложную систему с БД и Admin UI. Вместо этого:

### 1. Config Properties

```java
package kz.coube.backend.courier.config;

@Component
@ConfigurationProperties(prefix = "courier.integration")
@Data
public class CourierIntegrationProperties {
    
    private String apiKey; // Статический ключ из environment variable
    private TeezConfig teez = new TeezConfig();
    
    @Data
    public static class TeezConfig {
        private boolean enabled = true;
        private String apiUrl;
        private String endpoint;
    }
}
```

### 2. Simple Security Filter

```java
package kz.coube.backend.courier.security;

@Component
@RequiredArgsConstructor
@Slf4j
public class CourierApiKeyFilter extends OncePerRequestFilter {
    
    private final CourierIntegrationProperties properties;
    private static final String API_KEY_HEADER = "X-API-Key";
    private static final String INTEGRATION_PATH_PREFIX = "/api/v1/integration/";
    
    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        
        String path = request.getRequestURI();
        
        // Применяем только к integration endpoints
        if (!path.startsWith(INTEGRATION_PATH_PREFIX)) {
            filterChain.doFilter(request, response);
            return;
        }
        
        String apiKey = request.getHeader(API_KEY_HEADER);
        
        // Проверка наличия ключа
        if (apiKey == null || apiKey.isBlank()) {
            log.warn("Missing API key for: {} from IP: {}", path, getClientIp(request));
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "API key is required");
            return;
        }
        
        // Простая проверка (сравнение строк)
        if (!properties.getApiKey().equals(apiKey)) {
            log.warn("Invalid API key for: {} from IP: {}", path, getClientIp(request));
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Invalid API key");
            return;
        }
        
        // Устанавливаем аутентификацию
        List<SimpleGrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_INTEGRATION"),
            new SimpleGrantedAuthority("SCOPE_courier:integration")
        );
        
        UsernamePasswordAuthenticationToken authentication = 
                new UsernamePasswordAuthenticationToken(
                        "INTEGRATION_API", null, authorities);
        
        SecurityContextHolder.getContext().setAuthentication(authentication);
        
        filterChain.doFilter(request, response);
    }
    
    private String getClientIp(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty()) {
            ip = request.getRemoteAddr();
        }
        if (ip != null && ip.contains(",")) {
            ip = ip.split(",")[0].trim();
        }
        return ip;
    }
}
```

### 3. Security Config

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Autowired
    private CourierApiKeyFilter courierApiKeyFilter;
    
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
                // ... existing config
                
                // Добавляем фильтр
                .addFilterBefore(courierApiKeyFilter, UsernamePasswordAuthenticationFilter.class)
                
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/v1/integration/**")
                        .hasAuthority("SCOPE_courier:integration")
                        // ... existing rules
                )
                .build();
    }
}
```

### 4. Configuration (application.yml)

```yaml
courier:
  integration:
    # Статический ключ (меняется через environment variable)
    api-key: ${COURIER_API_KEY:dev-test-key-not-for-production}
    
    teez:
      enabled: true
      api-url: ${TEEZ_API_URL:https://teez-api.example.com}
      endpoint: /api/waybill/results
```

### 5. Production Deployment

**Генерация ключа**:
```bash
# Безопасный случайный ключ (32 байта)
openssl rand -base64 32
# Результат: xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR=

# Добавляем префикс
# coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
```

**Kubernetes Secret**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: courier-api-key
stringData:
  api-key: coube_prod_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
```

**Deployment env**:
```yaml
env:
  - name: COURIER_API_KEY
    valueFrom:
      secretKeyRef:
        name: courier-api-key
        key: api-key
```

### Преимущества упрощенного подхода

✅ **Быстрая реализация**: 2-4 часа (вместо 2-3 дней)  
✅ **Без БД**: не нужна таблица `integration_api_keys`  
✅ **Без Admin UI**: не нужен контроллер управления  
✅ **Безопасно**: HTTPS + environment variable + логирование  
✅ **Легко сменить**: просто обновить environment variable  

### Что НЕ включено (можно добавить после MVP)

❌ Хранение в БД с хешированием  
❌ Множество ключей (для разных маркетплейсов)  
❌ Admin UI для управления ключами  
❌ IP whitelist  
❌ Rate limiting  
❌ Детальные scopes и права  
❌ Статистика использования в отдельной таблице  

### Использование TEEZ

```bash
curl -X POST "https://api.coube.kz/api/v1/integration/waybills" \
  -H "X-API-Key: coube_prod_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR" \
  -H "Content-Type: application/json" \
  -d '{"source_system": "TEEZ_PVZ", ...}'
```

**См. детали**: `04-api-key-authentication-simplified.md`

---

## ✅ Итоговая статистика

### Новый код
- ✅ **Миграции**: 4 файла
- ✅ **Entity**: 2 новых (CourierRouteOrder, CourierIntegrationLog)
- ✅ **Repository**: 2 новых
- ✅ **Service**: 3 новых (CourierIntegrationService, CourierOrderService, CourierResultsService)
- ✅ **Controller**: 1 новый + 1 метод в существующий (IntegrationController + DriverController)
- ✅ **DTO**: ~10 классов
- ✅ **Enum**: 2 новых (CourierOrderStatus, CourierOrderStatusReason)

### Переиспользуется
- ✅ **Transportation** (основная сущность)
- ✅ **TransportationRouteHistory** (маршруты)
- ✅ **CargoLoadingHistory** (точки доставки)
- ✅ **DriverController** (95% API для курьера)
- ✅ **DriverService** (вся логика)
- ✅ **TransportationService**
- ✅ **TransportationRouteService**
- ✅ **DriverLocationService**
- ✅ **FileService**
- ✅ **NotificationService**

---

## ⏱️ Обновленная оценка: **2-3 недели (1 разработчик)**

**Week 1**: БД миграции + Entity + Repository  
**Week 2**: Integration API (импорт от TEEZ) + Services  
**Week 3**: Дополнения в DriverController + отправка результатов + тестирование

**Почему так быстро:**
- Минимум нового кода
- Максимум переиспользования
- Простая архитектура
- Нет лишней сложности

---

## 🎯 Что НЕ входит в MVP (можно добавить потом)

❌ Асинхронная отправка результатов с retry  
❌ Сложная валидация маршрутов  
❌ Геокодирование адресов  
❌ Управление складами через admin UI  
❌ Детальная аналитика и отчеты  
❌ Отдельный веб-интерфейс для логистов (используем существующий)  
❌ История изменений маршрутов  
❌ Rate limiting  
❌ IP whitelist для API ключей  

---

**Следующий шаг**: Создать чеклист реализации на основе этого плана.
