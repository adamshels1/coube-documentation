# 07. Webhook для получения результатов доставки TEEZ

## Обзор

**Изменение архитектуры интеграции**: Вместо того, чтобы Coube отправлял результаты доставки в TEEZ (push-модель), необходимо реализовать webhook endpoint, через который TEEZ будет запрашивать результаты (pull-модель).

**Статус**: Draft
**Дата создания**: 2025-10-16
**Приоритет**: High

---

## Проблема

### Текущая архитектура (TO-BE CHANGED)

Согласно документации:
- `coube-documentation/business_analysis/converted/courier_delivery_flow_ascii.md:81-82`
- `coube-documentation/tasks/backend/courier-delivery-integration-mvp/03-api-examples.md:588-643`

Текущий flow:
```
┌─────────────┐                    ┌─────────────┐
│   COUBE     │   POST results     │  TEEZ_PVZ   │
│             ├───────────────────►│             │
│   Platform  │   (async queue)    │   System    │
└─────────────┘                    └─────────────┘
```

**Проблемы**:
1. Coube должен знать endpoint TEEZ API
2. Необходима асинхронная очередь и retry механизм
3. Сложная обработка ошибок при недоступности TEEZ
4. TEEZ не контролирует момент получения данных

### Новая архитектура (TO-BE)

```
┌─────────────┐                    ┌─────────────┐
│   COUBE     │◄───────────────────┤  TEEZ_PVZ   │
│             │   GET results      │             │
│   Platform  │   (webhook)        │   System    │
└─────────────┘                    └─────────────┘
```

**Преимущества**:
1. TEEZ контролирует момент получения данных
2. Упрощается логика на стороне Coube (нет очередей)
3. TEEZ сам управляет retry-логикой
4. Снижается coupling между системами

---

## Решение

### 1. Новый Webhook Endpoint

#### 1.1 Endpoint для получения результатов по маршрутному листу

**URL**: `GET /api/v1/integration/courier/waybills/{externalWaybillId}/results`

**Параметры запроса**:
- `externalWaybillId` (path) - ID маршрутного листа в системе TEEZ
- `source_system` (query, optional) - источник данных, default: `TEEZ_PVZ`

**Headers**:
```
X-API-Key: {teez-api-key}
Accept: application/json
```

**Response 200 OK**:
```json
{
  "waybill_id": "WB-2025-001",
  "transportation_id": 12345,
  "status": "completed",
  "completed_at": "2025-01-07T16:00:00Z",
  "delivery_results": [
    {
      "track_number": "TRACK-123456",
      "external_id": "ORDER-TEEZ-001",
      "status": "delivered",
      "status_reason": null,
      "delivery_datetime": "2025-01-07T10:15:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg",
      "courier_comment": null,
      "sms_code_used": "1234",
      "positions": [
        {
          "code": "POS-001",
          "name": "Товар 1",
          "qty": 1,
          "returned_qty": 0
        },
        {
          "code": "POS-002",
          "name": "Товар 2",
          "qty": 1,
          "returned_qty": 0
        }
      ]
    },
    {
      "track_number": "TRACK-123457",
      "external_id": "ORDER-TEEZ-002",
      "status": "not_delivered",
      "status_reason": "customer_not_available",
      "delivery_datetime": "2025-01-07T14:05:00Z",
      "photo_url": null,
      "courier_comment": "Клиент не отвечает на звонки",
      "positions": [
        {
          "code": "POS-003",
          "name": "Документы",
          "qty": 1,
          "returned_qty": 1
        }
      ]
    }
  ],
  "additional_events": [
    {
      "order_external_id": "ORDER-TEEZ-003",
      "event_type": "previous_order_not_received",
      "event_datetime": "2025-01-07T15:00:00Z",
      "comment": "По этому адресу ранее не удалось доставить заказ"
    }
  ]
}
```

**Response 404 Not Found**:
```json
{
  "error": "WAYBILL_NOT_FOUND",
  "message": "Waybill with external ID 'WB-2025-001' not found",
  "external_waybill_id": "WB-2025-001",
  "source_system": "TEEZ_PVZ"
}
```

**Response 409 Conflict** (если маршрут еще не завершен):
```json
{
  "error": "WAYBILL_NOT_COMPLETED",
  "message": "Waybill is not completed yet",
  "external_waybill_id": "WB-2025-001",
  "current_status": "ON_THE_WAY",
  "completed_points": 2,
  "total_points": 4
}
```

#### 1.2 Webhook для уведомления о завершении маршрута (опционально)

Если TEEZ хочет получать уведомления о готовности данных, Coube может отправлять webhook-уведомление:

**URL** (предоставляется TEEZ): `POST {teez_webhook_url}/waybill-completed`

**Request Body**:
```json
{
  "external_waybill_id": "WB-2025-001",
  "transportation_id": 12345,
  "completed_at": "2025-01-07T16:00:00Z",
  "results_available": true,
  "results_url": "https://api.coube.kz/api/v1/integration/courier/waybills/WB-2025-001/results?source_system=TEEZ_PVZ"
}
```

---

## Изменения в документации

### 2.1 Файлы для обновления

1. **`courier_delivery_flow_ascii.md`** (строки 76-82)
   - **Было**: `POST результаты в TEEZ_PVZ (async)`
   - **Стало**: `Webhook notification (optional) + TEEZ pulls results via API`

2. **`03-api-examples.md`** (раздел 10)
   - Удалить секцию "10. Отправка результатов в TEEZ"
   - Добавить секцию "10. Получение результатов через webhook"

3. **`01-mvp-plan.md`** и **`02-implementation-checklist.md`**
   - Обновить секции про асинхронную очередь результатов
   - Заменить на webhook endpoint

---

## Реализация

### 3.1 Backend Changes

#### Controller

**Новый класс**: `CourierIntegrationWebhookController`

```java
@RestController
@RequestMapping("/api/v1/integration/courier")
@Validated
public class CourierIntegrationWebhookController {

    @Autowired
    private CourierWaybillResultsService waybillResultsService;

    @GetMapping("/waybills/{externalWaybillId}/results")
    @ResponseStatus(HttpStatus.OK)
    public CourierWaybillResultsDTO getWaybillResults(
            @PathVariable String externalWaybillId,
            @RequestParam(defaultValue = "TEEZ_PVZ") String sourceSystem,
            @RequestHeader("X-API-Key") String apiKey
    ) {
        // 1. Validate API key
        validateApiKey(apiKey, sourceSystem);

        // 2. Get waybill results
        return waybillResultsService.getWaybillResults(externalWaybillId, sourceSystem);
    }
}
```

#### Service

**Новый сервис**: `CourierWaybillResultsService`

```java
@Service
public class CourierWaybillResultsService {

    @Autowired
    private TransportationRepository transportationRepository;

    @Autowired
    private CourierRouteOrderRepository courierRouteOrderRepository;

    @Autowired
    private CargoLoadingHistoryRepository cargoLoadingHistoryRepository;

    public CourierWaybillResultsDTO getWaybillResults(String externalWaybillId, String sourceSystem) {
        // 1. Find transportation by external waybill ID
        Transportation transportation = transportationRepository
            .findByExternalWaybillIdAndSourceSystem(externalWaybillId, sourceSystem)
            .orElseThrow(() -> new WaybillNotFoundException(externalWaybillId, sourceSystem));

        // 2. Check if waybill is completed
        if (!isWaybillCompleted(transportation)) {
            throw new WaybillNotCompletedException(
                externalWaybillId,
                transportation.getStatus(),
                getCompletionProgress(transportation)
            );
        }

        // 3. Build results DTO
        return buildWaybillResultsDTO(transportation);
    }

    private boolean isWaybillCompleted(Transportation transportation) {
        return transportation.getStatus() == TransportationStatus.COMPLETED ||
               transportation.getStatus() == TransportationStatus.CLOSED_BY_LOGIST;
    }

    private CourierWaybillResultsDTO buildWaybillResultsDTO(Transportation transportation) {
        CourierWaybillResultsDTO dto = new CourierWaybillResultsDTO();
        dto.setWaybillId(transportation.getExternalWaybillId());
        dto.setTransportationId(transportation.getId());
        dto.setStatus("completed");
        dto.setCompletedAt(transportation.getCompletedAt());

        // Get all route orders with their statuses
        List<CourierRouteOrder> orders = courierRouteOrderRepository
            .findByTransportationId(transportation.getId());

        List<DeliveryResultDTO> deliveryResults = orders.stream()
            .map(this::mapToDeliveryResult)
            .collect(Collectors.toList());

        dto.setDeliveryResults(deliveryResults);

        // Get additional events (e.g., problematic addresses)
        List<AdditionalEventDTO> additionalEvents = getAdditionalEvents(transportation);
        dto.setAdditionalEvents(additionalEvents);

        return dto;
    }

    private DeliveryResultDTO mapToDeliveryResult(CourierRouteOrder order) {
        DeliveryResultDTO result = new DeliveryResultDTO();
        result.setTrackNumber(order.getTrackNumber());
        result.setExternalId(order.getExternalId());
        result.setStatus(order.getStatus().toString().toLowerCase());
        result.setStatusReason(order.getStatusReason());
        result.setDeliveryDatetime(order.getStatusDatetime());
        result.setPhotoUrl(getPhotoUrl(order.getPhotoId()));
        result.setCourierComment(order.getCourierComment());
        result.setSmsCodeUsed(order.getSmsCodeUsed());

        // Map positions
        if (order.getPositions() != null) {
            List<PositionDTO> positions = mapPositions(order.getPositions());
            result.setPositions(positions);
        }

        return result;
    }

    private List<AdditionalEventDTO> getAdditionalEvents(Transportation transportation) {
        // Implementation: get problematic addresses, previous_order_not_received events
        // ...
        return new ArrayList<>();
    }
}
```

### 3.2 DTO Classes

```java
@Data
public class CourierWaybillResultsDTO {
    private String waybillId;
    private Long transportationId;
    private String status;
    private Instant completedAt;
    private List<DeliveryResultDTO> deliveryResults;
    private List<AdditionalEventDTO> additionalEvents;
}

@Data
public class DeliveryResultDTO {
    private String trackNumber;
    private String externalId;
    private String status; // delivered, not_delivered, returned, partially_returned
    private String statusReason; // customer_not_available, customer_postponed, etc.
    private Instant deliveryDatetime;
    private String photoUrl;
    private String courierComment;
    private String smsCodeUsed;
    private List<PositionDTO> positions;
}

@Data
public class PositionDTO {
    private String code;
    private String name;
    private Integer qty;
    private Integer returnedQty;
}

@Data
public class AdditionalEventDTO {
    private String orderExternalId;
    private String eventType; // previous_order_not_received
    private Instant eventDatetime;
    private String comment;
}
```

### 3.3 Database Changes

**Изменения в таблице `transportation`:**
- Добавить поле `completed_at` (TIMESTAMP) - время завершения маршрута
- Добавить индекс на `(external_waybill_id, source_system)` для быстрого поиска

```sql
ALTER TABLE applications.transportation
ADD COLUMN completed_at TIMESTAMP;

CREATE INDEX idx_transportation_external_waybill
ON applications.transportation(external_waybill_id, source_system);
```

**Изменения в таблице `courier_route_order`:**
- Поля уже существуют (status, status_datetime, sms_code_used, photo_id, courier_comment)
- Проверить наличие поля `status_reason` (добавить если нет)

```sql
-- Если поле status_reason не существует
ALTER TABLE applications.courier_route_order
ADD COLUMN status_reason TEXT;
```

### 3.4 Логирование

Все webhook-вызовы логировать в таблицу `courier_integration_log`:

```java
private void logWebhookAccess(String externalWaybillId, String sourceSystem, boolean success, String errorMessage) {
    CourierIntegrationLog log = new CourierIntegrationLog();
    log.setDirection("INCOMING"); // TEEZ -> Coube
    log.setSourceSystem(sourceSystem);
    log.setHttpMethod("GET");
    log.setEndpoint("/api/v1/integration/courier/waybills/" + externalWaybillId + "/results");
    log.setStatus(success ? "SUCCESS" : "ERROR");
    log.setErrorMessage(errorMessage);
    log.setRequestDatetime(Instant.now());
    log.setResponseDatetime(Instant.now());

    courierIntegrationLogRepository.save(log);
}
```

---

## Опциональное уведомление (Webhook notification)

Если TEEZ хочет получать уведомления о готовности данных вместо polling:

### 4.1 Coube отправляет уведомление

**Когда**: При завершении маршрута курьером или логистом

**Куда**: На webhook URL, предоставленный TEEZ

**Реализация**:

```java
@Service
public class CourierWaybillNotificationService {

    @Autowired
    private RestTemplate restTemplate;

    @Autowired
    private CourierIntegrationLogRepository logRepository;

    @Value("${integration.teez.webhook.url}")
    private String teezWebhookUrl;

    @Value("${integration.teez.api-key}")
    private String teezApiKey;

    public void notifyWaybillCompleted(Transportation transportation) {
        if (!isTeezIntegration(transportation)) {
            return; // Skip if not TEEZ waybill
        }

        try {
            WaybillCompletedNotificationDTO notification = buildNotification(transportation);

            HttpHeaders headers = new HttpHeaders();
            headers.set("X-API-Key", teezApiKey);
            headers.setContentType(MediaType.APPLICATION_JSON);

            HttpEntity<WaybillCompletedNotificationDTO> request =
                new HttpEntity<>(notification, headers);

            ResponseEntity<String> response = restTemplate.postForEntity(
                teezWebhookUrl + "/waybill-completed",
                request,
                String.class
            );

            logWebhookNotification(transportation, true, null);
        } catch (Exception e) {
            logWebhookNotification(transportation, false, e.getMessage());
            // Don't throw - notification is optional, just log the error
        }
    }
}
```

**Конфигурация**:
```yaml
integration:
  teez:
    webhook:
      url: ${TEEZ_WEBHOOK_URL:https://api.teez.kz/webhooks}
      enabled: ${TEEZ_WEBHOOK_ENABLED:false}
    api-key: ${TEEZ_API_KEY}
```

**Retry**: Не делать retry для webhook-уведомлений. Если TEEZ не получил уведомление, они могут сделать polling.

---

## Security

### 5.1 API Key Authentication

Использовать существующий механизм API Key аутентификации из:
- `04-api-key-authentication-simplified.md`

**Проверка**:
```java
private void validateApiKey(String apiKey, String sourceSystem) {
    // Check if API key is valid for source system
    if (!apiKeyService.isValidApiKey(apiKey, sourceSystem)) {
        throw new UnauthorizedException("Invalid API key for system: " + sourceSystem);
    }
}
```

### 5.2 Rate Limiting

Добавить rate limiting на webhook endpoint:
- Max 60 requests per minute per API key
- Max 1000 requests per hour per API key

```java
@RateLimiter(name = "courierWebhook", fallbackMethod = "rateLimitFallback")
public CourierWaybillResultsDTO getWaybillResults(...) {
    // ...
}
```

---

## Testing

### 6.1 Unit Tests

```java
@Test
public void testGetWaybillResults_Success() {
    // Given
    String externalWaybillId = "WB-2025-001";
    String sourceSystem = "TEEZ_PVZ";

    Transportation transportation = createCompletedTransportation();
    when(transportationRepository.findByExternalWaybillIdAndSourceSystem(externalWaybillId, sourceSystem))
        .thenReturn(Optional.of(transportation));

    // When
    CourierWaybillResultsDTO results = service.getWaybillResults(externalWaybillId, sourceSystem);

    // Then
    assertNotNull(results);
    assertEquals(externalWaybillId, results.getWaybillId());
    assertEquals("completed", results.getStatus());
}

@Test
public void testGetWaybillResults_NotFound() {
    // Given
    String externalWaybillId = "WB-NOT-EXISTS";
    when(transportationRepository.findByExternalWaybillIdAndSourceSystem(...))
        .thenReturn(Optional.empty());

    // When/Then
    assertThrows(WaybillNotFoundException.class,
        () -> service.getWaybillResults(externalWaybillId, "TEEZ_PVZ"));
}

@Test
public void testGetWaybillResults_NotCompleted() {
    // Given
    Transportation transportation = createInProgressTransportation();
    when(transportationRepository.findByExternalWaybillIdAndSourceSystem(...))
        .thenReturn(Optional.of(transportation));

    // When/Then
    assertThrows(WaybillNotCompletedException.class,
        () -> service.getWaybillResults("WB-2025-001", "TEEZ_PVZ"));
}
```

### 6.2 Integration Tests

```bash
# Test webhook endpoint
curl -X GET "http://localhost:8080/api/v1/integration/courier/waybills/WB-2025-001/results?source_system=TEEZ_PVZ" \
  -H "X-API-Key: test-api-key-teez"

# Expected: 200 OK with results
# Or 404 if not found
# Or 409 if not completed
```

---

## Migration Plan

### 7.1 Этап 1: Реализация webhook endpoint (Week 1)

- [ ] Создать `CourierIntegrationWebhookController`
- [ ] Создать `CourierWaybillResultsService`
- [ ] Добавить DTO классы
- [ ] Добавить database migrations (completed_at, indexes)
- [ ] Написать unit tests
- [ ] Написать integration tests

### 7.2 Этап 2: Документация и координация с TEEZ (Week 1)

- [ ] Обновить `courier_delivery_flow_ascii.md`
- [ ] Обновить `03-api-examples.md`
- [ ] Создать Swagger/OpenAPI документацию
- [ ] Предоставить TEEZ:
  - Endpoint URL
  - API key
  - Примеры запросов/ответов
  - Описание error codes

### 7.3 Этап 3: Опциональный webhook notification (Week 2)

- [ ] Реализовать `CourierWaybillNotificationService`
- [ ] Добавить конфигурацию webhook URL
- [ ] Добавить логирование уведомлений
- [ ] Тестирование с TEEZ

### 7.4 Этап 4: Удаление старой логики (Week 2)

- [ ] Удалить асинхронную очередь отправки результатов
- [ ] Удалить `CourierResultsQueueService` (если существует)
- [ ] Удалить retry механизм для отправки в TEEZ
- [ ] Очистить неиспользуемые таблицы/поля

---

## Мониторинг

### 8.1 Метрики

Добавить метрики для webhook endpoint:

```java
@Timed(value = "courier.webhook.results.duration")
@Counted(value = "courier.webhook.results.total")
public CourierWaybillResultsDTO getWaybillResults(...) {
    // ...
}
```

**Метрики для отслеживания**:
- `courier.webhook.results.total` - всего запросов
- `courier.webhook.results.success` - успешных запросов
- `courier.webhook.results.not_found` - 404 errors
- `courier.webhook.results.not_completed` - 409 errors
- `courier.webhook.results.duration` - время обработки запроса

### 8.2 Alerts

Настроить алерты:
- Error rate > 5% за 5 минут
- Response time > 2s (p95)
- Rate limit triggered > 10 times per hour

---

## Open Questions

1. **Нужен ли webhook notification от Coube к TEEZ?**
   - Или TEEZ будет делать polling каждые N минут?
   - Если webhook - какой URL предоставит TEEZ?

2. **Как часто TEEZ будет запрашивать результаты?**
   - Сразу после завершения маршрута?
   - Периодический polling каждые 5-10 минут?

3. **Нужна ли пагинация для больших маршрутов?**
   - Если в маршруте 100+ заказов?

4. **Сколько хранить данные?**
   - 30 дней? 90 дней? Бессрочно?
   - Нужна ли архивация старых результатов?

5. **Нужен ли отдельный endpoint для получения статуса одного заказа?**
   - `GET /api/v1/integration/courier/orders/{trackNumber}/status`

---

## References

- `coube-documentation/business_analysis/converted/courier_delivery_flow_ascii.md:76-95`
- `coube-documentation/business_analysis/converted/Проект_системы_курьерская_доставка.md:551-650`
- `coube-documentation/tasks/backend/courier-delivery-integration-mvp/03-api-examples.md:588-657`
- Architecture DB: `applications.courier_route_order` table
- Architecture DB: `applications.courier_integration_log` table

---

**Дата создания**: 2025-10-16
**Автор**: Claude Code
**Версия**: 1.0
**Статус**: Draft - Requires Review
