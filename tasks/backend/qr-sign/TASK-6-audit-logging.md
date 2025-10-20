# TASK-6: Журналирование и аудит для SIEM

## Описание
Реализовать сервис журналирования всех событий подписания для отправки в SIEM систему по протоколу syslog RFC 5424.

## Приоритет
Medium

## Story Points
5

## Формат логов для SIEM

### Шаблон лог записи
```
{timestamp} egov-sign-service {key=value pairs} level={LEVEL} category={CATEGORY} description="{text}" result={RESULT}
```

### Пример успешного подписания
```
19:10:2025 14:23:45 egov-sign-service session_id=123 user_iin=931002451325 document_id=456 document_type=CONTRACT cert_serial=ABC123 signing_method=EGOV_QR level=INFO category=SIGN_DOCUMENT description="Document signed successfully" result=SUCCESS
```

### Пример ошибки валидации
```
19:10:2025 14:25:10 egov-sign-service session_id=789 user_iin=987654321098 document_id=101 document_type=INVOICE reason="Certificate revoked" level=ERROR category=SIGN_VALIDATION description="Signature validation failed" result=FAILED
```

### Пример OCSP запроса
```
19:10:2025 14:23:42 egov-sign-service session_id=123 cert_serial=ABC123 ocsp_status=good level=INFO category=OCSP_REQUEST description="OCSP validation successful" result=SUCCESS
```

## Сервис

### AuditLoggingService.java
```java
@Service
@Slf4j
public class AuditLoggingService {

    @Value("${logging.siem.enabled}")
    private boolean siemEnabled;

    // Логировать успешное подписание
    public void logSigningSuccess(Long sessionId, String iin, Long documentId,
                                    String documentType, String certSerial, String signingMethod) {
        Map<String, String> details = Map.of(
            "session_id", sessionId.toString(),
            "user_iin", iin,
            "document_id", documentId.toString(),
            "document_type", documentType,
            "cert_serial", certSerial,
            "signing_method", signingMethod
        );

        String logEntry = buildLogEntry(
            "INFO",
            "SIGN_DOCUMENT",
            "Document signed successfully",
            "SUCCESS",
            details
        );

        log.info(logEntry);
        sendToSIEM(logEntry);
    }

    // Логировать ошибку валидации
    public void logSigningFailure(Long sessionId, String iin, Long documentId,
                                    String documentType, String reason) {
        Map<String, String> details = Map.of(
            "session_id", sessionId.toString(),
            "user_iin", iin != null ? iin : "unknown",
            "document_id", documentId.toString(),
            "document_type", documentType,
            "reason", reason
        );

        String logEntry = buildLogEntry(
            "ERROR",
            "SIGN_VALIDATION",
            "Signature validation failed",
            "FAILED",
            details
        );

        log.error(logEntry);
        sendToSIEM(logEntry);
    }

    // Логировать OCSP запрос
    public void logOCSPRequest(String certSerial, String ocspStatus) {
        Map<String, String> details = Map.of(
            "cert_serial", certSerial,
            "ocsp_status", ocspStatus
        );

        String logEntry = buildLogEntry(
            "INFO",
            "OCSP_REQUEST",
            "OCSP validation",
            ocspStatus.equals("good") ? "SUCCESS" : "FAILED",
            details
        );

        log.info(logEntry);
        sendToSIEM(logEntry);
    }

    // Логировать создание сессии
    public void logSessionCreated(Long sessionId, String documentType, Long documentId, String signingMethod) {
        Map<String, String> details = Map.of(
            "session_id", sessionId.toString(),
            "document_type", documentType,
            "document_id", documentId.toString(),
            "signing_method", signingMethod
        );

        String logEntry = buildLogEntry(
            "INFO",
            "SESSION_CREATED",
            "Signing session created",
            "SUCCESS",
            details
        );

        log.info(logEntry);
        sendToSIEM(logEntry);
    }

    // Логировать истечение срока сессии
    public void logSessionExpired(Long sessionId) {
        Map<String, String> details = Map.of(
            "session_id", sessionId.toString()
        );

        String logEntry = buildLogEntry(
            "WARN",
            "SESSION_EXPIRED",
            "Signing session expired",
            "EXPIRED",
            details
        );

        log.warn(logEntry);
        sendToSIEM(logEntry);
    }

    // Логировать ошибку CRL
    public void logCRLCheckFailed(String certSerial, String error) {
        Map<String, String> details = Map.of(
            "cert_serial", certSerial,
            "error", error
        );

        String logEntry = buildLogEntry(
            "ERROR",
            "CRL_CHECK",
            "CRL check failed",
            "FAILED",
            details
        );

        log.error(logEntry);
        sendToSIEM(logEntry);
    }

    // Построить лог запись
    private String buildLogEntry(String level, String category, String description,
                                   String result, Map<String, String> details) {
        LocalDateTime now = LocalDateTime.now();
        String timestamp = now.format(DateTimeFormatter.ofPattern("dd:MM:yyyy HH:mm:ss"));

        StringBuilder sb = new StringBuilder();
        sb.append(timestamp).append(" ");
        sb.append("egov-sign-service").append(" ");

        // Добавить все детали
        details.forEach((key, value) -> {
            sb.append(key).append("=").append(sanitize(value)).append(" ");
        });

        // Добавить метаданные
        sb.append("level=").append(level).append(" ");
        sb.append("category=").append(category).append(" ");
        sb.append("description=\"").append(sanitize(description)).append("\" ");
        sb.append("result=").append(result);

        return sb.toString();
    }

    // Очистить от опасных символов
    private String sanitize(String value) {
        if (value == null) return "null";
        return value.replaceAll("[\n\r\t]", " ")
                    .replaceAll("\"", "'");
    }

    // Отправить в SIEM
    private void sendToSIEM(String logEntry) {
        if (!siemEnabled) {
            return;
        }

        // Отправка через Logback Syslog Appender
        // или напрямую через сокет
        Logger siemLogger = LoggerFactory.getLogger("SIEM");
        siemLogger.info(logEntry);
    }
}
```

## Конфигурация Logback

### logback-spring.xml
```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>

    <!-- Console Appender -->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n</pattern>
        </encoder>
    </appender>

    <!-- File Appender для аудита -->
    <appender name="AUDIT_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>logs/audit.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <fileNamePattern>logs/audit-%d{yyyy-MM-dd}.log</fileNamePattern>
            <maxHistory>90</maxHistory>
            <totalSizeCap>10GB</totalSizeCap>
        </rollingPolicy>
        <encoder>
            <pattern>%msg%n</pattern>
        </encoder>
    </appender>

    <!-- SIEM Syslog Appender -->
    <appender name="SIEM" class="ch.qos.logback.classic.net.SyslogAppender">
        <syslogHost>${SIEM_HOST:-localhost}</syslogHost>
        <port>${SIEM_PORT:-514}</port>
        <facility>USER</facility>
        <suffixPattern>%msg</suffixPattern>
    </appender>

    <!-- Logger для AuditLoggingService -->
    <logger name="kz.coube.application.service.AuditLoggingService" level="INFO" additivity="false">
        <appender-ref ref="AUDIT_FILE" />
        <appender-ref ref="CONSOLE" />
    </logger>

    <!-- Logger для SIEM отправки -->
    <logger name="SIEM" level="INFO" additivity="false">
        <appender-ref ref="SIEM" />
        <appender-ref ref="AUDIT_FILE" />
    </logger>

    <!-- Root logger -->
    <root level="INFO">
        <appender-ref ref="CONSOLE" />
    </root>

</configuration>
```

## Конфигурация приложения

### application.yml
```yaml
logging:
  siem:
    enabled: ${SIEM_ENABLED:false}
    host: ${SIEM_HOST:localhost}
    port: ${SIEM_PORT:514}

  file:
    name: logs/coube-backend.log
    max-size: 100MB
    max-history: 30

  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"
    file: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"

  level:
    kz.coube.application.service.AuditLoggingService: INFO
    SIEM: INFO
```

## Scheduled задача для очистки старых сессий

### SessionCleanupScheduler.java
```java
@Component
@EnableScheduling
public class SessionCleanupScheduler {

    @Autowired
    private EgovSigningSessionRepository sessionRepository;

    @Autowired
    private AuditLoggingService auditService;

    // Каждый час проверять истекшие сессии
    @Scheduled(cron = "0 0 * * * *")
    public void cleanupExpiredSessions() {
        LocalDateTime now = LocalDateTime.now();

        List<EgovSigningSession> expiredSessions = sessionRepository
            .findByStatusAndExpiresAtBefore("PENDING", now);

        for (EgovSigningSession session : expiredSessions) {
            session.setStatus("EXPIRED");
            sessionRepository.save(session);

            auditService.logSessionExpired(session.getId());
        }

        if (!expiredSessions.isEmpty()) {
            log.info("Marked {} sessions as expired", expiredSessions.size());
        }
    }
}
```

## Repository расширение

### EgovSigningSessionRepository.java
```java
public interface EgovSigningSessionRepository extends JpaRepository<EgovSigningSession, Long> {

    List<EgovSigningSession> findByStatusAndExpiresAtBefore(String status, LocalDateTime expiresAt);

    @Query("SELECT s FROM EgovSigningSession s WHERE s.status = 'PENDING' AND s.expiresAt < :now")
    List<EgovSigningSession> findExpiredPendingSessions(@Param("now") LocalDateTime now);
}
```

## Метрики (опционально)

### SigningMetricsService.java
```java
@Service
public class SigningMetricsService {

    private final MeterRegistry meterRegistry;

    public SigningMetricsService(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }

    public void recordSigningSuccess(String documentType) {
        meterRegistry.counter("egov.signing.success",
            "document_type", documentType
        ).increment();
    }

    public void recordSigningFailure(String documentType, String reason) {
        meterRegistry.counter("egov.signing.failure",
            "document_type", documentType,
            "reason", reason
        ).increment();
    }

    public void recordOCSPRequest(String status) {
        meterRegistry.counter("egov.signing.ocsp.request",
            "status", status
        ).increment();
    }
}
```

## Тесты

### AuditLoggingServiceTest.java
```java
@SpringBootTest
class AuditLoggingServiceTest {

    @Autowired
    private AuditLoggingService auditService;

    @Test
    void logSigningSuccess_CreatesCorrectLogEntry() {
        // Arrange
        Long sessionId = 123L;
        String iin = "931002451325";
        Long documentId = 456L;
        String docType = "CONTRACT";
        String certSerial = "ABC123";

        // Act
        auditService.logSigningSuccess(sessionId, iin, documentId, docType, certSerial, "EGOV_QR");

        // Assert - проверить что лог создан
        // Можно использовать ListAppender для захвата логов в тестах
    }

    @Test
    void buildLogEntry_ContainsAllRequiredFields() {
        // Тест формата лога
    }
}
```

## Зависимости в pom.xml

```xml
<!-- Logback Syslog -->
<dependency>
    <groupId>ch.qos.logback</groupId>
    <artifactId>logback-classic</artifactId>
</dependency>

<!-- Micrometer для метрик (опционально) -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-core</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

## Критерии приемки
- ✅ Создан AuditLoggingService со всеми методами логирования
- ✅ Логи в формате для SIEM (syslog RFC 5424)
- ✅ Настроен Logback с SIEM appender
- ✅ Логируются все критичные события:
  - Создание сессии
  - Успешное подписание
  - Ошибки валидации
  - OCSP/CRL запросы
  - Истечение сессии
- ✅ Scheduled задача для очистки истекших сессий
- ✅ Конфигурация через application.yml
- ✅ Метрики подписания (опционально)
- ✅ Unit тесты

## Зависимости
- TASK-1 (database schema)
- TASK-4 (signature validation)

## Связанная документация
- [Flow диаграмма 9](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#9-журналирование-и-аудит)
- [Smart Bridge требования](../../business_analysis/converted/QR%20sign/Smart%20Bridge.md) (раздел "Требования по информационной безопасности")
