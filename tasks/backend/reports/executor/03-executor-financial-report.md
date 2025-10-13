# Отчеты перевозчика - Финансовый отчет (оплаты от заказчика и МФО)

## Описание задачи
Реализовать API для отчета "Финансовый отчет" - отчет по поступлениям платежей от заказчиков и МФО (факторинговых компаний).

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `05-reports-financial-payment.md`, но с фокусом на поступления для перевозчика.

## Frontend UI референс
- Компонент: `ExecutorFinancialReport.vue`
- Фильтры: заказчик, источник платежа (Заказчик/МФО), статус, период
- Таблица: номер платежа, заказчик, рейс, сумма, дата, источник, статус
- Метрики: общая сумма поступлений, сумма от заказчиков, сумма от МФО
- Графики: график поступлений по месяцам, распределение по источникам

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/financial-payments`
Получение данных по финансовым поступлениям

**Параметры запроса:**
```json
{
  "paymentId": "string (optional)",
  "customerId": "number (optional)",
  "source": "string (optional)", // customer, mfo
  "status": "string (optional)", // received, processing, error
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "page": "number (default: 0)",
  "size": "number (default: 20)"
}
```

**Ответ:**
```json
{
  "data": [
    {
      "id": "number",
      "paymentNumber": "string",
      "customerName": "string",
      "routeNumber": "string",
      "amount": "number",
      "currency": "string",
      "paymentDate": "string",
      "source": "string", // customer, mfo
      "status": "string", // received, processing, error
      "mfoName": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalAmount": "number",
    "customerAmount": "number",
    "mfoAmount": "number",
    "receivedCount": "number",
    "processingCount": "number"
  }
}
```

### 2. GET `/api/reports/executor/financial-payments/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/financial-payments/summary`
Получение сводной финансовой статистики

**Параметры:**
```json
{
  "period": "string", // month, quarter, year
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "periods": [
    {
      "period": "2024-01",
      "totalAmount": "number",
      "customerAmount": "number",
      "mfoAmount": "number",
      "paymentCount": "number"
    }
  ],
  "totalBySource": {
    "customer": "number",
    "mfo": "number"
  }
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по платежам от заказчиков
SELECT
    'PAY-' || t.id::text as paymentNumber,
    o.organization_name as customerName,
    tc.transportation_number as routeNumber,
    tc.cost as amount,
    tc.cost_currency_code as currency,
    t.updated_at as paymentDate,
    'customer' as source,
    CASE
        WHEN tc.status = 'paid' THEN 'received'
        WHEN tc.status = 'pending' THEN 'processing'
        ELSE 'error'
    END as status,
    NULL as mfoName
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND t.status = 'completed'

UNION ALL

-- Запрос по выплатам от МФО
SELECT
    'MFO-' || pr.request_number::text as paymentNumber,
    o.organization_name as customerName,
    tc.transportation_number as routeNumber,
    pr.amount as amount,
    'KZT' as currency,
    pr.paid_at as paymentDate,
    'mfo' as source,
    pr.status as status,
    f.name as mfoName
FROM factoring.payout_request pr
    LEFT JOIN applications.transportation t ON pr.transportation_id = t.id
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
    LEFT JOIN factoring.factor f ON pr.organization_id = f.id
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND pr.status = 'paid'
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость и статус оплаты
- `factoring.payout_request` - запросы на выплаты от МФО
- `factoring.factor` - информация о МФО-партнерах
- `user.organization` - информация об организациях (заказчики)
- `factoring.factoring_agreement` - соглашения с МФО

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `FinancialPaymentReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с финансовыми эндпоинтами
3. Создать DTO для запроса и ответа
4. Реализовать объединение данных из разных источников (прямые платежи + МФО)
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для статистики
7. Добавить кэширование для сводной статистики (Redis)
8. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по поступлениям от заказчиков и МФО
- ✅ Данные агрегируются из разных источников корректно
- ✅ Статусы платежей отображаются правильно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика