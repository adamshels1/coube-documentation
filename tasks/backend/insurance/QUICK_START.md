# Quick Start - Интеграция страхования

## TL;DR
Реализуем интеграцию с УСК Евразия для автоматического страхования грузов при создании заявки.

## Основная идея
- Заказчик создает заявку → включает свич "Со страхованием"
- Проверяем клиента через API страховой (ПОД/ФТ)
- Генерируем документы → клиент подписывает ЭЦП
- Создаем договор в 1С страховой → получаем подписанный договор

## Архитектура

```
Transportation (with_insurance: true)
         ↓
   InsurancePolicy (status: pending)
         ↓
   CheckClient API (ПОД/ФТ проверка)
         ↓
   Generate Documents (PDF)
         ↓
   Client Signs (ЭЦП)
         ↓
   CreateNewDocument API (1С)
         ↓
   SavePicture API (загрузка документов)
         ↓
   Receive Signed Contract
         ↓
   InsurancePolicy (status: active)
```

## Основные компоненты

### 1. База данных (4 таблицы)
- `insurance_policies` - полисы
- `insurance_client_checks` - проверки
- `insurance_documents` - документы
- `insurance_api_logs` - логи

### 2. API клиент
```java
@Service
class InsuranceApiClient {
    CheckClientResponse checkClient(request)
    CreateDocumentResponse createNewDocument(request)
    SavePictureResponse savePicture(request)
}
```

### 3. Бизнес-логика
```java
@Service
class InsuranceService {
    createInsurancePolicy(transportationId)
    checkClientForInsurance(policyId)
    signInsuranceDocuments(policyId, signature)
    createInsuranceContract(policyId)
    receiveSignedContract(contractNumber, pdf)
}
```

### 4. REST API
```
POST   /api/insurance/check-client/{transportationId}
GET    /api/insurance/documents/preview/{insurancePolicyId}
POST   /api/insurance/sign/{insurancePolicyId}
POST   /api/insurance/create-contract/{insurancePolicyId}
GET    /api/insurance/status/{insurancePolicyId}
POST   /api/insurance/cancel/{insurancePolicyId}
```

## Последовательность разработки

1. **День 1-2**: БД + миграции → [01-database-schema.md](./01-database-schema.md)
2. **День 3-4**: API клиент → [02-api-integration.md](./02-api-integration.md)
3. **День 5-7**: Бизнес-логика → [03-business-logic.md](./03-business-logic.md)
4. **День 8-9**: Генерация документов → [05-document-generation.md](./05-document-generation.md)
5. **День 10**: REST API → [04-rest-api-endpoints.md](./04-rest-api-endpoints.md)
6. **День 11-12**: Тестирование → [06-integration-testing.md](./06-integration-testing.md)

## Важные моменты

### ✅ Делаем просто
- Синхронный флоу без сложных state machine
- Промежуточный статус `INSURANCE_PENDING` для заявки
- Если проверка не прошла → заявка БЕЗ страхования

### ⚠️ Не забыть
- Логирование всех API запросов в `insurance_api_logs`
- Retry логика для сетевых ошибок (3 попытки)
- Валидация ЭЦП перед отправкой
- Уведомления клиенту на каждом этапе

### 🔒 Безопасность
- Все endpoints требуют аутентификации
- Проверка прав доступа к заявке
- SSL для всех запросов к страховой
- Rate limiting для API

## Быстрая проверка работы

### 1. Создать заявку со страхованием
```bash
curl -X POST http://localhost:8080/api/transportations \
  -H "Content-Type: application/json" \
  -d '{"withInsurance": true, "cargoName": "Мебель", ...}'
```

### 2. Проверить клиента
```bash
curl -X POST http://localhost:8080/api/insurance/check-client/123
```

### 3. Получить статус
```bash
curl http://localhost:8080/api/insurance/status/456
```

## Конфигурация

### application.yml
```yaml
insurance:
  api:
    url: https://ws.theeurasia.kz/ws/wsNovelty.1cws
    timeout: 30000
    retry:
      max-attempts: 3
      backoff: 2000
```

## Мониторинг

### Метрики
- `insurance.policy.created` - счетчик созданных полисов
- `insurance.check.duration` - время проверки клиента
- `insurance.check.total` - счетчик проверок (по результатам)
- `insurance.check.errors` - ошибки проверок

### Алерты
- Проверка клиента > 30 сек
- API страховой недоступен
- Ошибки при создании договора

## Troubleshooting

### Проблема: Проверка клиента всегда fails
**Решение**: Проверить формат ИИН/БИН, убедиться что API доступен

### Проблема: Документы не генерируются
**Решение**: Проверить наличие данных в transportation и cargo_loading

### Проблема: API страховой возвращает ошибку
**Решение**: Проверить логи в `insurance_api_logs`, проверить credentials

## Полезные SQL запросы

### Статистика по страхованию
```sql
SELECT
    status,
    COUNT(*)
FROM applications.insurance_policies
GROUP BY status;
```

### Последние проверки клиентов
```sql
SELECT *
FROM applications.insurance_client_checks
ORDER BY checked_at DESC
LIMIT 10;
```

### Логи API за последний час
```sql
SELECT *
FROM applications.insurance_api_logs
WHERE created_at > NOW() - INTERVAL '1 hour'
ORDER BY created_at DESC;
```

## Ссылки
- 📄 [README.md](./README.md) - полный обзор
- 🗄️ [01-database-schema.md](./01-database-schema.md) - схема БД
- 🔌 [02-api-integration.md](./02-api-integration.md) - API клиент
- ⚙️ [03-business-logic.md](./03-business-logic.md) - бизнес-логика
- 🌐 [04-rest-api-endpoints.md](./04-rest-api-endpoints.md) - REST API
- 📝 [05-document-generation.md](./05-document-generation.md) - генерация документов
- 🧪 [06-integration-testing.md](./06-integration-testing.md) - тестирование
