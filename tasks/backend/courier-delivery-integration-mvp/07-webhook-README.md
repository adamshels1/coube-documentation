# Webhook для получения результатов доставки - Краткое резюме

## Суть изменения

**Было** (Push-модель):
```
Coube → POST результаты → TEEZ_PVZ
         (асинхронно)
```

**Стало** (Pull-модель):
```
Coube ← GET результаты ← TEEZ_PVZ
         (по запросу)
```

---

## Почему меняем?

### Проблемы старого подхода:
1. ❌ Coube должен знать endpoint TEEZ API
2. ❌ Нужна сложная асинхронная очередь с retry
3. ❌ Сложная обработка ошибок при недоступности TEEZ
4. ❌ TEEZ не контролирует момент получения данных
5. ❌ Высокий coupling между системами

### Преимущества нового подхода:
1. ✅ TEEZ контролирует момент получения данных
2. ✅ Упрощается логика на стороне Coube (нет очередей, нет retry)
3. ✅ TEEZ сам управляет retry-логикой
4. ✅ Снижается coupling между системами
5. ✅ Проще масштабировать и поддерживать

---

## Что нужно сделать?

### 1. Новый Webhook Endpoint

**Endpoint**: `GET /api/v1/integration/courier/waybills/{externalWaybillId}/results`

**Параметры**:
- `externalWaybillId` (path) - ID маршрутного листа в TEEZ
- `source_system` (query) - default: `TEEZ_PVZ`

**Аутентификация**: `X-API-Key` header

**Пример запроса**:
```bash
GET /api/v1/integration/courier/waybills/WB-2025-001/results?source_system=TEEZ_PVZ
X-API-Key: {teez-api-key}
```

**Пример ответа** (200 OK):
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
      "delivery_datetime": "2025-01-07T10:15:00Z",
      "photo_url": "https://s3.coube.kz/courier/photos/123456.jpg",
      "sms_code_used": "1234",
      "positions": [...]
    }
  ],
  "additional_events": [...]
}
```

**Error коды**:
- `404 Not Found` - маршрутный лист не найден
- `409 Conflict` - маршрут еще не завершен
- `401 Unauthorized` - неверный API key

---

### 2. Опционально: Webhook уведомление

Если TEEZ хочет получать уведомления вместо polling:

**Coube отправляет**: `POST {teez_webhook_url}/waybill-completed`

```json
{
  "external_waybill_id": "WB-2025-001",
  "transportation_id": 12345,
  "completed_at": "2025-01-07T16:00:00Z",
  "results_available": true,
  "results_url": "https://api.coube.kz/api/v1/integration/courier/waybills/WB-2025-001/results"
}
```

---

## Backend реализация

### Компоненты:

1. **Controller**: `CourierIntegrationWebhookController`
   - GET `/api/v1/integration/courier/waybills/{id}/results`

2. **Service**: `CourierWaybillResultsService`
   - `getWaybillResults(externalWaybillId, sourceSystem)`
   - Проверка статуса завершения
   - Сборка результатов доставки

3. **DTOs**:
   - `CourierWaybillResultsDTO`
   - `DeliveryResultDTO`
   - `PositionDTO`
   - `AdditionalEventDTO`

4. **Database changes**:
   - Добавить `completed_at` в таблицу `transportation`
   - Добавить индекс на `(external_waybill_id, source_system)`
   - Проверить наличие `status_reason` в `courier_route_order`

---

## Файлы для обновления

### Документация:
1. ✏️ `courier_delivery_flow_ascii.md` (строки 76-82)
   - Обновить диаграмму flow
2. ✏️ `03-api-examples.md` (раздел 10)
   - Удалить "Отправка результатов в TEEZ"
   - Добавить "Получение результатов через webhook"
3. ✏️ `01-mvp-plan.md` и `02-implementation-checklist.md`
   - Обновить секции про асинхронную очередь

### Код для удаления:
- ❌ Асинхронная очередь отправки результатов
- ❌ `CourierResultsQueueService` (если существует)
- ❌ Retry механизм для отправки в TEEZ
- ❌ Pub/Sub таблицы для очереди (если были созданы)

---

## Migration Plan

### Этап 1 (Week 1): Реализация webhook
- [ ] Создать Controller, Service, DTOs
- [ ] Database migrations
- [ ] Unit tests + Integration tests

### Этап 2 (Week 1): Документация
- [ ] Обновить документацию
- [ ] Создать Swagger/OpenAPI docs
- [ ] Координация с TEEZ (endpoint URL, API key)

### Этап 3 (Week 2): Опциональный webhook notification
- [ ] Реализовать `CourierWaybillNotificationService`
- [ ] Тестирование с TEEZ

### Этап 4 (Week 2): Cleanup
- [ ] Удалить старую логику отправки
- [ ] Cleanup неиспользуемых таблиц/полей

---

## Security & Monitoring

### Security:
- ✅ API Key authentication (X-API-Key header)
- ✅ Rate limiting (60 req/min, 1000 req/hour)
- ✅ Логирование всех webhook вызовов в `courier_integration_log`

### Monitoring:
- `courier.webhook.results.total` - всего запросов
- `courier.webhook.results.success` - успешных
- `courier.webhook.results.not_found` - 404 errors
- `courier.webhook.results.not_completed` - 409 errors
- `courier.webhook.results.duration` - время обработки

### Alerts:
- Error rate > 5% за 5 минут
- Response time > 2s (p95)
- Rate limit triggered > 10 times/hour

---

## Open Questions для TEEZ

1. ❓ Нужен ли webhook notification от Coube?
   - Или TEEZ будет делать polling каждые N минут?

2. ❓ Как часто TEEZ будет запрашивать результаты?
   - Сразу после завершения?
   - Периодический polling?

3. ❓ Нужна ли пагинация для больших маршрутов?
   - Если в маршруте 100+ заказов?

4. ❓ Сколько хранить данные результатов?
   - 30 дней? 90 дней? Бессрочно?

5. ❓ Нужен ли endpoint для получения статуса одного заказа?
   - `GET /api/v1/integration/courier/orders/{trackNumber}/status`

---

## Ссылки

- **Подробная документация**: `07-webhook-results-endpoint.md`
- **Текущий flow**: `courier_delivery_flow_ascii.md:76-95`
- **API примеры**: `03-api-examples.md:588-657`
- **БД**: таблицы `courier_route_order`, `courier_integration_log`

---

**Дата создания**: 2025-10-16
**Статус**: Draft - Requires Review
