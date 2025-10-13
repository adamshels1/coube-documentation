# Создать сервис анализа рейсов за период

## Описание задачи
Реализовать API для отчета "Кол-во рейсов за период" - отчет по анализу количества рейсов, пробега и времени в пути за выбранный период.

## Frontend UI референс
- Компонент: `ExecutorRoutesPeriodReport.vue`
- Фильтры: номер рейса, период, водитель, ТС
- Таблица: номер рейса, дата, пробег (км), время ожидания (часы), время в пути (часы)
- Метрики: всего рейсов, общий пробег, среднее время ожидания, среднее время в пути
- Графики: график рейсов по месяцам, распределение времени ожидания, анализ пробега

## Эндпоинты для реализации

### 1. GET `/api/reports/executor/routes-period`
Получение данных по рейсам за период

**Параметры запроса:**
```json
{
  "routeNumber": "string (optional)",
  "driverId": "number (optional)",
  "vehicleId": "number (optional)",
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
      "routeDate": "string",
      "distance": "number",
      "waitingTimeHours": "number",
      "travelTimeHours": "number",
      "loadingTimeHours": "number",
      "unloadingTimeHours": "number",
      "totalTimeHours": "number",
      "averageSpeed": "number",
      "driverName": "string",
      "vehiclePlate": "string",
      "routeFrom": "string",
      "routeTo": "string",
      "cargoWeight": "number"
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalRoutes": "number",
    "totalDistance": "number",
    "totalWaitingTime": "number",
    "totalTravelTime": "number",
    "averageWaitingTime": "number",
    "averageTravelTime": "number",
    "averageSpeed": "number"
  }
}
```

### 2. GET `/api/reports/executor/routes-period/export`
Экспорт отчета в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл

### 3. GET `/api/reports/executor/routes-period/analytics`
Получение аналитики по рейсам

**Параметры:**
```json
{
  "period": "string", // week, month, quarter
  "dateFrom": "string (optional)",
  "dateTo": "string (optional)",
  "groupBy": "string" // driver, vehicle, route, month
}
```

**Ответ:**
```json
{
  "timeline": [
    {
      "period": "2024-W01",
      "routeCount": "number",
      "totalDistance": "number",
      "averageWaitingTime": "number",
      "averageTravelTime": "number",
      "averageSpeed": "number"
    }
  ],
  "byDriver": [
    {
      "driverId": "number",
      "driverName": "string",
      "routeCount": "number",
      "totalDistance": "number",
      "averageWaitingTime": "number",
      "averageTravelTime": "number",
      "efficiency": "number"
    }
  ],
  "byVehicle": [
    {
      "vehicleId": "number",
      "vehiclePlate": "string",
      "routeCount": "number",
      "totalDistance": "number",
      "utilizationRate": "number"
    }
  ]
}
```

## Что нужно сделать

### 1. Создать DTO классы
```java
public class RoutesPeriodReportDTO {
    private Long id;
    private String routeNumber;
    private LocalDate routeDate;
    private BigDecimal distance; // км
    private BigDecimal waitingTimeHours; // время ожидания на погрузке/выгрузке
    private BigDecimal travelTimeHours; // время в пути
    private BigDecimal loadingTimeHours;
    private BigDecimal unloadingTimeHours;
    private BigDecimal totalTimeHours;
    private BigDecimal averageSpeed; // км/ч
    private String driverName;
    private String vehiclePlate;
    private String routeFrom;
    private String routeTo;
    private BigDecimal cargoWeight;
}

public class RoutesPeriodSummaryDTO {
    private Integer totalRoutes;
    private BigDecimal totalDistance;
    private BigDecimal totalWaitingTime;
    private BigDecimal totalTravelTime;
    private BigDecimal averageWaitingTime;
    private BigDecimal averageTravelTime;
    private BigDecimal averageSpeed;
}

public class RoutesAnalyticsDTO {
    private List<RoutePeriodTimelineDTO> timeline;
    private List<DriverPerformanceDTO> byDriver;
    private List<VehiclePerformanceDTO> byVehicle;
}
```

### 2. Создать сервис
```java
@Service
@Transactional(readOnly = true)
public class ExecutorRoutesPeriodReportService {

    public Page<RoutesPeriodReportDTO> getRoutesPeriodReport(
        Long executorId, RoutesPeriodFilterDTO filter, Pageable pageable
    ) {
        // Основной запрос с расчетом времени и расстояния
    }

    public RoutesPeriodSummaryDTO getRoutesSummary(Long executorId, RoutesPeriodFilterDTO filter) {
        // Агрегированные метрики
    }

    public RoutesAnalyticsDTO getRoutesAnalytics(
        Long executorId, AnalyticsFilter filter
    ) {
        // Аналитика по группировкам: водитель, ТС, месяц
    }

    private BigDecimal calculateAverageSpeed(BigDecimal distance, BigDecimal travelTimeHours) {
        if (travelTimeHours.compareTo(BigDecimal.ZERO) == 0) {
            return BigDecimal.ZERO;
        }
        return distance.divide(travelTimeHours, 2, RoundingMode.HALF_UP);
    }

    private BigDecimal calculateTravelTime(LocalDateTime loadingTime, LocalDateTime unloadingTime) {
        if (loadingTime == null || unloadingTime == null) {
            return BigDecimal.ZERO;
        }
        Duration duration = Duration.between(loadingTime, unloadingTime);
        return BigDecimal.valueOf(duration.toMinutes() / 60.0);
    }
}
```

### 3. Добавить в контроллер
```java
@GetMapping("/routes-period")
public ResponseEntity<Page<RoutesPeriodReportDTO>> getRoutesPeriodReport(
    @RequestParam(required = false) String routeNumber,
    @RequestParam(required = false) Long driverId,
    @RequestParam(required = false) Long vehicleId,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
    @RequestParam(defaultValue = "0") int page,
    @RequestParam(defaultValue = "20") int size
) {
    // Реализация
}

@GetMapping("/routes-period/analytics")
public ResponseEntity<RoutesAnalyticsDTO> getRoutesAnalytics(
    @RequestParam(required = false) Long driverId,
    @RequestParam(required = false) Long vehicleId,
    @RequestParam String period, // week, month, quarter
    @RequestParam String groupBy, // driver, vehicle, route, month
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
    @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo
) {
    // Аналитика с группировкой
}
```

### 4. Основной SQL запрос
```sql
WITH route_details AS (
    SELECT
        t.id,
        tc.transportation_number as routeNumber,
        t.created_at::date as routeDate,
        -- Расчет расстояния через PostGIS
        COALESCE(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        ) as distance,
        -- Время ожидания на погрузке/выгрузке
        COALESCE(cl_from.loading_time_hours, 0) + COALESCE(cl_to.loading_time_hours, 0) as waitingTimeHours,
        cl_from.loading_time_hours as loadingTimeHours,
        cl_to.loading_time_hours as unloadingTimeHours,
        -- Время в пути
        CASE
            WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
            THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
            ELSE 0
        END as travelTimeHours,
        -- Общее время
        CASE
            WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
            THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
            ELSE 0
        END + COALESCE(cl_from.loading_time_hours, 0) + COALESCE(cl_to.loading_time_hours, 0) as totalTimeHours,
        -- Средняя скорость
        CASE
            WHEN COALESCE(
                ST_Distance(
                    ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                    ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                ) / 1000, 0
            ) > 0 AND
            CASE
                WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
                THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
                ELSE 0
            END > 0
            THEN COALESCE(
                ST_Distance(
                    ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                    ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
                ) / 1000, 0
            ) / CASE
                WHEN cl_from.loading_datetime IS NOT NULL AND cl_to.loading_datetime IS NOT NULL
                THEN EXTRACT(EPOCH FROM (cl_to.loading_datetime - cl_from.loading_datetime)) / 3600
                ELSE 1
            END
            ELSE 0
        END as averageSpeed,
        -- Информация о водителе и ТС
        e.first_name || ' ' || e.last_name as driverName,
        v.registration_plate as vehiclePlate,
        cl_from.address as routeFrom,
        cl_to.address as routeTo,
        t.cargo_weight
    FROM applications.transportation t
        LEFT JOIN applications.transportation_cost tc ON t.id = tc.transportation_id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id AND cl_to.loading_type = 'UNLOADING'
        LEFT JOIN applications.transport tr ON tc.transportation_id = (
            SELECT transportation_number FROM applications.transportation_cost
            WHERE executor_organization_id = :executorId
            AND id = t.id
            LIMIT 1
        )
        LEFT JOIN applications.employee_transport et ON tr.id = et.transport_id AND et.active = true
        LEFT JOIN user.employee e ON et.employee_id = e.id
        LEFT JOIN applications.vehicle v ON tr.vehicle_id = v.id
    WHERE
        tc.executor_organization_id = :executorId
        AND t.status = 'completed'
        AND (:routeNumber IS NULL OR tc.transportation_number ILIKE '%' || :routeNumber || '%')
        AND (:driverId IS NULL OR e.id = :driverId)
        AND (:vehicleId IS NULL OR v.id = :vehicleId)
        AND (:dateFrom IS NULL OR t.created_at::date >= :dateFrom)
        AND (:dateTo IS NULL OR t.created_at::date <= :dateTo)
)
SELECT * FROM route_details
WHERE distance > 0 OR travelTimeHours > 0
ORDER BY routeDate DESC, routeNumber DESC
```

### 5. Аналитика по группировкам
```sql
-- Аналитика по водителям
SELECT
    e.id as driverId,
    e.first_name || ' ' || e.last_name as driverName,
    COUNT(t.id) as routeCount,
    SUM(distance) as totalDistance,
    AVG(waitingTimeHours) as averageWaitingTime,
    AVG(travelTimeHours) as averageTravelTime,
    -- Эффективность (расчет на основе времени и расстояния)
    (SUM(distance) / NULLIF(SUM(totalTimeHours), 0)) as efficiency
FROM route_details rd
    JOIN user.employee e ON rd.driverName = e.first_name || ' ' || e.last_name
GROUP BY e.id, e.first_name, e.last_name
ORDER BY efficiency DESC
```

## Требования
- ✅ Оптимизация PostGIS запросов для расчета расстояний
- ✅ Кэширование аналитических данных
- ✅ Валидация временных интервалов
- ✅ Обработка случаев с отсутствующими координатами
- ✅ Pagination для больших объемов данных

## Критерии приемки
- [ ] Расчет расстояния и времени работает корректно
- [ ] Средняя скорость рассчитывается правильно
- [ ] Аналитика по группировкам работает
- [ ] Фильтры по водителям/ТС применяются
- [ ] Производительность < 1с для типичных запросов
- [ ] Обработка некорректных данных (пустые координаты)