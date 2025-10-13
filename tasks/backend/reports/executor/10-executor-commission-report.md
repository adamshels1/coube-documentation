# Отчеты перевозчика - Подписки / комиссии платформы

## Описание задачи
Реализовать API для отчета "Подписки / комиссии платформы" - отчет по комиссиям и подпискам, уплаченным перевозчиком за использование платформы.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `07-reports-platform-commission.md`, но с фокусом на комиссии перевозчика.

## Frontend UI референс
- Компонент: `ExecutorCommissionReport.vue`
- Фильтры: тип операции, тип подписки, период
- Таблица: дата, операция, сумма (₸), тип подписки
- Метрики: общая сумма комиссий, количество операций, средняя комиссия
- Графики: график сумм комиссий по месяцам, распределение по типам операций

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/platform-commissions`
Получение данных по комиссиям платформы

**Параметры запроса:**
```json
{
  "operationType": "string (optional)", // transaction, subscription, penalty
  "subscriptionType": "string (optional)",
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
      "operationDate": "string",
      "operationType": "string", // transaction, subscription, penalty
      "description": "string",
      "amount": "number",
      "currency": "string",
      "subscriptionType": "string",
      "transactionId": "string",
      "status": "string" // paid, pending, failed
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalAmount": "number",
    "totalTransactions": "number",
    "paidAmount": "number",
    "pendingAmount": "number",
    "averageCommission": "number"
  }
}
```

### 2. GET `/api/reports/executor/platform-commissions/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel file

### 3. GET `/api/reports/executor/platform-commissions/subscription-info`
Получение информации о текущей подписке

**Ответ:**
```json
{
  "currentSubscription": {
    "type": "string",
    "name": "string",
    "monthlyFee": "number",
    "transactionFee": "number",
    "startDate": "string",
    "endDate": "string",
    "status": "string", // active, expired, cancelled
    "features": ["string"]
  },
  "usageStats": {
    "transactionsThisMonth": "number",
    "commissionPaidThisMonth": "number",
    "estimatedNextMonth": "number"
  }
}
```

## SQL запросы (базовая логика)

```sql
-- Запрос по комиссиям (placeholder - структура для будущей реализации)
WITH mock_commissions AS (
    -- Транзакционные комиссии
    SELECT
        t.updated_at as operationDate,
        'transaction' as operationType,
        'Комиссия за транзакцию ' || tc.transportation_number as description,
        -- Комиссия 2% от стоимости (заглушка)
        tc.cost * 0.02 as amount,
        tc.cost_currency_code as currency,
        'Процентная' as subscriptionType,
        'TRANS-' || tc.transportation_number as transactionId,
        CASE
            WHEN tc.status = 'paid' THEN 'paid'
            ELSE 'pending'
        END as status
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND t.status = 'completed'

    UNION ALL

    -- Ежемесячные подписки (mock данные)
    SELECT
        DATE_TRUNC('month', CURRENT_DATE) as operationDate,
        'subscription' as operationType,
        'Ежемесячная подписка на платформу' as description,
        50000 as amount, -- 50,000 ₸ в месяц
        'KZT' as currency,
        'Бизнес' as subscriptionType,
        'SUB-' || EXTRACT(YEAR FROM CURRENT_DATE) || '-' || EXTRACT(MONTH FROM CURRENT_DATE) as transactionId,
        'paid' as status
    WHERE
        DATE_TRUNC('month', CURRENT_DATE) <= CURRENT_DATE

    UNION ALL

    -- Штрафы (mock данные)
    SELECT
        t.updated_at as operationDate,
        'penalty' as operationType,
        'Штраф за нарушение сроков доставки' as description,
        tc.cost * 0.05 as amount, -- 5% шлюз
        tc.cost_currency_code as currency,
        'Штраф' as subscriptionType,
        'PEN-' || tc.transportation_number as transactionId,
        'paid' as status
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE
        tc.executor_organization_id = $executorOrganizationId
        AND t.status = 'completed'
        AND EXTRACT(HOURS FROM (t.updated_at - t.created_at)) > 48 -- Опоздание более 48 часов
        AND ROW_NUMBER() OVER (PARTITION BY tc.transportation_number ORDER BY t.updated_at DESC) = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY operationDate DESC) as id,
    mc.*
FROM mock_commissions mc
WHERE
    ($operationType IS NULL OR mc.operationType = $operationType)
    AND ($subscriptionType IS NULL OR mc.subscriptionType = $subscriptionType)
    AND ($dateFrom IS NULL OR mc.operationDate >= $dateFrom)
    AND ($dateTo IS NULL OR mc.operationDate <= $dateTo)
ORDER BY mc.operationDate DESC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость для расчета комиссий
- **Будущие таблицы (для будущей реализации):**
  - `billing.subscriptions` - информация о подписках
  - `billing.commission_transactions` - транзакции комиссий
  - `billing.subscription_plans` - тарифные планы
  - `billing.invoice_commissions` - инвойсы по комиссиям

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `PlatformCommissionReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по комиссиям
3. Создать DTO для запроса и ответа
4. Реализовать базовую логику расчета комиссий (как заглушку)
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных для статистики
7. Добавить кэширование для расчетных данных (Redis)
8. **Будущая интеграция:** Подготовить структуру для полноценной биллинговой системы
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректную структуру данных по комиссиям
- ✅ Расчет комиссий работает на основе заглушек
- ✅ Фильтрация по типам операций работает корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Графики и статистика рассчитываются правильно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Структура готова для будущей интеграции с биллинговой системой

## Заметки для будущей разработки
- Создать полноценную биллинговую систему с различными тарифами
- Добавить автоматическое списание комиссий
- Реализовать систему уведомлений о предстоящих платежах
- Добавить analytics по эффективности использования платформы
- Создать систему промокодов и скидок
- Интеграция с платежными системами для автоматического оплаты