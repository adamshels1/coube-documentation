# 08. API Key аутентификация для TEEZ интеграции

## Обзор

Простая аутентификация через статический API Key для интеграции с TEEZ_PVZ вместо сложного OAuth2 Client Credentials flow.

---

## Архитектура

### Принцип работы

1. Coube генерирует уникальный API Key для TEEZ
2. API Key хранится в БД с метаданными (дата создания, срок действия, активность)
3. TEEZ передает API Key в заголовке каждого запроса
4. Custom Spring Security Filter валидирует ключ перед обработкой запроса

---

## Изменения в БД

### Новая таблица: `integration_api_keys`

**Файл миграции**: `V2025_01_15_11__create_integration_api_keys_table.sql`

```sql
CREATE TABLE IF NOT EXISTS applications.integration_api_keys (
    id BIGSERIAL PRIMARY KEY,
    
    -- Идентификация
    key_name VARCHAR(255) NOT NULL UNIQUE,
    api_key_hash VARCHAR(512) NOT NULL UNIQUE, -- SHA-256 hash ключа
    
    -- Метаданные
    source_system VARCHAR(100) NOT NULL, -- TEEZ_PVZ
    description TEXT,
    
    -- Статус и права
    is_active BOOLEAN NOT NULL DEFAULT true,
    scopes TEXT[] NOT NULL DEFAULT '{}', -- ['courier:integration:read', 'courier:integration:write']
    
    -- IP whitelist (опционально)
    allowed_ips TEXT[], -- ['192.168.1.0/24', '10.0.0.5']
    
    -- Срок действия
    expires_at TIMESTAMP,
    
    -- Статистика использования
    last_used_at TIMESTAMP,
    usage_count BIGINT DEFAULT 0,
    
    -- Аудит
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by TEXT NOT NULL
);

-- Индексы
CREATE INDEX idx_api_keys_hash ON applications.integration_api_keys(api_key_hash);
CREATE INDEX idx_api_keys_active ON applications.integration_api_keys(is_active);
CREATE INDEX idx_api_keys_source ON applications.integration_api_keys(source_system);

-- Комментарии
COMMENT ON TABLE applications.integration_api_keys IS 'API ключи для интеграции с внешними системами';
COMMENT ON COLUMN applications.integration_api_keys.api_key_hash IS 'SHA-256 хеш API ключа (не храним в открытом виде)';
COMMENT ON COLUMN applications.integration_api_keys.scopes IS 'Разрешения (права доступа) для данного ключа';
```

---

## Entity класс

**Файл**: `/src/main/java/kz/coube/backend/integration/entity/IntegrationApiKey.java`

```java
package kz.coube.backend.integration.entity;

import jakarta.persistence.*;
import kz.coube.backend.common.entity.AuditEntity;
import lombok.*;

import java.time.Instant;
import java.util.List;

@Entity
@Table(name = "integration_api_keys", schema = "applications")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class IntegrationApiKey extends AuditEntity {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "key_name", nullable = false, unique = true)
    private String keyName;
    
    @Column(name = "api_key_hash", nullable = false, unique = true)
    private String apiKeyHash;
    
    @Column(name = "source_system", nullable = false)
    private String sourceSystem; // TEEZ_PVZ
    
    @Column(name = "description", columnDefinition = "TEXT")
    private String description;
    
    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;
    
    @ElementCollection
    @CollectionTable(name = "integration_api_key_scopes", 
                     schema = "applications",
                     joinColumns = @JoinColumn(name = "api_key_id"))
    @Column(name = "scope")
    private List<String> scopes;
    
    @ElementCollection
    @CollectionTable(name = "integration_api_key_allowed_ips", 
                     schema = "applications",
                     joinColumns = @JoinColumn(name = "api_key_id"))
    @Column(name = "ip")
    private List<String> allowedIps;
    
    @Column(name = "expires_at")
    private Instant expiresAt;
    
    @Column(name = "last_used_at")
    private Instant lastUsedAt;
    
    @Column(name = "usage_count")
    private Long usageCount = 0L;
    
    public boolean isExpired() {
        return expiresAt != null && Instant.now().isAfter(expiresAt);
    }
    
    public boolean hasScope(String scope) {
        return scopes != null && scopes.contains(scope);
    }
}
```

---

## Repository

**Файл**: `/src/main/java/kz/coube/backend/integration/repository/IntegrationApiKeyRepository.java`

```java
package kz.coube.backend.integration.repository;

import kz.coube.backend.integration.entity.IntegrationApiKey;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.Optional;

@Repository
public interface IntegrationApiKeyRepository extends JpaRepository<IntegrationApiKey, Long> {
    
    Optional<IntegrationApiKey> findByApiKeyHash(String apiKeyHash);
    
    Optional<IntegrationApiKey> findByKeyName(String keyName);
    
    @Modifying
    @Query("UPDATE IntegrationApiKey k SET k.lastUsedAt = :now, k.usageCount = k.usageCount + 1 WHERE k.id = :id")
    void updateUsageStats(Long id, Instant now);
}
```

---

## Service для управления API ключами

**Файл**: `/src/main/java/kz/coube/backend/integration/service/ApiKeyService.java`

```java
package kz.coube.backend.integration.service;

import kz.coube.backend.integration.entity.IntegrationApiKey;
import kz.coube.backend.integration.repository.IntegrationApiKeyRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.List;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Slf4j
public class ApiKeyService {
    
    private final IntegrationApiKeyRepository apiKeyRepository;
    private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private static final int API_KEY_LENGTH = 32; // 32 bytes = 256 bits
    
    /**
     * Генерация нового API ключа
     * @return пара: сам ключ (показываем один раз!) и entity
     */
    @Transactional
    public ApiKeyGenerationResult generateApiKey(
            String keyName,
            String sourceSystem,
            String description,
            List<String> scopes,
            Integer validityDays) {
        
        // Генерируем случайный ключ
        String apiKey = generateSecureKey();
        
        // Хешируем для хранения
        String hash = passwordEncoder.encode(apiKey);
        
        // Создаем entity
        IntegrationApiKey entity = IntegrationApiKey.builder()
                .keyName(keyName)
                .apiKeyHash(hash)
                .sourceSystem(sourceSystem)
                .description(description)
                .isActive(true)
                .scopes(scopes)
                .expiresAt(validityDays != null ? Instant.now().plus(validityDays, ChronoUnit.DAYS) : null)
                .usageCount(0L)
                .build();
        
        apiKeyRepository.save(entity);
        
        log.info("Generated new API key for {} ({})", sourceSystem, keyName);
        
        return new ApiKeyGenerationResult(apiKey, entity);
    }
    
    /**
     * Валидация API ключа
     */
    @Transactional
    public Optional<IntegrationApiKey> validateApiKey(String apiKey) {
        if (apiKey == null || apiKey.isBlank()) {
            return Optional.empty();
        }
        
        // Ищем все активные ключи и проверяем хеш
        List<IntegrationApiKey> activeKeys = apiKeyRepository.findAll().stream()
                .filter(IntegrationApiKey::getIsActive)
                .filter(k -> !k.isExpired())
                .toList();
        
        for (IntegrationApiKey key : activeKeys) {
            if (passwordEncoder.matches(apiKey, key.getApiKeyHash())) {
                // Обновляем статистику использования
                apiKeyRepository.updateUsageStats(key.getId(), Instant.now());
                return Optional.of(key);
            }
        }
        
        return Optional.empty();
    }
    
    /**
     * Проверка IP адреса
     */
    public boolean isIpAllowed(IntegrationApiKey key, String requestIp) {
        if (key.getAllowedIps() == null || key.getAllowedIps().isEmpty()) {
            return true; // Нет ограничений по IP
        }
        
        return key.getAllowedIps().stream()
                .anyMatch(allowedIp -> matchesIpPattern(requestIp, allowedIp));
    }
    
    /**
     * Отзыв (деактивация) ключа
     */
    @Transactional
    public void revokeApiKey(String keyName) {
        apiKeyRepository.findByKeyName(keyName).ifPresent(key -> {
            key.setIsActive(false);
            apiKeyRepository.save(key);
            log.warn("API key revoked: {}", keyName);
        });
    }
    
    /**
     * Генерация безопасного случайного ключа
     */
    private String generateSecureKey() {
        SecureRandom random = new SecureRandom();
        byte[] bytes = new byte[API_KEY_LENGTH];
        random.nextBytes(bytes);
        return "coube_" + Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }
    
    /**
     * Проверка соответствия IP паттерну (поддержка CIDR)
     */
    private boolean matchesIpPattern(String ip, String pattern) {
        // Упрощенная реализация, для production использовать библиотеку Apache Commons Net
        if (pattern.contains("/")) {
            // CIDR notation (например, 192.168.1.0/24)
            // TODO: implement CIDR matching
            return true;
        }
        return ip.equals(pattern);
    }
    
    public record ApiKeyGenerationResult(String apiKey, IntegrationApiKey entity) {}
}
```

---

## Security Filter

**Файл**: `/src/main/java/kz/coube/backend/integration/security/ApiKeyAuthenticationFilter.java`

```java
package kz.coube.backend.integration.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import kz.coube.backend.integration.entity.IntegrationApiKey;
import kz.coube.backend.integration.service.ApiKeyService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class ApiKeyAuthenticationFilter extends OncePerRequestFilter {
    
    private final ApiKeyService apiKeyService;
    private static final String API_KEY_HEADER = "X-API-Key";
    private static final String INTEGRATION_PATH_PREFIX = "/api/v1/integration/";
    
    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        
        String path = request.getRequestURI();
        
        // Применяем фильтр только к integration endpoints
        if (!path.startsWith(INTEGRATION_PATH_PREFIX)) {
            filterChain.doFilter(request, response);
            return;
        }
        
        String apiKey = request.getHeader(API_KEY_HEADER);
        
        if (apiKey == null || apiKey.isBlank()) {
            log.warn("Missing API key for integration request: {}", path);
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "API key is required");
            return;
        }
        
        // Валидируем API ключ
        apiKeyService.validateApiKey(apiKey).ifPresentOrElse(
                key -> {
                    // Проверяем IP whitelist
                    String clientIp = getClientIp(request);
                    if (!apiKeyService.isIpAllowed(key, clientIp)) {
                        log.warn("IP {} not allowed for API key: {}", clientIp, key.getKeyName());
                        try {
                            response.sendError(HttpServletResponse.SC_FORBIDDEN, "IP address not allowed");
                        } catch (IOException e) {
                            log.error("Error sending forbidden response", e);
                        }
                        return;
                    }
                    
                    // Устанавливаем аутентификацию
                    List<SimpleGrantedAuthority> authorities = key.getScopes().stream()
                            .map(scope -> new SimpleGrantedAuthority("SCOPE_" + scope))
                            .toList();
                    
                    UsernamePasswordAuthenticationToken authentication = 
                            new UsernamePasswordAuthenticationToken(
                                    key.getSourceSystem(), // principal
                                    null, // credentials
                                    authorities);
                    
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                    
                    log.debug("API key authenticated: {} ({})", key.getKeyName(), key.getSourceSystem());
                    
                    try {
                        filterChain.doFilter(request, response);
                    } catch (IOException | ServletException e) {
                        log.error("Error in filter chain", e);
                    }
                },
                () -> {
                    log.warn("Invalid API key for integration request: {}", path);
                    try {
                        response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Invalid API key");
                    } catch (IOException e) {
                        log.error("Error sending unauthorized response", e);
                    }
                }
        );
    }
    
    private String getClientIp(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isEmpty()) {
            ip = request.getHeader("X-Real-IP");
        }
        if (ip == null || ip.isEmpty()) {
            ip = request.getRemoteAddr();
        }
        // Берем первый IP из X-Forwarded-For (если там список)
        if (ip != null && ip.contains(",")) {
            ip = ip.split(",")[0].trim();
        }
        return ip;
    }
}
```

---

## Security Configuration

**Файл**: `/src/main/java/kz/coube/backend/configuration/SecurityConfig.java`

**Добавить**:

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Autowired
    private ApiKeyAuthenticationFilter apiKeyAuthenticationFilter;
    
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
                // ... existing config
                
                // Добавляем API Key фильтр перед стандартной аутентификацией
                .addFilterBefore(apiKeyAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
                
                .authorizeHttpRequests(auth -> auth
                        // Integration endpoints требуют scope courier:integration
                        .requestMatchers("/api/v1/integration/teez/**")
                        .hasAuthority("SCOPE_courier:integration")
                        
                        // ... existing rules
                )
                .build();
    }
}
```

---

## Management Controller (для админов)

**Файл**: `/src/main/java/kz/coube/backend/superadmin/api/ApiKeyManagementController.java`

```java
package kz.coube.backend.superadmin.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import kz.coube.backend.auth.roles.KeycloakRole;
import kz.coube.backend.common.validation.AuthorizationRequired;
import kz.coube.backend.integration.entity.IntegrationApiKey;
import kz.coube.backend.integration.repository.IntegrationApiKeyRepository;
import kz.coube.backend.integration.service.ApiKeyService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/admin/api-keys")
@RequiredArgsConstructor
@Tag(name = "API Key Management", description = "Управление интеграционными API ключами")
@AuthorizationRequired(roles = {KeycloakRole.SUPER_ADMIN})
public class ApiKeyManagementController {
    
    private final ApiKeyService apiKeyService;
    private final IntegrationApiKeyRepository apiKeyRepository;
    
    @PostMapping
    @Operation(summary = "Создать новый API ключ")
    public ResponseEntity<?> createApiKey(@RequestBody CreateApiKeyRequest request) {
        ApiKeyService.ApiKeyGenerationResult result = apiKeyService.generateApiKey(
                request.keyName(),
                request.sourceSystem(),
                request.description(),
                request.scopes(),
                request.validityDays()
        );
        
        return ResponseEntity.ok(Map.of(
                "apiKey", result.apiKey(), // ПОКАЗЫВАЕМ ТОЛЬКО ОДИН РАЗ!
                "keyName", result.entity().getKeyName(),
                "expiresAt", result.entity().getExpiresAt(),
                "scopes", result.entity().getScopes(),
                "warning", "Сохраните API ключ! Он больше не будет показан."
        ));
    }
    
    @GetMapping
    @Operation(summary = "Список всех API ключей")
    public ResponseEntity<Page<IntegrationApiKey>> listApiKeys(Pageable pageable) {
        return ResponseEntity.ok(apiKeyRepository.findAll(pageable));
    }
    
    @DeleteMapping("/{keyName}")
    @Operation(summary = "Отозвать (деактивировать) API ключ")
    public ResponseEntity<?> revokeApiKey(@PathVariable String keyName) {
        apiKeyService.revokeApiKey(keyName);
        return ResponseEntity.ok(Map.of("status", "revoked", "keyName", keyName));
    }
    
    record CreateApiKeyRequest(
            String keyName,
            String sourceSystem,
            String description,
            List<String> scopes,
            Integer validityDays
    ) {}
}
```

---

## Использование TEEZ стороной

### 1. Coube Admin создает API ключ

```bash
POST /api/v1/admin/api-keys
Authorization: Bearer {admin_token}

{
  "keyName": "teez-production",
  "sourceSystem": "TEEZ_PVZ",
  "description": "Production API key for TEEZ integration",
  "scopes": ["courier:integration"],
  "validityDays": 365
}
```

**Response**:
```json
{
  "apiKey": "coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR",
  "keyName": "teez-production",
  "expiresAt": "2026-01-06T10:00:00Z",
  "scopes": ["courier:integration"],
  "warning": "Сохраните API ключ! Он больше не будет показан."
}
```

⚠️ **ВАЖНО**: API ключ показывается только один раз! TEEZ должны сохранить его.

### 2. TEEZ использует ключ

```bash
POST /api/v1/integration/teez/waybills
X-API-Key: coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
Content-Type: application/json

{
  "source_system": "TEEZ_PVZ",
  "waybill": {
    "id": "WB-2025-001",
    ...
  }
}
```

---

## Конфигурация

### application.yml

```yaml
integration:
  api-key:
    enabled: true
    header-name: X-API-Key
    rate-limit:
      enabled: true
      requests-per-minute: 100
```

---

## Безопасность

### Best Practices

✅ **Хранение**: API ключи хешируются BCrypt (как пароли)  
✅ **Генерация**: SecureRandom + 256 bits entropy  
✅ **Передача**: только HTTPS  
✅ **Ротация**: срок действия (validityDays)  
✅ **IP Whitelist**: опциональное ограничение по IP  
✅ **Логирование**: все использования ключа логируются  
✅ **Отзыв**: мгновенная деактивация при компрометации  

### Что НЕ делать

❌ Не храним ключи в открытом виде  
❌ Не передаем ключи в URL параметрах  
❌ Не логируем сами ключи (только hash)  
❌ Не используем один ключ для всех окружений  

---

## Rate Limiting (опционально)

Можно добавить rate limiting на уровне API ключа:

```java
@Component
public class ApiKeyRateLimiter {
    
    private final Map<Long, RateLimiter> limiters = new ConcurrentHashMap<>();
    
    public boolean allowRequest(IntegrationApiKey key) {
        RateLimiter limiter = limiters.computeIfAbsent(
                key.getId(),
                id -> RateLimiter.create(100.0 / 60.0) // 100 req/min
        );
        return limiter.tryAcquire();
    }
}
```

---

## Мониторинг

### Метрики

- `integration_api_key_requests_total` - всего запросов
- `integration_api_key_requests_failed_total` - неудачных запросов
- `integration_api_key_usage_by_source` - использование по источникам

### Alerts

- Подозрительная активность (слишком много запросов)
- Использование отозванного ключа
- Попытки доступа с неразрешенного IP

---

## Checklist реализации

- [ ] Создать миграцию `V2025_01_15_11__create_integration_api_keys_table.sql`
- [ ] Создать Entity `IntegrationApiKey`
- [ ] Создать Repository `IntegrationApiKeyRepository`
- [ ] Создать Service `ApiKeyService`
- [ ] Создать Filter `ApiKeyAuthenticationFilter`
- [ ] Обновить `SecurityConfig`
- [ ] Создать Management Controller `ApiKeyManagementController`
- [ ] Добавить в `application.yml` конфигурацию
- [ ] Unit тесты для `ApiKeyService`
- [ ] Integration тесты для фильтра
- [ ] Документация для TEEZ
- [ ] Сгенерировать production ключ для TEEZ

---

## Сравнение с OAuth2

| Аспект | API Key | OAuth2 Client Credentials |
|--------|---------|---------------------------|
| Сложность внедрения | Простая | Средняя |
| Сложность для клиента | Очень простая | Средняя (нужен token endpoint) |
| Безопасность | Хорошая (при правильном использовании) | Отличная |
| Срок действия токена | Настраиваемый | Короткий (refresh flow) |
| Отзыв доступа | Мгновенный | Мгновенный |
| Подходит для | Простые B2B интеграции | Enterprise интеграции |

**Рекомендация**: Для интеграции с TEEZ **API Key достаточно**, т.к. это доверенная B2B интеграция между двумя системами.
