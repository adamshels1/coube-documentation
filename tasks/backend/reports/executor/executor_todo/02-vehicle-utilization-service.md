# Создать сервис утилизации транспортных средств

## Описание задачи
Реализовать API для отчета "Утилизация ТС (загруженность)" - отчет по анализу загруженности транспортных средств перевозчика.

## Frontend UI референс
- Компонент: `ExecutorVehicleUtilizationReport.vue`
- Фильтры: номер ТС, период, тип кузова
- Таблица: номер ТС, количество рейсов, перевезено (т), общая грузоподъемность (т), коэффициент загрузки (%)
- Метрики: общее количество ТС, средняя загрузка, общая перевезенная масса
- Графики: график загрузки по месяцам, топ самых загруженных ТС, распределение по типам ТС

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/vehicle-utilization`
Получение данных по утилизации транспортных средств

**Параметры запроса:**
```json
{
  "vehicleId": "number (optional)",
  "vehiclePlate": "string (optional)",
  "bodyType": "string (optional)",
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
      "vehicleId": "number",
      "vehiclePlate": "string",
      "vehicleModel": "string",
      "vehicleBodyType": "string",
      "totalRoutes": "number",
      "totalCargoWeight": "number",
      "vehicleCapacity": "number",
      "utilizationRate": "number",
      "averageRouteWeight": "number",
      "lastRouteDate": "string",
      "status": "string" // active, inactive, maintenance
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalVehicles": "number",
    "activeVehicles": "number",
    "averageUtilization": "number",
    "totalCargoWeight": "number",
    "totalCapacity": "number",
    "bestUtilizedVehicle": "string",
    "leastUtilizedVehicle": "string"
  }
}
```

### 2. GET `/api/reports/executor/vehicle-utilization/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/vehicle-utilization/timeline`
Получение динамики загрузки по времени

**Параметры:**
```json
{
  "vehicleId": "number (optional)",
  "period": "string", // week, month, quarter
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)"
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-W01",
      "totalRoutes": "number",
      "totalCargoWeight": "number",
      "totalCapacity": "number",
      "utilizationRate": "number",
      "activeVehicles": "number"
    }
  ],
  "vehicles": [
    {
      "vehicleId": "number",
      "vehiclePlate": "string",
      "timeline": [
        {
          "period": "2024-W01",
          "utilizationRate": "number",
          "routes": "number"
        }
      ]
    }
  ]
}
```

## Что нужно сделать

### 1. Создать DTO классы
```java
public class VehicleUtilizationReportDTO {
    private Long id;
    private Long vehicleId;
    private String vehiclePlate;
    private String vehicleModel;
    private String vehicleBodyType;
    private Integer totalRoutes;
    private BigDecimal totalCargoWeight;
    private BigDecimal vehicleCapacity;
    private BigDecimal utilizationRate; // Коэффициент загрузки в %
    private BigDecimal averageRouteWeight;
    private LocalDateTime lastRouteDate;
    private String status; // active, inactive, maintenance
}

public class VehicleUtilizationSummaryDTO {
    private Integer totalVehicles;
    private Integer activeVehicles;
    private BigDecimal averageUtilization;
    private BigDecimal totalCargoWeight;
    private BigDecimal totalCapacity;
    private String bestUtilizedVehicle;
    private String leastUtilizedVehicle;
}

public class VehicleUtilizationFilterDTO {
    private Long vehicleId;
    private String vehiclePlate;
    private String bodyType;
    private LocalDate dateFrom;
    private LocalDate dateTo;
    private BigDecimal minUtilization;
    private BigDecimal maxUtilization;
}
```

### 2. Создать сервис
```java
@Service
@Transactional(readOnly = true)
public class ExecutorVehicleUtilizationReportService {

    @Cacheable(value = "vehicle-utilization", key = "#executorId + '-' + #filter.hashCode()")
    public Page<VehicleUtilizationReportDTO> getVehicleUtilizationReport(
        Long executorId, VehicleUtilizationFilterDTO filter, Pageable pageable
    ) {
        // Расчет коэффициента загрузки: (перевезено / (грузоподъемность × рейсы)) × 100
    }

    @Cacheable(value = "vehicle-utilization-summary", key = "#executorId")
    public VehicleUtilizationSummaryDTO getUtilizationSummary(Long executorId) {
        // Агрегированные метрики по всем ТС
    }

    public List<VehicleUtilizationTimelineDTO> getUtilizationTimeline(
        Long executorId, TimelineFilter filter
    ) {
        // Динамика загрузки по периодам (неделя/месяц/квартал)
    }

    private BigDecimal calculateUtilizationRate(BigDecimal totalCargo, BigDecimal capacity, Integer routes) {
        if (capacity.compareTo(BigDecimal.ZERO) == 0 || routes == 0) {
            return BigDecimal.ZERO;
        }
        return totalCargo
            .multiply(new BigDecimal("100"))
            .divide(capacity.multiply(new BigDecimal(routes)), 2, RoundingMode.HALF_UP);
    }
}
```

### 3. Добавить в контроллер
```java
@GetMapping("/vehicle-utilization")
public ResponseEntity<Page<VehicleUtilizationReportDTO>> getVehicleUtilizationReport(
    @RequestParam(required = false) Long vehicleId,
    @RequestParam(required = false) String vehiclePlate,
    @RequestParam(required = false) String bodyType,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size
) {
    // Реализация
}

@GetMapping("/vehicle-utilization/summary")
public ResponseEntity<VehicleUtilizationSummaryDTO> getUtilizationSummary() {
    // Сводная статистика
}

@GetMapping("/vehicle-utilization/timeline")
public ResponseEntity<List<VehicleUtilizationTimelineDTO>> getUtilizationTimeline(
    @RequestParam(required = false) Long vehicleId,
    @RequestParam String period, // week, month, quarter
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo
) {
    // Таймлайн по периодам
}
```

### 4. SQL запрос для расчета утилизации
```sql
WITH vehicle_stats AS (
    SELECT
        v.id as vehicleId,
        v.registration_plate as vehiclePlate,
        v.brand || ' ' || v.model as vehicleModel,
        vbt.name_ru as vehicleBodyType,
        v.capacity_value as vehicleCapacity,
        COUNT(t.id) as totalRoutes,
        COALESCE(SUM(t.cargo_weight), 0) as totalCargoWeight,
        -- Коэффициент загрузки
        CASE
            WHEN v.capacity_value > 0 AND COUNT(t.id) > 0
            THEN (COALESCE(SUM(t.cargo_weight), 0) * 100.0) / (v.capacity_value * COUNT(t.id))
            ELSE 0
        END as utilizationRate,
        MAX(t.updated_at) as lastRouteDate
    FROM applications.vehicle v
        LEFT JOIN dictionaries.vehicle_body_type vbt ON v.vehicle_body_type_id = vbt.id
        LEFT JOIN applications.transport tr ON v.id = tr.vehicle_id
        LEFT JOIN applications.transportation t ON tr.id = (
            SELECT transport_id FROM applications.transport
            WHERE vehicle_id = v.id AND transportation_id IS NOT NULL
            LIMIT 1
        )
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
    WHERE
        v.executor_organization_id = :executorId
        AND (:vehicleId IS NULL OR v.id = :vehicleId)
        AND (:vehiclePlate IS NULL OR v.registration_plate ILIKE '%' || :vehiclePlate || '%')
        AND (:dateFrom IS NULL OR t.created_at >= :dateFrom)
        AND (:dateTo IS NULL OR t.created_at <= :dateTo)
    GROUP BY v.id, v.registration_plate, v.brand, v.model, vbt.name_ru, v.capacity_value
)
SELECT * FROM vehicle_stats
WHERE utilizationRate >= COALESCE(:minUtilization, 0)
ORDER BY utilizationRate DESC, totalRoutes DESC
```

### 5. Интеграция с GPS данными (для определения статуса ТС)
```java
@Component
public class VehicleStatusResolver {

    public String determineVehicleStatus(Long vehicleId, LocalDateTime lastRouteDate) {
        // Проверка последних GPS координат из gis.veh_latest_loc
        // Если нет активности > 30 дней - inactive
        // Если есть активность - active
    }
}
```

## Требования
- ✅ Кэширование тяжелых расчетов через Redis
- ✅ Валидация коэффициента загрузки (не более 100%)
- ✅ Обработка случаев когда vehicleCapacity = 0
- ✅ Правильный rounding для денежных величин
- ✅ Оптимизация запросов для больших объемов данных

## Критерии приемки
- [ ] Коэффициент загрузки рассчитывается корректно
- [ ] Кэширование работает и улучшает производительность
- [ ] Фильтрация по всем параметрам работает
- [ ] Таймлайн по периодам формируется правильно
- [ ] Статусы ТС определяются корректно
- [ ] Нагрузочное тестирование показывает < 2с для типичных запросов