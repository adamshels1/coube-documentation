# Отчеты перевозчика - Дебиторка заказчиков [Фьючерс]

## Описание задачи
Реализовать API для отчета "Дебиторка заказчиков" - отчет по задолженностям заказчиков и просроченным платежам.

**Важно:** Отчет будет активным при подключении платежной системы позже. Пока в разработке оставить.

**Перекрытие с отчетами заказчика:** Используется аналогичная логика как в `06-reports-debtor-analysis.md`, но с фокусом на дебиторскую задолженность для перевозчика.

## Frontend UI референс
- Компонент: `ExecutorDebtorReport.vue`
- Фильтры: заказчик, статус задолженности, период просрочки
- Таблица: заказчик, рейс, сумма долга, срок оплаты, дата погашения, просрочка (дни), статус
- Метрики: общая сумма дебиторки, просроченная сумма, количество должников
- Графики: диаграмма (оплачено/в срок/просрочено), динамика задолженности

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/debtor-analysis`
Получение данных по дебиторской задолженности

**Параметры запроса:**
```json
{
  "customerId": "number (optional)",
  "debtStatus": "string (optional)", // on_time, overdue
  "overdueDays": "number (optional)", // минимальное количество дней просрочки
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
      "customerName": "string",
      "routeNumber": "string",
      "debtAmount": "number",
      "currency": "string",
      "dueDate": "string",
      "paymentDate": "string",
      "overdueDays": "number",
      "status": "string", // on_time, overdue
      "contactInfo": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDebt": "number",
    "overdueDebt": "number",
    "onTimeDebt": "number",
    "debtorsCount": "number",
    "averageOverdueDays": "number"
  }
}
```

### 2. GET `/api/reports/executor/debtor-analysis/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/debtor-analysis/customers`
Получение списка должников с агрегированной информацией

**Ответ:**
```json
{
  "customers": [
    {
      "customerId": "number",
      "customerName": "string",
      "totalDebt": "number",
      "overdueDebt": "number",
      "debtCount": "number",
      "averageOverdueDays": "number",
      "lastPaymentDate": "string",
      "contactInfo": "string"
    }
  ]
}
```

## SQL запросы (базовая логика)

```sql
-- Основной запрос по дебиторской задолженности
SELECT
    o.organization_name as customerName,
    tc.transportation_number as routeNumber,
    tc.cost as debtAmount,
    tc.cost_currency_code as currency,
    -- Срок оплаты (с учетом задержки оплаты)
    (t.created_at + INTERVAL '1 day' * COALESCE(tc.payment_delay, 30)) as dueDate,
    -- Фактическая дата оплаты (если есть)
    tc.updated_at as paymentDate,
    -- Расчет просроченных дней
    CASE
        WHEN tc.status != 'paid' THEN
            GREATEST(0, EXTRACT(DAYS FROM CURRENT_DATE - (t.created_at + INTERVAL '1 day' * COALESCE(tc.payment_delay, 30))))
        ELSE 0
    END as overdueDays,
    -- Статус задолженности
    CASE
        WHEN tc.status = 'paid' THEN 'on_time'
        WHEN CURRENT_DATE > (t.created_at + INTERVAL '1 day' * COALESCE(tc.payment_delay, 30)) THEN 'overdue'
        ELSE 'on_time'
    END as status,
    -- Контактная информация (из профиля организации)
    ops.accounting_documents_email as contactInfo
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
    LEFT JOIN user.organization_profile_settings ops ON o.id = ops.organization_id
WHERE
    tc.executor_organization_id = $executorOrganizationId
    AND t.status = 'completed'
    AND tc.status != 'paid' -- Только неоплаченные
    AND ($customerId IS NULL OR t.organization_id = $customerId)
    AND ($debtStatus IS NULL OR
         CASE
             WHEN CURRENT_DATE > (t.created_at + INTERVAL '1 day' * COALESCE(tc.payment_delay, 30)) THEN 'overdue'
             ELSE 'on_time'
         END = $debtStatus)
    AND ($overdueDays IS NULL OR
         GREATEST(0, EXTRACT(DAYS FROM CURRENT_DATE - (t.created_at + INTERVAL '1 day' * COALESCE(tc.payment_delay, 30)))) >= $overdueDays)
ORDER BY overdueDays DESC, dueDate ASC
```

## Основные таблицы БД
- `applications.transportation` - основная информация о перевозках
- `applications.transportation_cost` - стоимость, статус оплаты, задержка платежа
- `user.organization` - информация об организациях (заказчики)
- `user.organization_profile_settings` - контактная информация организаций
- `applications.invoices` - информация по инвойсам (для интеграции с платежной системой)

## Техническая реализация
1. **Переиспользование:** Адаптировать существующий `DebtorAnalysisReportService` для перевозчика
2. Создать контроллер `ExecutorReportsController` с эндпоинтами по дебиторке
3. Создать DTO для запроса и ответа
4. Реализовать расчет просроченных дней и статусов
5. Добавить экспорт в Excel через Apache POI
6. Реализовать агрегацию данных по должникам
7. Добавить кэширование для сводной статистики (Redis)
8. **Будущая интеграция:** Подготовить структуру для интеграции с платежной системой
9. Обеспечить доступ только для авторизованных пользователей организации-перевозчика

## Критерии приемки
- ✅ API возвращает корректные данные по дебиторской задолженности
- ✅ Расчет просроченных дней работает правильно
- ✅ Статусы задолженности определяются корректно
- ✅ Экспорт в Excel содержит все поля из таблицы
- ✅ Агрегация по заказчикам работает корректно
- ✅ Пагинация работает корректно
- ✅ API работает только для авторизованных пользователей организации-перевозчика
- ✅ Структура готова для будущей интеграции с платежной системой

## Заметки для будущей разработки
- При подключении платежной системы добавить интеграцию с реальными данными о платежах
- Добавить автоматические уведомления о приближающихся сроках оплаты
- Реализовать экспорт отчетов для коллекторских агентств
- Добавить функционал расчета пеней и неустоек