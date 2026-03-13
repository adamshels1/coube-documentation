# Создать конфигурацию безопасности для отчетов перевозчика

## Задача
Настроить Spring Security для обеспечения доступа к отчетам только для авторизованных пользователей организации-перевозчика.

## Что нужно сделать

### 1. Создать ExecutorSecurityContext
```java
@Component
public class ExecutorSecurityContext {

    private final EmployeeRepository employeeRepository;
    private final OrganizationRepository organizationRepository;

    public Long getCurrentExecutorId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            throw new SecurityException("User not authenticated");
        }

        String email = authentication.getName();
        Employee employee = employeeRepository.findByEmailAndIsActive(email, true)
            .orElseThrow(() -> new SecurityException("Employee not found: " + email));

        // Проверяем что сотрудник принадлежит организации-перевозчику
        if (!hasExecutorRole(employee)) {
            throw new SecurityException("User is not an executor: " + email);
        }

        return employee.getOrganizationId();
    }

    private boolean hasExecutorRole(Employee employee) {
        return employee.getOrganization().getBusinessType() == BusinessType.EXECUTOR;
    }

    public boolean canAccessTransportationData(Long transportationId) {
        Long executorId = getCurrentExecutorId();

        // Проверяем что перевозка принадлежит текущему перевозчику
        return transportationRepository.existsByIdAndExecutorOrganizationId(transportationId, executorId);
    }
}
```

### 2. Создать PermissionEvaluator
```java
@Component("executorSecurity")
public class ExecutorPermissionEvaluator implements PermissionEvaluator {

    private final ExecutorSecurityContext securityContext;

    public boolean canAccessExecutorData(Authentication authentication) {
        try {
            securityContext.getCurrentExecutorId();
            return true;
        } catch (SecurityException e) {
            return false;
        }
    }

    public boolean canAccessTransportation(Authentication authentication, Long transportationId) {
        return securityContext.canAccessTransportationData(transportationId);
    }

    @Override
    public boolean hasPermission(Authentication authentication, Object targetDomainObject, Object permission) {
        if ("executor_data".equals(permission)) {
            return canAccessExecutorData(authentication);
        }
        if ("transportation".equals(permission) && targetDomainObject instanceof Long) {
            return canAccessTransportation(authentication, (Long) targetDomainObject);
        }
        return false;
    }

    @Override
    public boolean hasPermission(Authentication authentication, Serializable targetId, String targetType, Object permission) {
        // Реализация для Serializable targetId
        return false;
    }
}
```

### 3. Обновить SecurityConfig
```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                // Публичные эндпоинты
                .requestMatchers("/api/auth/**").permitAll()
                .requestMatchers("/api/public/**").permitAll()

                // Эндпоинты отчетов перевозчика (только для авторизованных)
                .requestMatchers("/api/reports/executor/**").hasRole("EXECUTOR")

                // Все остальные требуют аутентификации
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt -> jwt.jwtDecoder(jwtDecoder())))
            .exceptionHandling(exceptions -> exceptions
                .authenticationEntryPoint(new BearerTokenAuthenticationEntryPoint())
                .accessDeniedHandler(new CustomAccessDeniedHandler())
            );

        return http.build();
    }

    @Bean
    public MethodSecurityExpressionHandler methodSecurityExpressionHandler() {
        DefaultMethodSecurityExpressionHandler handler = new DefaultMethodSecurityExpressionHandler();
        handler.setPermissionEvaluator(new ExecutorPermissionEvaluator());
        return handler;
    }
}
```

### 4. Создать кастомные аннотации
```java
@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@PreAuthorize("hasRole('EXECUTOR') and @executorSecurity.canAccessExecutorData(authentication)")
public @interface ExecutorAccess {
}

@Target({ElementType.METHOD, ElementType.TYPE})
@Retention(RetentionPolicy.RUNTIME)
@PreAuthorize("hasRole('EXECUTOR') and @executorSecurity.canAccessTransportation(authentication, #transportationId)")
public @interface TransportationAccess {
    String value() default "transportationId";
}
```

### 5. Создать BaseController для отчетов
```java
@RestController
@RequestMapping("/api/reports/executor")
@ExecutorAccess
public class ExecutorReportsBaseController {

    protected final ExecutorSecurityContext securityContext;
    protected final ExecutorAVRInsuranceReportService avrInsuranceService;
    protected final ExecutorVehicleUtilizationReportService vehicleUtilizationService;
    protected final ExecutorRoutesPeriodReportService routesPeriodService;
    protected final ExecutorDisputesReportService disputesService;

    public ExecutorReportsBaseController(
        ExecutorSecurityContext securityContext,
        ExecutorAVRInsuranceReportService avrInsuranceService,
        ExecutorVehicleUtilizationReportService vehicleUtilizationService,
        ExecutorRoutesPeriodReportService routesPeriodService,
        ExecutorDisputesReportService disputesService
    ) {
        this.securityContext = securityContext;
        this.avrInsuranceService = avrInsuranceService;
        this.vehicleUtilizationService = vehicleUtilizationService;
        this.routesPeriodService = routesPeriodService;
        this.disputesService = disputesService;
    }

    protected Long getCurrentExecutorId() {
        return securityContext.getCurrentExecutorId();
    }

    protected void validateTransportationAccess(Long transportationId) {
        if (!securityContext.canAccessTransportationData(transportationId)) {
            throw new AccessDeniedException("Access denied to transportation: " + transportationId);
        }
    }
}
```

### 6. Обновить контроллеры с безопасностью
```java
@RestController
@RequestMapping("/api/reports/executor")
@ExecutorAccess
public class ExecutorReportsController extends ExecutorReportsBaseController {

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
        Long executorId = getCurrentExecutorId();
        AVRInsuranceFilterDTO filter = new AVRInsuranceFilterDTO(routeNumber, customerId, documentStatus, dateFrom, dateTo);
        Pageable pageable = PageRequest.of(page, size);

        Page<AVRInsuranceReportDTO> result = avrInsuranceService.getAVRInsuranceReport(executorId, filter, pageable);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/avr-insurance/{routeId}/documents")
    @TransportationAccess
    public ResponseEntity<RouteDocumentsDTO> getRouteDocuments(@PathVariable Long routeId) {
        validateTransportationAccess(routeId);
        Long executorId = getCurrentExecutorId();

        RouteDocumentsDTO result = avrInsuranceService.getRouteDocuments(executorId, routeId);
        return ResponseEntity.ok(result);
    }
}
```

### 7. Создать обработку ошибок
```java
@Component
public class CustomAccessDeniedHandler implements AccessDeniedHandler {

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response,
                       AccessDeniedException accessDeniedException) throws IOException {
        response.setStatus(HttpStatus.FORBIDDEN.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);

        Map<String, Object> body = new HashMap<>();
        body.put("timestamp", LocalDateTime.now());
        body.put("status", HttpStatus.FORBIDDEN.value());
        body.put("error", "Forbidden");
        body.put("message", "Access denied: " + accessDeniedException.getMessage());
        body.put("path", request.getServletPath());

        new ObjectMapper().writeValue(response.getOutputStream(), body);
    }
}
```

### 8. Добавить валидацию в сервисы
```java
@Service
@Transactional(readOnly = true)
public class ExecutorAVRInsuranceReportService {

    public Page<AVRInsuranceReportDTO> getAVRInsuranceReport(
        Long executorId, AVRInsuranceFilterDTO filter, Pageable pageable
    ) {
        // Валидация что executorId принадлежит текущему пользователю
        if (!securityContext.isValidExecutorId(executorId)) {
            throw new AccessDeniedException("Invalid executor ID");
        }

        // Основная логика отчета
        return reportRepository.findByExecutorIdWithFilters(executorId, filter, pageable);
    }
}
```

### 9. Создать тесты безопасности
```java
@SpringBootTest
@AutoConfigureTestDatabase
class ExecutorReportsSecurityTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Test
    void whenUnauthorized_thenReturns401() {
        ResponseEntity<String> response = restTemplate.getForEntity(
            "/api/reports/executor/avr-insurance", String.class
        );
        assertEquals(HttpStatus.UNAUTHORIZED, response.getStatusCode());
    }

    @Test
    @WithMockUser(roles = {"CUSTOMER"})
    void whenCustomerAccess_thenReturns403() {
        ResponseEntity<String> response = restTemplate.getForEntity(
            "/api/reports/executor/avr-insurance", String.class
        );
        assertEquals(HttpStatus.FORBIDDEN, response.getStatusCode());
    }

    @Test
    @WithMockUser(roles = {"EXECUTOR"})
    void whenExecutorAccess_thenReturns200() {
        ResponseEntity<String> response = restTemplate.getForEntity(
            "/api/reports/executor/avr-insurance", String.class
        );
        assertEquals(HttpStatus.OK, response.getStatusCode());
    }
}
```

## Требования
- ✅ Все эндпоинты `/api/reports/executor/**` защищены
- ✅ Доступ только для пользователей с ролью EXECUTOR
- ✅ Валидация что пользователь принадлежит организации-перевозчику
- ✅ Проверка доступа к конкретным транспортным средствам
- ✅ Обработка ошибок безопасности
- ✅ Тесты безопасности

## Критерии приемки
- [ ] Неавторизованные пользователи получают 401
- [ ] Пользователи без роли EXECUTOR получают 403
- [ ] Перевозчики видят только свои данные
- [ ] Попытка доступа к чужим данным блокируется
- [ ] Все тесты безопасности проходят
- [ ] Логи безопасности работают корректно