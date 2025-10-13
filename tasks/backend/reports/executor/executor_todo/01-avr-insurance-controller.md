# Создать ExecutorReportsController для АВР и страховых полисов

## Описание задачи
Реализовать API для отчета "Выполненные перевозки (АВР, страховые полисы)" - отчет по выполненным перевозкам с актами выполненных работ и страховыми полисами.

## Frontend UI референс
- Компонент: `ExecutorAVRInsuranceReport.vue`
- Фильтры: номер перевозки, заказчик, статус документа, период
- Таблица: номер перевозки, заказчик, сумма, АВР (ссылка), страховой полис, премия, статус документа
- Метрики: общее количество перевозок, общая сумма, количество подписанных документов
- Графики: статусы документов, динамика выплат по месяцам

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/avr-insurance`
Получение данных по АВР и страховым полисам

**Параметры запроса:**
```json
{
  "routeNumber": "string (optional)",
  "customerId": "number (optional)",
  "documentStatus": "string (optional)", // signed, pending, rejected
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
      "routeNumber": "string",
      "customerName": "string",
      "amount": "number",
      "avrDocumentUrl": "string",
      "insurancePolicyNumber": "string",
      "insuranceDocumentUrl": "string",
      "bonusAmount": "number",
      "documentStatus": "string", // signed, pending, rejected
      "completedAt": "string"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalAmount": "number",
    "signedDocuments": "number",
    "pendingDocuments": "number"
  }
}
```

### 2. GET `/api/reports/executor/avr-insurance/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/avr-insurance/{routeId}/documents`
Получение документов для конкретной перевозки

**Ответ:**
```json
{
  "avrDocument": {
    "id": "number",
    "fileName": "string",
    "fileUrl": "string",
    "signedAt": "string"
  },
  "insuranceDocument": {
    "id": "number",
    "policyNumber": "string",
    "fileName": "string",
    "fileUrl": "string",
    "signedAt": "string"
  }
}
```

## Что нужно сделать

### 1. Создать контроллер
```java
@RestController
@RequestMapping("/api/reports/executor")
@PreAuthorize("hasRole('EXECUTOR') and @executorSecurity.canAccessExecutorData(authentication)")
public class ExecutorReportsController {

    private final ExecutorAVRInsuranceReportService avrInsuranceService;

    @GetMapping("/avr-insurance")
    public ResponseEntity<Page<AVRInsuranceReportDTO>> getAVRInsuranceReport(
        @RequestParam(required = false) String routeNumber,
        @RequestParam(required = false) Long customerId,
        @RequestParam(required = false) String documentStatus,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
        @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size
    ) {
        // Реализация
    }

    @GetMapping("/avr-insurance/export")
    public ResponseEntity<Resource> exportAVRInsuranceReport(
        // те же параметры
    ) {
        // Экспорт в Excel
    }

    @GetMapping("/avr-insurance/{routeId}/documents")
    public ResponseEntity<RouteDocumentsDTO> getRouteDocuments(@PathVariable Long routeId) {
        // Получение документов по рейсу
    }
}
```

### 2. Создать DTO классы
```java
public class AVRInsuranceReportDTO {
    private Long id;
    private String routeNumber;
    private String customerName;
    private BigDecimal amount;
    private String avrDocumentUrl;
    private String insurancePolicyNumber;
    private String insuranceDocumentUrl;
    private BigDecimal bonusAmount;
    private String documentStatus; // signed, pending, rejected
    private LocalDateTime completedAt;
}

public class RouteDocumentsDTO {
    private DocumentInfo avrDocument;
    private DocumentInfo insuranceDocument;
}

public class AVRInsuranceFilterDTO {
    private String routeNumber;
    private Long customerId;
    private String documentStatus;
    private LocalDate dateFrom;
    private LocalDate dateTo;
}
```

### 3. Создать сервис
```java
@Service
@Transactional(readOnly = true)
public class ExecutorAVRInsuranceReportService {

    public Page<AVRInsuranceReportDTO> getAVRInsuranceReport(
        Long executorId, AVRInsuranceFilterDTO filter, Pageable pageable
    ) {
        // Объединение данных из актов и страховых полисов
    }

    public byte[] exportToExcel(Long executorId, AVRInsuranceFilterDTO filter) {
        // Генерация Excel файла
    }

    public RouteDocumentsDTO getRouteDocuments(Long executorId, Long routeId) {
        // Получение документов с проверкой прав доступа
    }
}
```

### 4. SQL запрос
```sql
SELECT
    t.id,
    tc.transportation_number as routeNumber,
    o.organization_name as customerName,
    tc.cost as amount,
    a.act_number,
    a.file_id as avrFileId,
    a.file_name as avrFileName,
    a.status as avrStatus,
    a.signed_date as avrSignedDate,
    'POL-' || tc.transportation_number as insurancePolicyNumber,
    tc.status as documentStatus,
    t.updated_at as completedAt,
    tc.idle_payment as bonusAmount
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
    LEFT JOIN applications.acts a ON t.id = a.transportation_id
WHERE
    tc.executor_organization_id = :executorId
    AND t.status = 'completed'
ORDER BY t.updated_at DESC
```

### 5. Экспорт в Excel
- Использовать Apache POI для генерации Excel
- Включить все поля из таблицы
- Добавить фильтрацию и форматирование

## Требования
- ✅ Валидация параметров запроса
- ✅ Проверка прав доступа (только свои данные)
- ✅ Пагинация через Spring Data
- ✅ Кэширование для часто запрашиваемых данных
- ✅ Обработка ошибок и валидные HTTP статусы

## Критерии приемки
- [ ] Контроллер возвращает корректные данные по АВР и полисам
- [ ] Фильтрация работает корректно
- [ ] Экспорт в Excel работает
- [ ] Права доступа проверяются
- [ ] Нагрузочное тестирование показывает производительность