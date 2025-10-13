# Безопасная адаптация существующих отчетов (без поломки заказчика)

## 🎯 Задача
Адаптировать 10 существующих отчетов заказчика для перевозчика, создав новые контроллеры и сервисы, не трогая существующий функционал заказчика.

## 📋 Стратегия: НЕ ИЗМЕНЯТЬ существующий код, а СОЗДАВАТЬ новый

### **🚫 НЕ ДЕЛАТЬ (сломает заказчика):**
- ❌ Изменять существующие контроллеры `ReportsController`
- ❌ Менять существующие сервисы `ApplicationRegistryReportService`
- ❌ Изменять SQL в существующих репозиториях
- ❌ Менять URL `/api/reports/applications/*`
- ❌ Трогать существующие DTO классы

### **✅ ДЕЛАТЬ (безопасно):**
- ✅ Создавать новые контроллеры `ExecutorReportsController`
- ✅ Создавать новые сервисы `ExecutorApplicationRegistryReportService`
- ✅ Создавать новые репозитории или новые методы в существующих
- ✅ Использовать новые URL `/api/reports/executor/*`
- ✅ Создавать новые DTO классы или наследоваться

## 🏗️ Архитектура безопасной адаптации

### **1. Создать иерархию сервисов:**

#### **Базовый абстрактный класс:**
```java
@Service
public abstract class BaseReportService {

    protected final TransportationRepository transportationRepository;
    protected final EmployeeRepository employeeRepository;

    // Общие методы для всех отчетов
    protected Pageable createDefaultPageable(int page, int size) {
        return PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
    }

    protected Long getCurrentOrganizationId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        // Получаем organization_id из токена/сессии
        return securityContext.getCurrentOrganizationId();
    }
}
```

#### **Существующий сервис заказчика (НЕ ТРОГАТЬ):**
```java
@Service
public class ApplicationRegistryReportService extends BaseReportService {

    public Page<ApplicationRegistryDTO> getCustomerReport(
        Long organizationId, CustomerReportFilter filter, Pageable pageable
    ) {
        // Существующая логика для заказчика - НЕ МЕНЯТЬ!
    }
}
```

#### **Новый сервис перевозчика (СОЗДАТЬ):**
```java
@Service
public class ExecutorApplicationRegistryReportService extends BaseReportService {

    private final ApplicationRegistryReportService customerService; // переиспользуем логику

    public Page<ExecutorApplicationRegistryDTO> getExecutorReport(
        ExecutorReportFilter filter, Pageable pageable
    ) {
        Long executorId = getCurrentOrganizationId();

        // Вариант 1: Переиспользовать существующую логику с адаптацией
        return adaptCustomerLogicForExecutor(executorId, filter, pageable);

        // Вариант 2: Новая реализация (если сильно отличается)
        // return newImplementation(executorId, filter, pageable);
    }

    private Page<ExecutorApplicationRegistryDTO> adaptCustomerLogicForExecutor(
        Long executorId, ExecutorReportFilter filter, Pageable pageable
    ) {
        // Используем существующие репозитории но с другими условиями
        return transportationRepository.findByExecutorOrganizationIdWithFilters(
            executorId, filter, pageable
        ).map(this::convertToExecutorDTO);
    }
}
```

### **2. Создать новые контроллеры:**

#### **Существующий контроллер (НЕ ТРОГАТЬ):**
```java
@RestController
@RequestMapping("/api/reports/applications")
public class ReportsController {

    @Autowired
    private ApplicationRegistryReportService applicationRegistryService;

    @GetMapping("/registry")
    public ResponseEntity<Page<ApplicationRegistryDTO>> getRegistry(
        // Существующие эндпоинты - НЕ МЕНЯТЬ!
    ) {
        // Существующая логика
    }
}
```

#### **Новый контроллер перевозчика (СОЗДАТЬ):**
```java
@RestController
@RequestMapping("/api/reports/executor")
@PreAuthorize("hasRole('EXECUTOR')")
public class ExecutorReportsController {

    @Autowired
    private ExecutorApplicationRegistryReportService executorApplicationRegistryService;

    @GetMapping("/completed-transportation-registry")
    public ResponseEntity<Page<ExecutorApplicationRegistryDTO>> getExecutorRegistry(
        @RequestParam(required = false) String routeNumber,
        @RequestParam(required = false) Long customerId,
        @RequestParam(required = false) String status,
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size
    ) {
        Long executorId = getCurrentExecutorId();
        ExecutorReportFilter filter = new ExecutorReportFilter(routeNumber, customerId, status);
        Pageable pageable = PageRequest.of(page, size);

        Page<ExecutorApplicationRegistryDTO> result = executorApplicationRegistryService
            .getExecutorReport(filter, pageable);

        return ResponseEntity.ok(result);
    }

    private Long getCurrentExecutorId() {
        return securityContext.getCurrentExecutorId();
    }
}
```

### **3. Безопасное расширение репозиториев:**

#### **Вариант А: Новые методы в существующем репозитории:**
```java
@Repository
public interface TransportationRepository extends JpaRepository<Transportation, Long> {

    // Существующие методы для заказчика - НЕ ТРОГАТЬ!
    Page<Transportation> findByOrganizationIdAndFilters(
        Long organizationId, CustomerFilter filter, Pageable pageable
    );

    // НОВЫЕ методы для перевозчика:
    @Query("SELECT t FROM Transportation t " +
           "LEFT JOIN TransportationCost tc ON t.id = tc.transportationId " +
           "WHERE tc.executorOrganizationId = :executorId " +
           "AND (:routeNumber IS NULL OR tc.transportationNumber LIKE %:routeNumber%) " +
           "AND (:customerId IS NULL OR t.organizationId = :customerId)")
    Page<Transportation> findByExecutorOrganizationIdWithFilters(
        @Param("executorId") Long executorId,
        @Param("routeNumber") String routeNumber,
        @Param("customerId") Long customerId,
        Pageable pageable
    );
}
```

#### **Вариант Б: Отдельный репозиторий для перевозчика:**
```java
@Repository
public interface ExecutorTransportationRepository extends JpaRepository<Transportation, Long> {

    // Только методы для перевозчика
    @Query("SELECT t FROM Transportation t " +
           "LEFT JOIN TransportationCost tc ON t.id = tc.transportationId " +
           "WHERE tc.executorOrganizationId = :executorId")
    Page<Transportation> findByExecutorOrganizationId(
        @Param("executorId") Long executorId, Pageable pageable
    );
}
```

### **4. Создать новые DTO (безопасное наследование):**

#### **Вариант А: Наследование от существующего DTO:**
```java
// Существующий DTO (НЕ ТРОГАТЬ)
public class ApplicationRegistryDTO {
    private Long id;
    private String applicationNumber;
    private String executorName; // для заказчика
    private String customerName;   // для заказчика
    // ... другие поля
}

// Новый DTO для перевозчика
public class ExecutorApplicationRegistryDTO extends ApplicationRegistryDTO {
    // Дополнительные поля специфичные для перевозчика
    private String profitMargin;
    private String actualCost;

    // Или переопределить геттеры для другой логики
    @Override
    public String getExecutorName() {
        // Для перевозчика это поле показывает заказчика
        return super.getCustomerName();
    }
}
```

#### **Вариант Б: Композиция:**
```java
// Новый независимый DTO
public class ExecutorApplicationRegistryDTO {
    private Long id;
    private String routeNumber;
    private String customerName; // для перевозчика показываем заказчика
    private String cargoName;
    private BigDecimal amount;
    // ... только нужные поля
}
```

## 🔒 План безопасного развертывания

### **Этап 1: Подготовка (без влияния на прод)**
1. Создать все новые классы в отдельных пакетах:
   - `com.coube.reports.executor.controller`
   - `com.coube.reports.executor.service`
   - `com.coube.reports.executor.dto`

2. Создать новые тесты для нового функционала:
   - `ExecutorReportsControllerTest`
   - `ExecutorApplicationRegistryReportServiceTest`

### **Этап 2: Тестирование в изолированной среде**
1. Запустить новые эндпоинты:
   - `GET /api/reports/executor/completed-transportation-registry`
   - `GET /api/reports/executor/financial-report`
   - и т.д.

2. Проверить что старые эндпоинты работают:
   - `GET /api/reports/applications/registry` ← должен работать как раньше
   - `GET /api/reports/financial-payment` ← должен работать как раньше

### **Этап 3: Поэтапный релиз**
1. **Deploy с Feature Flag:**
```java
@RestController
@RequestMapping("/api/reports/executor")
public class ExecutorReportsController {

    @Value("${reports.executor.enabled:false}")
    private boolean executorReportsEnabled;

    @GetMapping("/completed-transportation-registry")
    public ResponseEntity<?> getExecutorRegistry() {
        if (!executorReportsEnabled) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body("Executor reports are not enabled");
        }
        // ... логика
    }
}
```

2. **Тестирование на small group пользователей**
3. **Включить для всех перевозчиков**
4. **Убрать feature flag**

## 🧪 Тесты безопасности

### **Тест 1: Проверка изоляции:**
```java
@SpringBootTest
@AutoConfigureTestDatabase
class SafeAdaptationTest {

    @Test
    void whenGetCustomerReports_thenReturnsOnlyCustomerData() {
        // Проверяем что старые эндпоинты заказчика не изменились
    }

    @Test
    void whenGetExecutorReports_thenReturnsOnlyExecutorData() {
        // Проверяем что новые эндпоинты перевозчика работают правильно
    }

    @Test
    void whenCustomerAccessExecutorEndpoint_thenReturns403() {
        // Проверяем что заказчик не может получить доступ к отчетам перевозчика
    }

    @Test
    void whenExecutorAccessCustomerEndpoint_thenReturns403() {
        // Проверяем что перевозчик не может получить доступ к отчетам заказчика
    }
}
```

### **Тест 2: Нагрузочное тестирование:**
```java
@SpringBootTest
class PerformanceTest {

    @Test
    void whenHighLoadOnBothEndpoints_thenNoPerformanceDegradation() {
        // Проверяем что добавление новых эндпоинтов не замедляет старые
    }
}
```

## 📋 Чек-лист безопасной адаптации

### **Перед началом:**
- [ ] Создать branch `feature/executor-reports`
- [ ] Настроить тестовое окружение
- [ ] Сделать backup существующего функционала

### **Разработка:**
- [ ] Создавать новые классы, не изменяя существующие
- [ ] Использовать новые URL пути
- [ ] Писать тесты для нового функционала
- [ ] Не трогать конфигурацию безопасности заказчика

### **Тестирование:**
- [ ] Все старые эндпоинты работают как раньше
- [ ] Новые эндпоинты работают корректно
- [ ] Нет смешения данных между заказчиком и перевозчиком
- [ ] Права доступа работают правильно

### **Релиз:**
- [ ] Code review с фокусом на изоляцию
- [ ] Deploy с feature flags
- [ ] Постепенное включение функционала
- [ ] Мониторинг производительности

## 🌐 Полный перечень эндпоинтов

### **СУЩЕСТВУЮЩИЕ ЭНДПОИНТЫ ЗАКАЗЧИКА (НЕ ТРОГАТЬ!):**

| URL | Метод | Описание | Контроллер | Сервис |
|-----|-------|----------|------------|---------|
| `/api/reports/applications/registry` | GET | Реестр заявок и перевозок | `ReportsController` | `ApplicationRegistryReportService` |
| `/api/reports/applications/registry/export` | GET | Экспорт реестра в Excel | `ReportsController` | `ApplicationRegistryReportService` |
| `/api/reports/disputes-claims` | GET | Споры и претензии | `ReportsController` | `DisputesClaimsReportService` |
| `/api/reports/disputes-claims/export` | GET | Экспорт споров в Excel | `ReportsController` | `DisputesClaimsReportService` |
| `/api/reports/geo-analytics` | GET | Гео-аналитика маршрутов | `ReportsController` | `GeoAnalyticsReportService` |
| `/api/reports/geo-analytics/export` | GET | Экспорт гео-аналитики | `ReportsController` | `GeoAnalyticsReportService` |
| `/api/reports/geo-analytics/map-data` | GET | Данные для карты | `ReportsController` | `GeoAnalyticsReportService` |
| `/api/reports/routes-contracts` | GET | Контракты и заявки | `ReportsController` | `RoutesContractsReportService` |
| `/api/reports/routes-contracts/export` | GET | Экспорт контрактов | `ReportsController` | `RoutesContractsReportService` |
| `/api/reports/financial-payment` | GET | Финансовые платежи | `ReportsController` | `FinancialPaymentReportService` |
| `/api/reports/financial-payment/export` | GET | Экспорт финансового отчета | `ReportsController` | `FinancialPaymentReportService` |
| `/api/reports/financial-payment/summary` | GET | Сводная финансовая статистика | `ReportsController` | `FinancialPaymentReportService` |
| `/api/reports/debtor-analysis` | GET | Дебиторская задолженность | `ReportsController` | `DebtorAnalysisReportService` |
| `/api/reports/debtor-analysis/export` | GET | Экспорт дебиторки | `ReportsController` | `DebtorAnalysisReportService` |
| `/api/reports/debtor-analysis/customers` | GET | Должники (агрегация) | `ReportsController` | `DebtorAnalysisReportService` |
| `/api/reports/platform-commission` | GET | Комиссии платформы | `ReportsController` | `PlatformCommissionReportService` |
| `/api/reports/platform-commission/export` | GET | Экспорт комиссий | `ReportsController` | `PlatformCommissionReportService` |
| `/api/reports/platform-commission/subscription-info` | GET | Информация о подписке | `ReportsController` | `PlatformCommissionReportService` |
| `/api/reports/completed-transport` | GET | Выполненные перевозки | `ReportsController` | `CompletedTransportReportService` |
| `/api/reports/completed-transport/export` | GET | Экспорт выполненных перевозок | `ReportsController` | `CompletedTransportReportService` |
| `/api/reports/sla-performance` | GET | SLA и производительность | `ReportsController` | `SLAPerformanceReportService` |
| `/api/reports/sla-performance/export` | GET | Экспорт SLA отчета | `ReportsController` | `SLAPerformanceReportService` |
| `/api/reports/sla-performance/statistics` | GET | Статистика SLA | `ReportsController` | `SLAPerformanceReportService` |
| `/api/reports/executor-comparison` | GET | Сравнение исполнителей | `ReportsController` | `ExecutorComparisonReportService` |
| `/api/reports/executor-comparison/export` | GET | Экспорт сравнения исполнителей | `ReportsController` | `ExecutorComparisonReportService` |
| `/api/reports/executor-comparison/top-performers` | GET | Топ исполнители | `ReportsController` | `ExecutorComparisonReportService` |
| `/api/reports/signature-logs` | GET | Логи подписей и ЭЦП | `ReportsController` | `SignatureLogsReportService` |
| `/api/reports/signature-logs/export` | GET | Экспорт логов подписей | `ReportsController` | `SignatureLogsReportService` |
| `/api/reports/signature-logs/statistics` | GET | Статистика подписей | `ReportsController` | `SignatureLogsReportService` |
| `/api/reports/notification-logs` | GET | Логи уведомлений | `ReportsController` | `NotificationLogsReportService` |
| `/api/reports/notification-logs/export` | GET | Экспорт логов уведомлений | `ReportsController` | `NotificationLogsReportService` |
| `/api/reports/notification-logs/statistics` | GET | Статистика уведомлений | `ReportsController` | `NotificationLogsReportService` |

**Итого: 31 эндпоинт для заказчика (не трогать!)**

---

### **НОВЫЕ ЭНДПОИНТЫ ПЕРЕВОЗЧИКА (СОЗДАТЬ):**

#### **Адаптированные отчеты (10 отчетов × 2-3 эндпоинта):**

| URL | Метод | Описание | Контроллер | Сервис | Статус |
|-----|-------|----------|------------|---------|--------|
| `/api/reports/executor/completed-transportation-registry` | GET | Реестр завершенных перевозок | `ExecutorReportsController` | `ExecutorApplicationRegistryReportService` | Адаптация |
| `/api/reports/executor/completed-transportation-registry/export` | GET | Экспорт реестра | `ExecutorReportsController` | `ExecutorApplicationRegistryReportService` | Адаптация |
| `/api/reports/executor/avr-insurance` | GET | АВР и страховые полисы | `ExecutorReportsController` | `ExecutorAVRInsuranceReportService` | **НОВЫЙ** |
| `/api/reports/executor/avr-insurance/export` | GET | Экспорт АВР | `ExecutorReportsController` | `ExecutorAVRInsuranceReportService` | **НОВЫЙ** |
| `/api/reports/executor/avr-insurance/{routeId}/documents` | GET | Документы по рейсу | `ExecutorReportsController` | `ExecutorAVRInsuranceReportService` | **НОВЫЙ** |
| `/api/reports/executor/financial-report` | GET | Финансовый отчет перевозчика | `ExecutorReportsController` | `ExecutorFinancialReportService` | Адаптация |
| `/api/reports/executor/financial-report/export` | GET | Экспорт фин. отчета | `ExecutorReportsController` | `ExecutorFinancialReportService` | Адаптация |
| `/api/reports/executor/debtor-report` | GET | Дебиторка заказчиков | `ExecutorReportsController` | `ExecutorDebtorReportService` | Адаптация |
| `/api/reports/executor/debtor-report/export` | GET | Экспорт дебиторки | `ExecutorReportsController` | `ExecutorDebtorReportService` | Адаптация |
| `/api/reports/executor/sla-report` | GET | SLA и опоздания | `ExecutorReportsController` | `ExecutorSLAReportService` | Адаптация |
| `/api/reports/executor/sla-report/export` | GET | Экспорт SLA | `ExecutorReportsController` | `ExecutorSLAReportService` | Адаптация |
| `/api/reports/executor/disputes-claims` | GET | Споры и претензии | `ExecutorReportsController` | `ExecutorDisputesReportService` | **НОВЫЙ** |
| `/api/reports/executor/disputes-claims/export` | GET | Экспорт споров | `ExecutorReportsController` | `ExecutorDisputesReportService` | **НОВЫЙ** |
| `/api/reports/executor/disputes-claims/kanban` | GET | Kanban доска споров | `ExecutorReportsController` | `ExecutorDisputesReportService` | **НОВЫЙ** |
| `/api/reports/executor/driver-comparison` | GET | Сравнение водителей | `ExecutorReportsController` | `ExecutorDriverComparisonReportService` | Адаптация |
| `/api/reports/executor/driver-comparison/export` | GET | Экспорт водителей | `ExecutorReportsController` | `ExecutorDriverComparisonReportService` | Адаптация |
| `/api/reports/executor/driver-comparison/top-performers` | GET | Топ водители | `ExecutorReportsController` | `ExecutorDriverComparisonReportService` | Адаптация |
| `/api/reports/executor/geo-analytics-report` | GET | Гео-аналитика перевозчика | `ExecutorReportsController` | `ExecutorGeoAnalyticsReportService` | Адаптация |
| `/api/reports/executor/geo-analytics-report/export` | GET | Экспорт гео-аналитики | `ExecutorReportsController` | `ExecutorGeoAnalyticsReportService` | Адаптация |
| `/api/reports/executor/geo-analytics-report/map-data` | GET | Данные для карты | `ExecutorReportsController` | `ExecutorGeoAnalyticsReportService` | Адаптация |
| `/api/reports/executor/signature-logs-report` | GET | Логи подписей перевозчика | `ExecutorReportsController` | `ExecutorSignatureLogsReportService` | Адаптация |
| `/api/reports/executor/signature-logs-report/export` | GET | Экспорт логов подписей | `ExecutorReportsController` | `ExecutorSignatureLogsReportService` | Адаптация |
| `/api/reports/executor/commission-report` | GET | Комиссии перевозчика | `ExecutorReportsController` | `ExecutorCommissionReportService` | Адаптация |
| `/api/reports/executor/commission-report/export` | GET | Экспорт комиссий | `ExecutorReportsController` | `ExecutorCommissionReportService` | Адаптация |
| `/api/reports/executor/notification-logs-report` | GET | Логи уведомлений перевозчика | `ExecutorReportsController` | `ExecutorNotificationLogsReportService` | Адаптация |
| `/api/reports/executor/notification-logs-report/export` | GET | Экспорт логов уведомлений | `ExecutorReportsController` | `ExecutorNotificationLogsReportService` | Адаптация |
| `/api/reports/executor/vehicle-utilization` | GET | Утилизация ТС | `ExecutorReportsController` | `ExecutorVehicleUtilizationReportService` | **НОВЫЙ** |
| `/api/reports/executor/vehicle-utilization/export` | GET | Экспорт утилизации ТС | `ExecutorReportsController` | `ExecutorVehicleUtilizationReportService` | **НОВЫЙ** |
| `/api/reports/executor/vehicle-utilization/timeline` | GET | Таймлайн утилизации | `ExecutorReportsController` | `ExecutorVehicleUtilizationReportService` | **НОВЫЙ** |
| `/api/reports/executor/routes-period` | GET | Рейсы за период | `ExecutorReportsController` | `ExecutorRoutesPeriodReportService` | **НОВЫЙ** |
| `/api/reports/executor/routes-period/export` | GET | Экспорт рейсов | `ExecutorReportsController` | `ExecutorRoutesPeriodReportService` | **НОВЫЙ** |
| `/api/reports/executor/routes-period/analytics` | GET | Аналитика рейсов | `ExecutorReportsController` | `ExecutorRoutesPeriodReportService` | **НОВЫЙ** |
| `/api/reports/executor/contracts-analysis` | GET | Анализ контрактов | `ExecutorReportsController` | `ExecutorContractsAnalysisReportService` | Адаптация |
| `/api/reports/executor/contracts-analysis/export` | GET | Экспорт контрактов | `ExecutorReportsController` | `ExecutorContractsAnalysisReportService` | Адаптация |
| `/api/reports/executor/contracts-analysis/statistics` | GET | Статистика контрактов | `ExecutorReportsController` | `ExecutorContractsAnalysisReportService` | Адаптация |

**Итого: 39 эндпоинтов для перевозчика (создать)**

---

## 📊 Статистика эндпоинтов

| Категория | Количество эндпоинтов | Статус |
|------------|---------------------|--------|
| **Существующие (заказчик)** | 31 | **НЕ ТРОГАТЬ** |
| **Адаптированные (перевозчик)** | 28 | Создать на основе существующих |
| **Новые (уникальные перевозчик)** | 11 | Разработать с нуля |
| **ВСЕГО ПЕРЕВОЗЧИК** | 39 | Создать |
| **ОБЩЕЕ В СИСТЕМЕ** | 70 | 31 + 39 |

## 🔗 Карта соответствия эндпоинтов

| Отчет заказчика | Отчет перевозчика | Изменения |
|-----------------|------------------|-----------|
| `/api/reports/applications/registry` | `/api/reports/executor/completed-transportation-registry` | Фильтрация по executor_organization_id |
| `/api/reports/financial-payment` | `/api/reports/executor/financial-report` | Источник данных + МФО |
| `/api/reports/geo-analytics` | `/api/reports/executor/geo-analytics-report` | Фильтрация по перевозчику |
| `/api/reports/sla-performance` | `/api/reports/executor/sla-report` | Анализ производительности перевозчика |
| `/api/reports/executor-comparison` | `/api/reports/executor/driver-comparison` | Анализ собственных водителей |

## ✅ Результат

После безопасной адаптации получим:
- **Заказчик:** Его функционал работает точно как раньше без изменений (31 эндпоинт)
- **Перевозчик:** Получает свои отчеты по новым URL `/api/reports/executor/*` (39 эндпоинтов)
- **Система:** Два независимых набора отчетов с общей базовой логикой
- **Безопасность:** Полная изоляция данных и прав доступа
- **Масштаб:** 70 эндпоинтов в системе без конфликта