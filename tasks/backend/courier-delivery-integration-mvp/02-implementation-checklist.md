# 11. Упрощенный чеклист реализации курьерской доставки

## Обзор

Пошаговый чеклист для быстрой реализации MVP курьерской доставки с максимальным переиспользованием существующего кода.

**Оценка**: 2-3 недели (1 разработчик)

---

## 📅 Week 1: Database & Entity Layer

### 1.1 Подготовка

- [ ] Создать ветку `feature/courier-delivery-mvp`
- [ ] Изучить существующие entity: `Transportation`, `TransportationRouteHistory`, `CargoLoadingHistory`
- [ ] Изучить `DriverController` и `DriverService`

### 1.2 Flyway Migrations

- [ ] **V2025_01_20_01__add_courier_delivery_type.sql**
  ```sql
  DO $$
  BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumlabel = 'COURIER_DELIVERY' 
                   AND enumtypid = 'transportation_type'::regtype) THEN
      ALTER TYPE dictionaries.transportation_type ADD VALUE 'COURIER_DELIVERY';
    END IF;
  END
  $$;
  ```

- [ ] **V2025_01_20_02__add_courier_fields_to_transportation.sql**
  - [ ] `source_system TEXT`
  - [ ] `external_waybill_id TEXT`
  - [ ] `courier_validation_status TEXT DEFAULT 'imported'`
  - [ ] Индексы на внешние ключи

- [ ] **V2025_01_20_03__add_courier_fields_to_cargo_loading.sql**
  - [ ] `is_sms_required BOOLEAN`
  - [ ] `is_photo_required BOOLEAN`
  - [ ] `courier_warehouse_id TEXT`

- [ ] **V2025_01_20_04__create_courier_tables.sql**
  - [ ] Таблица `courier_route_order`
  - [ ] Таблица `courier_integration_log`
  - [ ] Индексы и комментарии

- [ ] Применить миграции локально: `./gradlew flywayMigrate`
- [ ] Проверить создание таблиц в БД
- [ ] Обновить документацию БД: `./coube-documentation-new/database-architecture/update-db-docs.sh`

### 1.3 Обновить messages.properties

- [ ] Добавить локализацию для `COURIER_DELIVERY`:
  ```properties
  enum.transportation-type.COURIER_DELIVERY.kk=Курьерлік жеткізу
  enum.transportation-type.COURIER_DELIVERY.ru=Курьерская доставка
  enum.transportation-type.COURIER_DELIVERY.en=Courier delivery
  enum.transportation-type.COURIER_DELIVERY.zh=快递
  ```

### 1.4 Enum Classes

- [ ] **TransportationType.java**: Добавить `COURIER_DELIVERY`
  ```java
  public enum TransportationType {
    FTL,
    BULK,
    CITY,
    LTL,
    COURIER_DELIVERY; // ← NEW
  }
  ```

- [ ] **CourierValidationStatus.java** (новый)
  ```java
  public enum CourierValidationStatus {
    IMPORTED,    // Импортирован из внешней системы
    VALIDATED,   // Провалидирован логистом
    ASSIGNED,    // Назначен курьеру
    CLOSED       // Закрыт логистом
  }
  ```

- [ ] **CourierOrderStatus.java** (новый)
  ```java
  public enum CourierOrderStatus {
    PENDING,
    DELIVERED,
    RETURNED,
    PARTIALLY_RETURNED,
    NOT_DELIVERED
  }
  ```

- [ ] **CourierOrderStatusReason.java** (новый)
  ```java
  public enum CourierOrderStatusReason {
    CUSTOMER_NOT_AVAILABLE,
    CUSTOMER_POSTPONED,
    FORCE_MAJEURE
  }
  ```

### 1.5 Entity Classes (новые)

- [ ] **CourierRouteOrder.java**
  - [ ] Связь с `CargoLoadingHistory` (ManyToOne)
  - [ ] Связь с `FileMetaInfo` для фото (ManyToOne)
  - [ ] Поле `positions` (JSONB)
  - [ ] Все поля из миграции
  - [ ] Extends `AuditEntity`

- [ ] **CourierIntegrationLog.java**
  - [ ] Связь с `Transportation` (ManyToOne)
  - [ ] Все поля из миграции
  - [ ] JSONB поля для request/response

### 1.6 Обновить существующие Entity

- [ ] **Transportation.java**: Добавить поля
  ```java
  @Column(name = "source_system")
  private String sourceSystem;
  
  @Column(name = "external_waybill_id")
  private String externalWaybillId;
  
  @Column(name = "courier_validation_status")
  @Enumerated(EnumType.STRING)
  private CourierValidationStatus courierValidationStatus;
  ```

- [ ] **CargoLoadingHistory.java**: Добавить поля
  ```java
  @Column(name = "is_sms_required")
  private Boolean isSmsRequired;
  
  @Column(name = "is_photo_required")
  private Boolean isPhotoRequired;
  
  @Column(name = "courier_warehouse_id")
  private String courierWarehouseId;
  
  @OneToMany(mappedBy = "cargoLoadingHistory", cascade = CascadeType.ALL)
  private List<CourierRouteOrder> courierOrders = new ArrayList<>();
  ```

### 1.7 Repositories

- [ ] **CourierRouteOrderRepository.java**
  ```java
  public interface CourierRouteOrderRepository extends JpaRepository<CourierRouteOrder, Long> {
    Optional<CourierRouteOrder> findByTrackNumber(String trackNumber);
    List<CourierRouteOrder> findByCargoLoadingHistoryId(Long cargoLoadingHistoryId);
    List<CourierRouteOrder> findByStatus(CourierOrderStatus status);
  }
  ```

- [ ] **CourierIntegrationLogRepository.java**
  ```java
  public interface CourierIntegrationLogRepository extends JpaRepository<CourierIntegrationLog, Long> {
    List<CourierIntegrationLog> findByTransportationId(Long transportationId);
    List<CourierIntegrationLog> findBySourceSystemAndStatus(String sourceSystem, String status);
  }
  ```

### 1.8 Unit Tests для Repositories

- [ ] `CourierRouteOrderRepositoryTest`
  - [ ] Тест создания заказа
  - [ ] Тест поиска по track number
  - [ ] Тест связи с CargoLoadingHistory

- [ ] `CourierIntegrationLogRepositoryTest`
  - [ ] Тест создания лога
  - [ ] Тест поиска по transportation

---

## 📅 Week 2: Integration API & Services

### 2.1 DTO Classes

**Request DTOs**:

- [ ] **WaybillImportRequest.java**
  ```java
  @Data @Builder
  public class WaybillImportRequest {
    private String sourceSystem; // TEEZ_PVZ, KASPI, etc.
    private WaybillHeader waybill;
    private List<DeliveryPoint> deliveries;
  }
  ```

- [ ] **WaybillHeader.java**
- [ ] **DeliveryPoint.java**
- [ ] **ReceiverInfo.java**
- [ ] **OrderInfo.java**
- [ ] **PositionInfo.java**

**Response DTOs**:

- [ ] **WaybillImportResponse.java**
  ```java
  @Data @Builder
  public class WaybillImportResponse {
    private String status;
    private Long transportationId;
    private String externalWaybillId;
    private Instant createdAt;
    private String message;
    private List<ValidationError> errors;
  }
  ```

- [ ] **OrderStatusDto.java**
- [ ] **ValidationError.java**

### 2.2 API Key аутентификация (упрощенная)

**Цель**: Простая защита Integration API без БД и Admin UI

- [ ] Создать `CourierIntegrationProperties`
  ```java
  @Component
  @ConfigurationProperties("courier.integration")
  public class CourierIntegrationProperties {
    private String apiKey; // Статический из env
    private TeezConfig teez;
  }
  ```

- [ ] Создать `CourierApiKeyFilter`
  ```java
  @Component
  public class CourierApiKeyFilter extends OncePerRequestFilter {
    // Проверяет X-API-Key header
    // Простое сравнение: properties.getApiKey().equals(apiKey)
    // Применяется только к /api/v1/integration/**
  }
  ```

- [ ] Обновить `SecurityConfig`
  ```java
  .addFilterBefore(courierApiKeyFilter, UsernamePasswordAuthenticationFilter.class)
  .requestMatchers("/api/v1/integration/**")
  .hasAuthority("SCOPE_courier:integration")
  ```

- [ ] Добавить в `application.yml`
  ```yaml
  courier:
    integration:
      api-key: ${COURIER_API_KEY:dev-test-key}
      teez:
        api-url: ${TEEZ_API_URL}
        endpoint: /api/waybill/results
  ```

- [ ] Генерировать production ключ
  ```bash
  openssl rand -base64 32
  # coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
  ```

- [ ] Создать Kubernetes Secret
  ```yaml
  apiVersion: v1
  kind: Secret
  metadata:
    name: courier-api-key
  stringData:
    api-key: coube_prod_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
  ```

- [ ] Unit тесты:
  - [ ] Тест с валидным ключом → success
  - [ ] Тест с невалидным ключом → 401
  - [ ] Тест без ключа → 401

- [ ] Integration тест
  ```java
  @Test
  void shouldAllow_whenValidApiKey() {
    mockMvc.perform(post("/api/v1/integration/waybills")
      .header("X-API-Key", validApiKey))
      .andExpect(status().isOk());
  }
  ```

- [ ] Передать API ключ TEEZ команде (через защищенный канал: 1Password/LastPass)

**Время**: 2-4 часа  
**См. детали**: `04-api-key-authentication-simplified.md`

### 2.3 CourierIntegrationService

- [ ] Создать `kz.coube.backend.courier.service.CourierIntegrationService`

- [ ] Метод `importWaybill(WaybillImportRequest request)`
  - [ ] Проверка дубликатов по `external_waybill_id`
  - [ ] Создание `Transportation` с типом `COURIER_DELIVERY`
  - [ ] Создание `TransportationRouteHistory` через `TransportationRouteService`
  - [ ] Создание `CargoLoadingHistory` для каждой точки
  - [ ] Создание `CourierRouteOrder` для каждого заказа
  - [ ] Логирование в `CourierIntegrationLog`
  - [ ] Обработка ошибок

- [ ] Метод `updateWaybill(Transportation t, WaybillImportRequest request)`
  - [ ] Проверка статуса (можно обновлять только IMPORTED)
  - [ ] Обновление маршрута
  - [ ] Логирование

- [ ] Метод `getOrderStatuses(String externalWaybillId, String sourceSystem)`
  - [ ] Поиск Transportation
  - [ ] Сбор всех заказов из всех точек
  - [ ] Возврат статусов

- [ ] Вспомогательные методы:
  - [ ] `createRouteFromWaybill()` - создание маршрута
  - [ ] `mapLoadType()` - маппинг типов загрузки
  - [ ] `logIntegration()` - логирование
  - [ ] `toJson()` / `fromJson()` - JSON конвертация

### 2.3 CourierIntegrationController

- [ ] Создать `kz.coube.backend.courier.api.CourierIntegrationController`
- [ ] Base path: `/api/v1/integration`

- [ ] `POST /waybills` - импорт маршрутного листа
  - [ ] `@Valid` валидация request
  - [ ] Вызов `courierIntegrationService.importWaybill()`
  - [ ] Обработка ошибок
  - [ ] Swagger аннотации

- [ ] `GET /waybills/{externalWaybillId}/orders` - статусы заказов
  - [ ] Параметр `sourceSystem` (required)
  - [ ] Вызов `courierIntegrationService.getOrderStatuses()`
  - [ ] Swagger аннотации

### 2.4 API Key Authentication (простая версия)

- [ ] Создать `ApiKeyAuthenticationFilter`
  - [ ] Чтение `X-API-Key` заголовка
  - [ ] Проверка ключа (пока hardcoded в конфиге)
  - [ ] Установка Authentication в SecurityContext

- [ ] Обновить `SecurityConfig`
  - [ ] Добавить фильтр перед стандартной аутентификацией
  - [ ] Разрешить `/api/v1/integration/**` для API ключа

- [ ] Добавить в `application.yml`:
  ```yaml
  courier:
    integration:
      api-key: ${COURIER_API_KEY:test-api-key-change-in-production}
      teez:
        api-url: ${TEEZ_API_URL:https://teez-api.example.com}
  ```

### 2.5 Unit Tests для Services

- [ ] `CourierIntegrationServiceTest`
  - [ ] Тест успешного импорта
  - [ ] Тест импорта дубликата
  - [ ] Тест обновления IMPORTED статуса
  - [ ] Тест блокировки обновления VALIDATED статуса
  - [ ] Тест создания маршрута с точками
  - [ ] Тест создания заказов
  - [ ] Тест получения статусов заказов

### 2.6 Integration Tests для Controllers

- [ ] `CourierIntegrationControllerIT`
  - [ ] Тест POST /waybills с валидным payload
  - [ ] Тест POST /waybills с невалидным payload
  - [ ] Тест GET /waybills/{id}/orders
  - [ ] Тест аутентификации по API key

---

## 📅 Week 3: Mobile API & Results Sending

### 3.1 CourierOrderService

- [ ] Создать `kz.coube.backend.courier.service.CourierOrderService`

- [ ] Метод `updateStatus(Long transportationId, Long orderId, CourierOrderStatusUpdateRequest)`
  - [ ] Проверка принадлежности заказа к transportation
  - [ ] Обновление статуса
  - [ ] Обновление причины статуса
  - [ ] Сохранение SMS кода
  - [ ] Сохранение комментария
  - [ ] Возврат обновленного заказа

- [ ] Метод `uploadPhoto(Long orderId, MultipartFile file)`
  - [ ] Использование `FileService.uploadFile()`
  - [ ] Связь фото с заказом
  - [ ] Валидация размера/формата

- [ ] Метод `updateReturnedPositions(Long orderId, List<PositionReturnDto>)`
  - [ ] Обновление JSON с возвращенными количествами
  - [ ] Автоматический расчет статуса (PARTIALLY_RETURNED)

### 3.2 Дополнение DriverController

- [ ] Добавить метод в `kz.coube.backend.driver.api.DriverController`:
  ```java
  @PutMapping("orders/{transportationId}/courier-orders/{orderId}/status")
  @Operation(summary = "Обновить статус заказа курьерской доставки")
  public ResponseEntity<CourierOrderStatusResponse> updateCourierOrderStatus(
      @PathVariable Long transportationId,
      @PathVariable Long orderId,
      @Valid @RequestBody CourierOrderStatusUpdateRequest request) {
    
    CourierRouteOrder order = courierOrderService.updateStatus(transportationId, orderId, request);
    return ResponseEntity.ok(toResponse(order));
  }
  ```

- [ ] DTO: `CourierOrderStatusUpdateRequest`
- [ ] DTO: `CourierOrderStatusResponse`

### 3.3 CourierResultsService

- [ ] Создать `kz.coube.backend.courier.service.CourierResultsService`

- [ ] Метод `sendResultsSync(Long transportationId)`
  - [ ] Проверка типа Transportation (должен быть COURIER_DELIVERY)
  - [ ] Сбор всех заказов из всех точек
  - [ ] Формирование payload `WaybillResultsPayload`
  - [ ] Определение URL маркетплейса по `source_system`
  - [ ] Синхронная отправка через `RestTemplate`
  - [ ] Логирование в `CourierIntegrationLog`
  - [ ] Обработка ошибок

- [ ] Метод `buildResultsPayload(Transportation transportation)`
  - [ ] Сбор всех `CargoLoadingHistory` точек
  - [ ] Для каждой точки - все `CourierRouteOrder`
  - [ ] Маппинг в `DeliveryResultDto`
  - [ ] Включение фото URL (если есть)

- [ ] Метод `determineMarketplaceUrl(String sourceSystem)`
  - [ ] Чтение из конфигурации для каждого маркетплейса
  - [ ] TEEZ, Kaspi, Wildberries, Ozon

- [ ] Вспомогательные методы:
  - [ ] `mapToExternalStatus()` - конвертация внутренних статусов в формат маркетплейса

### 3.4 DTO для отправки результатов

- [ ] **WaybillResultsPayload.java**
  ```java
  @Data @Builder
  public class WaybillResultsPayload {
    private String waybillId;
    private Instant completedAt;
    private List<DeliveryResultDto> deliveryResults;
  }
  ```

- [ ] **DeliveryResultDto.java**
  ```java
  @Data @Builder
  public class DeliveryResultDto {
    private String trackNumber;
    private String externalId;
    private String status;
    private String statusReason;
    private Instant deliveryDatetime;
    private String photoUrl;
    private String courierComment;
  }
  ```

### 3.5 RestTemplate Configuration

- [ ] Создать `CourierIntegrationConfig`
  ```java
  @Configuration
  public class CourierIntegrationConfig {
    
    @Bean("courierRestTemplate")
    public RestTemplate courierRestTemplate() {
      RestTemplate template = new RestTemplate();
      template.setRequestFactory(new HttpComponentsClientHttpRequestFactory());
      // Таймауты, interceptors, error handlers
      return template;
    }
  }
  ```

### 3.6 Интеграция с логистом (использование существующего UI)

- [ ] Проверить, что `TransportationService` поддерживает:
  - [ ] Назначение водителя на Transportation с типом COURIER_DELIVERY
  - [ ] Обновление статуса на CLOSED

- [ ] Добавить вызов `CourierResultsService.sendResultsSync()` при закрытии:
  ```java
  // В TransportationService или отдельном listener
  if (TransportationType.COURIER_DELIVERY.equals(transportation.getTransportationType()) 
      && CourierValidationStatus.CLOSED.equals(transportation.getCourierValidationStatus())) {
    courierResultsService.sendResultsSync(transportation.getId());
  }
  ```

### 3.7 Unit Tests

- [ ] `CourierOrderServiceTest`
  - [ ] Тест обновления статуса
  - [ ] Тест загрузки фото
  - [ ] Тест частичного возврата

- [ ] `CourierResultsServiceTest`
  - [ ] Тест формирования payload
  - [ ] Тест отправки результатов
  - [ ] Тест обработки ошибок маркетплейса
  - [ ] Mock RestTemplate

### 3.8 Integration Tests

- [ ] `DriverControllerCourierIT`
  - [ ] Тест обновления статуса заказа через DriverController
  - [ ] Тест что курьер может обновить только свои заказы

---

## 📅 Final: Testing & Documentation

### 4.1 End-to-End Test

- [ ] `CourierDeliveryWorkflowE2ETest`
  1. [ ] Импорт маршрутного листа от TEEZ
  2. [ ] Логист назначает курьера (через существующий API)
  3. [ ] Курьер принимает заявку (через DriverController)
  4. [ ] Курьер начинает маршрут
  5. [ ] Курьер обновляет статусы точек (arrival/departure)
  6. [ ] Курьер обновляет статусы заказов
  7. [ ] Курьер завершает маршрут
  8. [ ] Логист закрывает маршрут
  9. [ ] Результаты отправляются в TEEZ
  10. [ ] Проверка логов интеграции

### 4.2 Performance Tests

- [ ] Тест импорта маршрута с 50 точками и 200 заказами
- [ ] Тест получения статусов для большого маршрута
- [ ] Проверка N+1 query проблем

### 4.3 API Documentation

- [ ] Обновить Swagger/OpenAPI specs
- [ ] Добавить примеры запросов/ответов для всех endpoints
- [ ] Документировать коды ошибок

- [ ] Создать `README.md` для TEEZ интеграции:
  - [ ] Как получить API key
  - [ ] Примеры curl запросов
  - [ ] Форматы payload
  - [ ] Коды ошибок
  - [ ] Webhook спецификация (для получения результатов)

### 4.4 Configuration

- [ ] Обновить `application.yml`:
  ```yaml
  courier:
    integration:
      api-key: ${COURIER_API_KEY}
      teez:
        enabled: true
        api-url: ${TEEZ_API_URL}
        endpoint: /api/waybill/results
      kaspi:
        enabled: false
        api-url: ${KASPI_API_URL}
        endpoint: /api/v1/courier/delivery-results
  ```

- [ ] Создать `application-courier.yml` для изоляции конфигурации

### 4.5 Deployment Preparation

- [ ] Проверить миграции на staging
- [ ] Создать changelog для release notes
- [ ] Подготовить rollback план
- [ ] Обновить monitoring dashboards

---

## 📊 Checklist Summary

### Database
- [ ] 4 Flyway миграции
- [ ] 2 новых таблицы
- [ ] 3 поля в Transportation
- [ ] 3 поля в CargoLoadingHistory

### Code
- [ ] 4 новых Enum
- [ ] 2 новых Entity
- [ ] 2 новых Repository
- [ ] 3 новых Service
- [ ] 1 новый Controller
- [ ] 1 метод в существующий Controller
- [ ] ~15 DTO классов
- [ ] 1 Config Properties класс (CourierIntegrationProperties)
- [ ] 1 Security Filter (CourierApiKeyFilter) - упрощенный без БД

### Tests
- [ ] 10+ Unit tests
- [ ] 5+ Integration tests
- [ ] 1 E2E test

### Documentation
- [ ] API documentation (Swagger)
- [ ] Integration guide для TEEZ
- [ ] README обновлен

---

## ⚠️ Важные замечания

### Не ломаем существующую логику

✅ **Используем существующие таблицы и сервисы**:
- `Transportation` - только добавляем 3 поля
- `CargoLoadingHistory` - только добавляем 3 поля  
- `DriverController` - добавляем 1 метод
- `DriverService` - НЕ трогаем вообще!

✅ **Новый тип перевозки** не влияет на существующие FLT, BULK, CITY, LTL

✅ **Курьер = водитель** с той же ролью `DRIVER`, различие только по типу Transportation

### Что может потребовать доработки после MVP

- Асинхронная отправка результатов с retry (scheduler)
- Управление API ключами через admin UI
- Геокодирование адресов
- Детальная валидация маршрутов
- Rate limiting для Integration API
- Аналитика и отчеты для логистов
- История изменений маршрутов
- Управление складами/ПВЗ

---

## ✅ Definition of Done

### Каждая задача считается завершенной когда:

- [ ] Код написан и прошел self-review
- [ ] Unit тесты написаны и проходят
- [ ] Integration тесты написаны и проходят
- [ ] Swagger документация обновлена
- [ ] Нет warnings от компилятора
- [ ] Нет критичных issues от SonarQube (если есть)
- [ ] Code review пройден
- [ ] Merged в feature branch

### MVP считается завершенным когда:

- [ ] Все миграции применены на dev/staging
- [ ] Все тесты проходят (включая E2E)
- [ ] API документация создана
- [ ] TEEZ integration guide готов
- [ ] Проведен demo для stakeholders
- [ ] Performance тесты пройдены
- [ ] Готов к deploy на production

---

**Estimated Timeline**: 2-3 недели  
**Team Size**: 1 backend разработчик  
**Risk Level**: Low (максимальное переиспользование существующего кода)  
**Dependencies**: Минимальные (не требует изменений в других модулях)
