# 07. Чеклист реализации курьерской доставки

## Обзор

Пошаговый чеклист для разработчиков backend для внедрения функционала курьерской доставки.

---

## Phase 1: Database Setup

### 1.1 Flyway Migrations

- [ ] **V2025_01_15_01**: Добавить `COURIER_DELIVERY` в enum `TransportationType`
  ```sql
  -- Добавить в properties файлы перевод названия
  ```

- [ ] **V2025_01_15_02**: Добавить поля в таблицу `applications.transportation`
  ```sql
  ALTER TABLE applications.transportation
  ADD COLUMN source_system TEXT,
  ADD COLUMN external_waybill_id TEXT,
  ADD COLUMN delivery_type TEXT,
  ADD COLUMN responsible_courier_warehouse_id TEXT,
  ADD COLUMN target_delivery_day DATE,
  ADD COLUMN validation_status TEXT DEFAULT 'imported_draft';
  
  CREATE INDEX idx_transportation_external_waybill 
  ON applications.transportation(external_waybill_id, source_system) 
  WHERE transportation_type = 'COURIER_DELIVERY';
  ```

- [ ] **V2025_01_15_03**: Добавить поля в таблицу `users.employee`
  ```sql
  ALTER TABLE users.employee
  ADD COLUMN primary_pickup_point_id TEXT,
  ADD COLUMN integration_data JSONB,
  ADD COLUMN current_status TEXT DEFAULT 'free';
  ```

- [ ] **V2025_01_15_04**: Создать таблицу `applications.courier_route_point`

- [ ] **V2025_01_15_05**: Создать таблицу `applications.courier_route_order`

- [ ] **V2025_01_15_06**: Создать таблицу `applications.courier_route_position`

- [ ] **V2025_01_15_07**: Создать таблицу `applications.courier_route_log`

- [ ] **V2025_01_15_08**: Создать таблицу `applications.courier_integration_log`

- [ ] **V2025_01_15_09**: Создать таблицу `dictionaries.courier_warehouse`

- [ ] **V2025_01_15_10**: Создать все enums и constraints

### 1.2 Проверка миграций

- [ ] Запустить `./gradlew flywayMigrate` локально
- [ ] Проверить создание всех таблиц
- [ ] Проверить индексы и constraints
- [ ] Обновить `/coube-documentation-new/database-architecture/` через скрипт

---

## Phase 2: Entity Classes

### 2.1 Создать Entity

- [ ] `kz.coube.backend.applications.entity.CourierRoutePoint`
  - [ ] Добавить аннотации JPA
  - [ ] Добавить связь с Transportation (ManyToOne)
  - [ ] Добавить связь с Orders (OneToMany)
  - [ ] Наследовать от AuditEntity

- [ ] `kz.coube.backend.applications.entity.CourierRouteOrder`
  - [ ] Связь с CourierRoutePoint
  - [ ] Связь с Positions
  - [ ] Уникальность track_number

- [ ] `kz.coube.backend.applications.entity.CourierRoutePosition`

- [ ] `kz.coube.backend.applications.entity.CourierRouteLog`

- [ ] `kz.coube.backend.applications.entity.CourierIntegrationLog`

- [ ] `kz.coube.backend.dictionaries.entity.CourierWarehouse`

### 2.2 Обновить существующие Entity

- [ ] **Transportation.java**: Добавить поля для курьерской доставки
  ```java
  @Column(name = "source_system")
  private String sourceSystem;
  
  @Column(name = "external_waybill_id")
  private String externalWaybillId;
  
  @Column(name = "delivery_type")
  private String deliveryType;
  
  @Column(name = "responsible_courier_warehouse_id")
  private String responsibleCourierWarehouseId;
  
  @Column(name = "target_delivery_day")
  private LocalDate targetDeliveryDay;
  
  @Column(name = "validation_status")
  @Enumerated(EnumType.STRING)
  private CourierValidationStatus validationStatus;
  
  @OneToMany(mappedBy = "transportation", cascade = CascadeType.ALL)
  private List<CourierRoutePoint> routePoints = new ArrayList<>();
  ```

- [ ] **Employee.java**: Добавить поля для курьеров
  ```java
  @Column(name = "primary_pickup_point_id")
  private String primaryPickupPointId;
  
  @Column(name = "integration_data", columnDefinition = "jsonb")
  @Type(JsonBinaryType.class)
  private String integrationData;
  
  @Column(name = "current_status")
  @Enumerated(EnumType.STRING)
  private EmployeeStatus currentStatus;
  ```

### 2.3 Создать Enums

- [ ] `kz.coube.backend.dictionaries.enumeration.CourierValidationStatus`
- [ ] `kz.coube.backend.dictionaries.enumeration.CourierPointStatus`
- [ ] `kz.coube.backend.dictionaries.enumeration.CourierOrderStatus`
- [ ] `kz.coube.backend.dictionaries.enumeration.CourierOrderStatusReason`
- [ ] `kz.coube.backend.dictionaries.enumeration.CourierEventType`
- [ ] `kz.coube.backend.dictionaries.enumeration.CourierActorType`
- [ ] `kz.coube.backend.dictionaries.enumeration.IntegrationType`
- [ ] `kz.coube.backend.dictionaries.enumeration.IntegrationStatus`
- [ ] `kz.coube.backend.dictionaries.enumeration.EmployeeStatus`

---

## Phase 3: Repositories

### 3.1 Создать Repository интерфейсы

- [ ] `kz.coube.backend.applications.repository.CourierRoutePointRepository`
  ```java
  public interface CourierRoutePointRepository extends JpaRepository<CourierRoutePoint, Long> {
    List<CourierRoutePoint> findByTransportationIdOrderBySortOrderAsc(Long transportationId);
    List<CourierRoutePoint> findByTransportationIdAndStatus(Long transportationId, CourierPointStatus status);
  }
  ```

- [ ] `kz.coube.backend.applications.repository.CourierRouteOrderRepository`
  ```java
  public interface CourierRouteOrderRepository extends JpaRepository<CourierRouteOrder, Long> {
    Optional<CourierRouteOrder> findByTrackNumber(String trackNumber);
    List<CourierRouteOrder> findByRoutePointId(Long routePointId);
    List<CourierRouteOrder> findByStatus(CourierOrderStatus status);
  }
  ```

- [ ] `kz.coube.backend.applications.repository.CourierRoutePositionRepository`

- [ ] `kz.coube.backend.applications.repository.CourierRouteLogRepository`

- [ ] `kz.coube.backend.applications.repository.CourierIntegrationLogRepository`

- [ ] `kz.coube.backend.dictionaries.repository.CourierWarehouseRepository`

### 3.2 Unit Tests для Repositories

- [ ] `CourierRoutePointRepositoryTest`
- [ ] `CourierRouteOrderRepositoryTest`
- [ ] `CourierIntegrationLogRepositoryTest`

---

## Phase 4: DTOs

### 4.1 Request DTOs

- [ ] `kz.coube.backend.integration.dto.WaybillImportRequest`
- [ ] `kz.coube.backend.integration.dto.WaybillHeader`
- [ ] `kz.coube.backend.integration.dto.DeliveryPoint`
- [ ] `kz.coube.backend.integration.dto.ReceiverInfo`
- [ ] `kz.coube.backend.integration.dto.OrderInfo`
- [ ] `kz.coube.backend.integration.dto.PositionInfo`
- [ ] `kz.coube.backend.courier.dto.CourierAssignRequest`
- [ ] `kz.coube.backend.courier.dto.PointStatusUpdateRequest`

### 4.2 Response DTOs

- [ ] `kz.coube.backend.integration.dto.WaybillImportResponse`
- [ ] `kz.coube.backend.integration.dto.ValidationError`
- [ ] `kz.coube.backend.courier.dto.CourierWaybillResponse`
- [ ] `kz.coube.backend.courier.dto.CourierWaybillListResponse`
- [ ] `kz.coube.backend.courier.dto.CourierOrderStatusResponse`
- [ ] `kz.coube.backend.courier.dto.ActiveWaybillResponse`
- [ ] `kz.coube.backend.courier.dto.DashboardSummaryResponse`

### 4.3 Mappers

- [ ] `kz.coube.backend.courier.mapper.CourierWaybillMapper`
  ```java
  @Mapper(componentModel = "spring")
  public interface CourierWaybillMapper {
    CourierWaybillResponse toResponse(Transportation transportation);
    // ... other methods
  }
  ```

- [ ] `kz.coube.backend.courier.mapper.CourierRouteMapper`

---

## Phase 5: Services

### 5.1 Integration Service

- [ ] **CourierIntegrationService**
  - [ ] `importWaybill(WaybillImportRequest request)`
  - [ ] `updateWaybill(String externalId, WaybillImportRequest request)`
  - [ ] `getWaybill(String externalId)`
  - [ ] `getOrderStatuses(String externalId)`
  - [ ] Валидация входящих данных
  - [ ] Логирование в CourierIntegrationLog
  - [ ] Транзакционность

- [ ] **Валидаторы**
  - [ ] Уникальность sort_order
  - [ ] Наличие финального склада
  - [ ] Геокодирование адресов
  - [ ] Проверка временных окон

- [ ] **Unit Tests**
  - [ ] `CourierIntegrationServiceTest`

### 5.2 Waybill Management Service

- [ ] **CourierWaybillService**
  - [ ] `getWaybills(Pageable, Filters)`
  - [ ] `getWaybillById(Long id)`
  - [ ] `updateWaybill(Long id, UpdateRequest)`
  - [ ] `validateWaybill(Long id)`
  - [ ] `assignCourier(Long id, Long courierId)`
  - [ ] `unassignCourier(Long id)`
  - [ ] `closeWaybill(Long id)`

- [ ] **Unit Tests**
  - [ ] `CourierWaybillServiceTest`

### 5.3 Mobile Service

- [ ] **CourierMobileService**
  - [ ] `getActiveWaybill(Long employeeId)`
  - [ ] `getWaybillHistory(Long employeeId, Pageable)`
  - [ ] `acceptWaybill(Long waybillId)`
  - [ ] `declineWaybill(Long waybillId, String reason)`
  - [ ] `startRoute(Long waybillId, LocationDto)`
  - [ ] `updatePointStatus(Long waybillId, Long pointId, StatusRequest)`
  - [ ] `completeRoute(Long waybillId)`
  - [ ] `finishRoute(Long waybillId)`
  - [ ] `uploadPhoto(MultipartFile, Long orderId)`
  - [ ] `reportProblem(ProblemRequest)`
  - [ ] `getDashboard(Long employeeId)`

- [ ] **Интеграция с существующими сервисами**
  - [ ] Использовать `DriverLocationService` для геолокации
  - [ ] Использовать `FileService` для загрузки фото
  - [ ] Использовать `NotificationService` для уведомлений

- [ ] **Unit Tests**
  - [ ] `CourierMobileServiceTest`

### 5.4 Results Export Service

- [ ] **CourierResultsService**
  - [ ] `queueResults(Long waybillId)`
  - [ ] `sendResults(Long waybillId)` (вызов TEEZ API)
  - [ ] `retryFailedResults()`
  - [ ] Логирование попыток
  - [ ] Обработка ошибок

- [ ] **Scheduler Job**
  - [ ] `CourierResultsDispatcherJob` (каждые 5 минут)

- [ ] **Unit Tests**
  - [ ] `CourierResultsServiceTest`

### 5.5 Warehouse Dictionary Service

- [ ] **CourierWarehouseService**
  - [ ] `getWarehouses(Filters)`
  - [ ] `createWarehouse(WarehouseRequest)`
  - [ ] `updateWarehouse(Long id, WarehouseRequest)`
  - [ ] `importWarehouses(List<WarehouseData>)`

---

## Phase 6: Controllers

### 6.1 Integration API

- [ ] **CourierIntegrationController** (`/api/v1/integration/teez`)
  - [ ] `POST /waybills` - создание/обновление маршрутного листа
  - [ ] `PUT /waybills/{externalWaybillId}` - обновление черновика
  - [ ] `GET /waybills/{externalWaybillId}` - получение маршрутного листа
  - [ ] `GET /waybills/{externalWaybillId}/orders` - статусы заказов
  - [ ] `POST /problem-address` - пометка проблемного адреса
  - [ ] Swagger аннотации
  - [ ] Валидация `@Valid`
  - [ ] Exception handling

- [ ] **Integration Tests**
  - [ ] `CourierIntegrationControllerIT`

### 6.2 Logist Web API

- [ ] **CourierLogistController** (`/api/v1/courier`)
  - [ ] `GET /waybills` - список маршрутных листов
  - [ ] `GET /waybills/{id}` - детали маршрутного листа
  - [ ] `PUT /waybills/{id}` - редактирование маршрута
  - [ ] `POST /waybills/{id}/validate` - валидация маршрута
  - [ ] `POST /waybills/{id}/assign` - назначение курьера
  - [ ] `POST /waybills/{id}/unassign` - снятие курьера
  - [ ] `POST /waybills/{id}/close` - закрытие маршрута
  - [ ] `GET /couriers` - список курьеров
  - [ ] `POST /couriers` - создание курьера
  - [ ] `PATCH /couriers/{id}` - обновление курьера
  - [ ] Авторизация `@AuthorizationRequired(roles = {LOGISTICIAN, ADMIN})`
  - [ ] Swagger документация

- [ ] **Integration Tests**
  - [ ] `CourierLogistControllerIT`

### 6.3 Mobile API

- [ ] **CourierMobileController** (`/api/v1/courier/mobile`)
  - [ ] `GET /waybills/active` - активный маршрут
  - [ ] `GET /waybills/history` - история маршрутов
  - [ ] `POST /waybills/{id}/accept` - принять маршрут
  - [ ] `POST /waybills/{id}/decline` - отклонить маршрут
  - [ ] `POST /waybills/{id}/start` - начать маршрут
  - [ ] `POST /waybills/{id}/points/{pointId}/status` - изменить статус точки
  - [ ] `POST /waybills/{id}/complete` - завершить маршрут
  - [ ] `POST /waybills/{id}/finish` - подтвердить возврат на склад
  - [ ] `POST /upload-photo` - загрузить фото
  - [ ] `POST /location` - отправить геолокацию (переиспользовать `DriverLocationController`)
  - [ ] `GET /dashboard` - сводка для курьера
  - [ ] `POST /report-problem` - сообщить о проблеме
  - [ ] `POST /sos` - экстренный вызов (переиспользовать из `DriverController`)
  - [ ] Авторизация `@AuthorizationRequired(roles = {DRIVER})`

- [ ] **Integration Tests**
  - [ ] `CourierMobileControllerIT`

---

## Phase 7: Configuration

### 7.1 Application Configuration

- [ ] **application.yml**: Добавить конфигурацию
  ```yaml
  courier:
    integration:
      teez:
        enabled: true
        api-url: ${TEEZ_API_URL}
        api-token: ${TEEZ_API_TOKEN}
        retry:
          max-attempts: 48
          interval-minutes: 30
        rate-limit:
          requests-per-minute: 60
    mobile:
      location-tracking:
        interval-seconds: 30
      photo:
        max-size-mb: 5
        storage-path: courier/photos
  ```

- [ ] **CourierConfigProperties.java**: Config bean
  ```java
  @ConfigurationProperties(prefix = "courier")
  @Data
  public class CourierConfigProperties {
    private IntegrationConfig integration;
    private MobileConfig mobile;
  }
  ```

### 7.2 Keycloak Configuration

- [ ] Создать новый client `coube-integration-teez`
- [ ] Настроить Client Credentials flow
- [ ] Создать scope `courier:integration`
- [ ] Добавить конфигурацию в Keycloak admin

### 7.3 Security Configuration

- [ ] Добавить endpoint matchers в SecurityConfig
  ```java
  .requestMatchers("/api/v1/integration/teez/**").hasAuthority("SCOPE_courier:integration")
  .requestMatchers("/api/v1/courier/mobile/**").hasRole("DRIVER")
  .requestMatchers("/api/v1/courier/**").hasAnyRole("LOGISTICIAN", "ADMIN")
  ```

---

## Phase 8: Integration with TEEZ

### 8.1 HTTP Client для TEEZ API

- [ ] **TeezApiClient**
  - [ ] `sendResults(WaybillResultsRequest)`
  - [ ] Обработка ошибок и ретраев
  - [ ] Таймауты и circuit breaker

- [ ] **Конфигурация RestTemplate/WebClient**
  ```java
  @Bean
  public RestTemplate teezRestTemplate() {
    // ... configuration
  }
  ```

### 8.2 Queue/Scheduler

- [ ] **CourierResultsQueue** (можно использовать DB таблицу как очередь)
- [ ] **CourierResultsDispatcherJob** (Spring @Scheduled)
  ```java
  @Scheduled(fixedDelay = 300000) // 5 минут
  public void dispatchResults() {
    courierResultsService.retryFailedResults();
  }
  ```

---

## Phase 9: Notifications

### 9.1 Новые типы уведомлений

- [ ] Добавить в `NotificationType`:
  - `COURIER_ASSIGNED`
  - `COURIER_ROUTE_STARTED`
  - `COURIER_ORDER_DELIVERED`
  - `COURIER_ROUTE_COMPLETED`

- [ ] Интеграция с существующим `NotificationService`

### 9.2 WhatsApp Templates

- [ ] Создать шаблоны в WhatsApp Business API для курьеров
- [ ] Добавить в `WhatsAppTemplate` enum

---

## Phase 10: Testing

### 10.1 Unit Tests

- [ ] Repositories: 100% coverage
- [ ] Services: 90%+ coverage
- [ ] Mappers: 100% coverage
- [ ] Validators: 100% coverage

### 10.2 Integration Tests

- [ ] `CourierIntegrationControllerIT`
- [ ] `CourierLogistControllerIT`
- [ ] `CourierMobileControllerIT`
- [ ] `CourierResultsServiceIT`

### 10.3 End-to-End Tests

- [ ] `CourierWorkflowE2ETest`:
  1. Import waybill from TEEZ
  2. Logist validates and assigns courier
  3. Courier accepts and starts route
  4. Courier updates point statuses
  5. Courier completes route
  6. Results sent to TEEZ
  7. Logist closes waybill

---

## Phase 11: Documentation

### 11.1 API Documentation

- [ ] Обновить Swagger/OpenAPI specs
- [ ] Добавить примеры запросов/ответов
- [ ] Документировать коды ошибок

### 11.2 Developer Documentation

- [ ] README для модуля courier
- [ ] Архитектурная диаграмма
- [ ] Sequence diagrams для основных флоу

### 11.3 Integration Guide для TEEZ

- [ ] API documentation для TEEZ разработчиков
- [ ] Примеры curl запросов
- [ ] Webhook спецификация
- [ ] Error codes и troubleshooting

---

## Phase 12: Deployment

### 12.1 Database

- [ ] Применить миграции на staging
- [ ] Применить миграции на production
- [ ] Backup БД перед миграцией

### 12.2 Application

- [ ] Build и deploy на staging
- [ ] Smoke tests на staging
- [ ] Deploy на production
- [ ] Мониторинг после деплоя

### 12.3 Keycloak

- [ ] Создать integration client на staging
- [ ] Создать integration client на production
- [ ] Передать credentials TEEZ команде

---

## Phase 13: Monitoring & Alerting

### 13.1 Metrics

- [ ] Добавить метрики:
  - `courier_waybills_imported_total`
  - `courier_results_sent_total`
  - `courier_results_failed_total`
  - `courier_routes_completed_total`

### 13.2 Logging

- [ ] Логирование всех интеграционных вызовов
- [ ] Error tracking (Sentry)
- [ ] Performance monitoring (APM)

### 13.3 Alerts

- [ ] High retry rate
- [ ] Failed results delivery
- [ ] TEEZ API down
- [ ] Database query slow

---

## Финальная проверка

- [ ] Все unit tests проходят
- [ ] Все integration tests проходят
- [ ] E2E тест проходит успешно
- [ ] API документация актуальна
- [ ] Migrations applied без ошибок
- [ ] Мониторинг настроен
- [ ] TEEZ команда получила документацию
- [ ] Проведен demo для stakeholders
- [ ] Получен sign-off от Product Owner

---

**Estimated Timeline**: 6 недель  
**Team Size**: 2-3 backend разработчика  
**Dependencies**: TEEZ команда для тестирования интеграции
