# Создать структуру для споров и претензий [Фьючерс]

## Описание задачи
Реализовать API для отчета "Споры и претензии" - отчет по спорам и претензиям от заказчиков.

**Важно:** Отчет будет активным при подключении платежной системы позже. Пока в разработке оставить.

## Frontend UI референс
- Компонент: `ExecutorDisputesReport.vue`
- Фильтры: номер спора, заказчик, статус, результат, период
- Таблица: номер спора, заказчик, сумма, статус, результат, комментарии
- Метрики: общее количество споров, сумма претензий, решенные споры, среднее время решения
- Графики: Канбан доска (Новый → В рассмотрении → Решен), динамика споров

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/disputes-claims`
Получение данных по спорам и претензиям

**Параметры запроса:**
```json
{
  "disputeId": "string (optional)",
  "customerId": "number (optional)",
  "status": "string (optional)", // new, under_review, resolved
  "result": "string (optional)",
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
      "disputeNumber": "string",
      "customerName": "string",
      "routeNumber": "string",
      "claimAmount": "number",
      "currency": "string",
      "status": "string", // new, under_review, resolved
      "result": "string",
      "description": "string",
      "createdAt": "string",
      "resolvedAt": "string",
      "resolutionDays": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalDisputes": "number",
    "totalClaimAmount": "number",
    "resolvedDisputes": "number",
    "underReviewDisputes": "number",
    "averageResolutionDays": "number"
  }
}
```

### 2. GET `/api/reports/executor/disputes-claims/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/disputes-claims/kanban`
Получение данных для Канбан доски

**Ответ:**
```json
{
  "columns": [
    {
      "status": "new",
      "title": "Новые",
      "items": [
        {
          "id": "number",
          "disputeNumber": "string",
          "customerName": "string",
          "claimAmount": "number",
          "createdAt": "string"
        }
      ]
    },
    {
      "status": "under_review",
      "title": "В рассмотрении",
      "items": [...]
    },
    {
      "status": "resolved",
      "title": "Решенные",
      "items": [...]
    }
  ]
}
```

## Что нужно сделать

### 1. Создать таблицы БД (Flyway миграция)
```sql
-- Таблица споров
CREATE TABLE claims.disputes (
    id BIGSERIAL PRIMARY KEY,
    dispute_number VARCHAR(50) UNIQUE NOT NULL,
    transportation_id BIGINT NOT NULL,
    customer_organization_id BIGINT NOT NULL,
    executor_organization_id BIGINT NOT NULL,
    claim_amount NUMERIC(15,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'KZT',
    status VARCHAR(20) NOT NULL DEFAULT 'new', -- new, under_review, resolved, rejected
    description TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    updated_by VARCHAR(255),

    FOREIGN KEY (transportation_id) REFERENCES applications.transportation(id),
    FOREIGN KEY (customer_organization_id) REFERENCES user.organization(id),
    FOREIGN KEY (executor_organization_id) REFERENCES user.organization(id)
);

-- Таблица документов по спорам
CREATE TABLE claims.dispute_documents (
    id BIGSERIAL PRIMARY KEY,
    dispute_id BIGINT NOT NULL,
    file_id UUID NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) NOT NULL, -- claim, evidence, resolution
    uploaded_by BIGINT NOT NULL,
    uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (dispute_id) REFERENCES claims.disputes(id) ON DELETE CASCADE,
    FOREIGN KEY (file_id) REFERENCES file.file_meta_info(id),
    FOREIGN KEY (uploaded_by) REFERENCES user.employee(id)
);

-- Таблица истории рассмотрения споров
CREATE TABLE claims.resolution_history (
    id BIGSERIAL PRIMARY KEY,
    dispute_id BIGINT NOT NULL,
    status_from VARCHAR(20),
    status_to VARCHAR(20) NOT NULL,
    comment TEXT,
    resolved_by BIGINT,
    resolved_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (dispute_id) REFERENCES claims.disputes(id) ON DELETE CASCADE,
    FOREIGN KEY (resolved_by) REFERENCES user.employee(id)
);

-- Индексы
CREATE INDEX idx_disputes_executor_org ON claims.disputes(executor_organization_id);
CREATE INDEX idx_disputes_status ON claims.disputes(status);
CREATE INDEX idx_disputes_created_at ON claims.disputes(created_at);
CREATE INDEX idx_dispute_documents_dispute_id ON claims.dispute_documents(dispute_id);
```

### 2. Создать Entity классы
```java
@Entity
@Table(name = "disputes", schema = "claims")
public class Dispute {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String disputeNumber;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "transportation_id")
    private Transportation transportation;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "customer_organization_id")
    private Organization customerOrganization;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "executor_organization_id")
    private Organization executorOrganization;

    @Column(nullable = false, precision = 15, scale = 2)
    private BigDecimal claimAmount;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private DisputeStatus status;

    @Column(columnDefinition = "TEXT")
    private String description;

    // getters, setters, equals, hashCode
}

public enum DisputeStatus {
    NEW("new"),
    UNDER_REVIEW("under_review"),
    RESOLVED("resolved"),
    REJECTED("rejected");
}
```

### 3. Создать Repository
```java
@Repository
public interface DisputeRepository extends JpaRepository<Dispute, Long> {

    Page<Dispute> findByExecutorOrganizationIdAndStatusContaining(
        Long executorOrganizationId, String status, Pageable pageable
    );

    Page<Dispute> findByExecutorOrganizationIdAndCustomerOrganizationIdAndStatusContaining(
        Long executorOrganizationId, Long customerOrganizationId,
        String status, Pageable pageable
    );

    @Query("SELECT d FROM Dispute d WHERE d.executorOrganizationId = :executorId " +
           "AND (:status IS NULL OR d.status = :status) " +
           "AND (:dateFrom IS NULL OR d.createdAt >= :dateFrom) " +
           "AND (:dateTo IS NULL OR d.createdAt <= :dateTo)")
    Page<Dispute> findDisputesWithFilters(
        @Param("executorId") Long executorId,
        @Param("status") DisputeStatus status,
        @Param("dateFrom") LocalDateTime dateFrom,
        @Param("dateTo") LocalDateTime dateTo,
        Pageable pageable
    );
}
```

### 4. Создать DTO классы
```java
public class DisputeReportDTO {
    private Long id;
    private String disputeNumber;
    private String customerName;
    private String routeNumber;
    private BigDecimal claimAmount;
    private String currency;
    private DisputeStatus status;
    private String result;
    private String description;
    private LocalDateTime createdAt;
    private LocalDateTime resolvedAt;
    private Long resolutionDays;
}

public class DisputeKanbanColumnDTO {
    private String status;
    private String title;
    private List<DisputeKanbanItemDTO> items;
}

public class DisputeSummaryDTO {
    private Long totalDisputes;
    private BigDecimal totalClaimAmount;
    private Long resolvedDisputes;
    private Long underReviewDisputes;
    private Double averageResolutionDays;
}
```

### 5. Создать сервис с моковыми данными
```java
@Service
@Transactional(readOnly = true)
public class ExecutorDisputesReportService {

    private final DisputeRepository disputeRepository;

    public Page<DisputeReportDTO> getDisputesReport(
        Long executorId, DisputeFilterDTO filter, Pageable pageable
    ) {
        // Пока используем моковые данные на основе существующих перевозок
        return generateMockDisputes(executorId, filter, pageable);
    }

    private Page<DisputeReportDTO> generateMockDisputes(
        Long executorId, DisputeFilterDTO filter, Pageable pageable
    ) {
        // Генерация моковых данных на основе перевозок со статусами
        // Новые: транспорт completed, но cost не paid
        // В рассмотрении: transport completed, cost = paid, но с опозданием
        // Решенные: все успешно завершенные
    }

    public List<DisputeKanbanColumnDTO> getKanbanData(Long executorId) {
        // Формирование Kanban доски
        return Arrays.asList(
            createKanbanColumn(DisputeStatus.NEW, "Новые"),
            createKanbanColumn(DisputeStatus.UNDER_REVIEW, "В рассмотрении"),
            createKanbanColumn(DisputeStatus.RESOLVED, "Решенные")
        );
    }
}
```

### 6. Добавить в контроллер
```java
@GetMapping("/disputes-claims")
public ResponseEntity<Page<DisputeReportDTO>> getDisputesClaims(
    @RequestParam(required = false) String disputeId,
    @RequestParam(required = false) Long customerId,
    @RequestParam(required = false) DisputeStatus status,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size
) {
    // Реализация с моковыми данными
}

@GetMapping("/disputes-claims/kanban")
public ResponseEntity<List<DisputeKanbanColumnDTO>> getKanbanBoard() {
    // Kanban доска для управления спорами
}
```

### 7. Моковый SQL запрос (для генерации данных)
```sql
-- Генерация моковых споров на основе существующих перевозок
SELECT
    'DISP-' || t.id::text || '-' ROW_NUMBER() OVER (ORDER BY t.created_at DESC) as disputeNumber,
    o.organization_name as customerName,
    tc.transportation_number as routeNumber,
    tc.cost as claimAmount,
    'KZT' as currency,
    CASE
        WHEN t.status = 'completed' AND tc.status = 'paid' THEN 'resolved'
        WHEN t.status = 'completed' AND tc.status != 'paid' THEN 'under_review'
        ELSE 'new'
    END as status,
    CASE
        WHEN tc.status = 'paid' THEN 'Выплачено'
        ELSE 'В обработке'
    END as result,
    'Претензия по рейсу ' || tc.transportation_number as description,
    t.created_at,
    t.updated_at as resolvedAt,
    EXTRACT(DAYS FROM (t.updated_at - t.created_at)) as resolutionDays
FROM applications.transportation t
    LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    LEFT JOIN user.organization o ON t.organization_id = o.id
WHERE
    tc.executor_organization_id = :executorId
    AND t.status = 'completed'
ORDER BY t.created_at DESC
```

## Требования
- ✅ Структура БД готова для будущей интеграции
- ✅ Моковые данные генерируются на основе реальных перевозок
- ✅ Kanban доска для управления спорами
- ✅ Валидация статусов и переходов
- ✅ Готовность к интеграции с платежной системой

## Критерии приемки
- [ ] Таблицы БД созданы и работают
- [ ] Моковые данные генерируются корректно
- [ ] API возвращает структуру данных для будущей системы
- [ ] Kanban доска отображается правильно
- [ ] Фильтры работают с моковыми данными
- [ ] Архитектура готова к реальной интеграции

## Заметки для будущей разработки
- При интеграции с платежной системой заменить моки на реальные данные
- Добавить систему документооборота для споров
- Создать автоматическую эскалацию споров
- Интегрировать с юридическими сервисами