# 04. API Key аутентификация для MVP (упрощенная версия)

## 🎯 Упрощенный подход для MVP

Для быстрой реализации MVP используем **максимально простую** версию API Key аутентификации:

### ❌ Что НЕ включаем в MVP:
- Таблица `integration_api_keys` в БД
- Entity, Repository, Service для управления ключами
- Admin UI для генерации ключей
- IP whitelist
- Rate limiting
- Scopes и права доступа
- Статистика использования

### ✅ Что включаем в MVP:
- **Статический API Key** в конфигурации
- **Простой Security Filter** для проверки ключа
- **Базовое логирование** в существующую таблицу `courier_integration_log`

**Экономия времени**: 2-3 дня работы

---

## Реализация для MVP

### 1. Конфигурация (application.yml)

```yaml
courier:
  integration:
    # Статический API ключ (меняется через конфиг, без БД)
    api-key: ${COURIER_API_KEY:test-api-key-change-in-production}
    
    teez:
      enabled: true
      api-url: ${TEEZ_API_URL:https://teez-api.example.com}
      endpoint: /api/waybill/results
```

**В production** задаем через environment variable:
```bash
export COURIER_API_KEY="coube_prod_secure_key_xJ3mK9pLqR8sT2vW5yZ7aB"
```

### 2. Config Properties класс

**Файл**: `/src/main/java/kz/coube/backend/courier/config/CourierIntegrationProperties.java`

```java
package kz.coube.backend.courier.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "courier.integration")
@Data
public class CourierIntegrationProperties {
    
    /**
     * Статический API ключ для интеграций
     */
    private String apiKey;
    
    /**
     * Настройки TEEZ интеграции
     */
    private TeezConfig teez = new TeezConfig();
    
    @Data
    public static class TeezConfig {
        private boolean enabled = true;
        private String apiUrl;
        private String endpoint;
    }
}
```

### 3. Простой Security Filter

**Файл**: `/src/main/java/kz/coube/backend/courier/security/CourierApiKeyFilter.java`

```java
package kz.coube.backend.courier.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import kz.coube.backend.courier.config.CourierIntegrationProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Упрощенный фильтр для проверки API ключа
 * MVP версия: проверяет только статический ключ из конфигурации
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class CourierApiKeyFilter extends OncePerRequestFilter {
    
    private final CourierIntegrationProperties properties;
    
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
        
        // Проверка наличия ключа
        if (apiKey == null || apiKey.isBlank()) {
            log.warn("Missing API key for integration request: {} from IP: {}", 
                     path, getClientIp(request));
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED, 
                             "API key is required. Please provide X-API-Key header.");
            return;
        }
        
        // Проверка корректности ключа (простое сравнение)
        if (!properties.getApiKey().equals(apiKey)) {
            log.warn("Invalid API key for integration request: {} from IP: {}", 
                     path, getClientIp(request));
            response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Invalid API key");
            return;
        }
        
        // Устанавливаем аутентификацию для Spring Security
        List<SimpleGrantedAuthority> authorities = List.of(
            new SimpleGrantedAuthority("ROLE_INTEGRATION"),
            new SimpleGrantedAuthority("SCOPE_courier:integration")
        );
        
        UsernamePasswordAuthenticationToken authentication = 
                new UsernamePasswordAuthenticationToken(
                        "INTEGRATION_API", // principal
                        null, // credentials
                        authorities);
        
        SecurityContextHolder.getContext().setAuthentication(authentication);
        
        log.debug("API key authenticated successfully for: {}", path);
        
        // Продолжаем цепочку фильтров
        filterChain.doFilter(request, response);
    }
    
    /**
     * Получение IP адреса клиента (учитывает proxy)
     */
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

### 4. Security Configuration

**Обновить**: `/src/main/java/kz/coube/backend/configuration/SecurityConfig.java`

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    @Autowired
    private CourierApiKeyFilter courierApiKeyFilter;
    
    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
                // ... existing config
                
                // Добавляем наш фильтр перед стандартной аутентификацией
                .addFilterBefore(courierApiKeyFilter, UsernamePasswordAuthenticationFilter.class)
                
                .authorizeHttpRequests(auth -> auth
                        // Integration endpoints требуют наш custom authority
                        .requestMatchers("/api/v1/integration/**")
                        .hasAuthority("SCOPE_courier:integration")
                        
                        // ... existing rules
                )
                .build();
    }
}
```

---

## Использование

### 1. Генерация API ключа (вручную)

Для production генерируем безопасный ключ:

```bash
# Генерация случайного ключа (32 байта, base64)
openssl rand -base64 32

# Результат например:
# xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR=

# Добавляем префикс для удобства
# coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
```

### 2. Передача ключа TEEZ команде

Отправляем ключ TEEZ команде через защищенный канал (например, 1Password, LastPass, или лично).

⚠️ **ВАЖНО**: Ключ передается один раз и не хранится в открытом виде в репозитории!

### 3. TEEZ использует ключ

```bash
curl -X POST "https://api.coube.kz/api/v1/integration/waybills" \
  -H "X-API-Key: coube_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR" \
  -H "Content-Type: application/json" \
  -d '{
    "source_system": "TEEZ_PVZ",
    "waybill": {
      "id": "WB-2025-001",
      ...
    }
  }'
```

---

## Deployment

### Development

```yaml
# application-dev.yml
courier:
  integration:
    api-key: dev-test-key-not-for-production
```

### Staging

```bash
# Environment variable
export COURIER_API_KEY="staging_key_abc123xyz"
```

### Production

```bash
# Environment variable (в Kubernetes Secret, AWS Secrets Manager, etc.)
export COURIER_API_KEY="coube_prod_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR"
```

**Kubernetes Secret пример**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: courier-api-key
type: Opaque
stringData:
  api-key: coube_prod_xJ3mK9pLqR8sT2vW5yZ7aB1cD4eF6gH9iJ0kL3mN5oP8qR
```

**Deployment использует**:
```yaml
env:
  - name: COURIER_API_KEY
    valueFrom:
      secretKeyRef:
        name: courier-api-key
        key: api-key
```

---

## Логирование

Все запросы с API ключом автоматически логируются в существующую таблицу `courier_integration_log`.

В `CourierIntegrationService` уже есть метод `logIntegration()`, который записывает:
- IP адрес клиента
- Время запроса
- Payload
- Статус (success/error)

**Не нужно** создавать отдельную таблицу для API ключей!

---

## Мониторинг

### Основные метрики для мониторинга:

1. **Количество запросов с невалидным ключом**
   ```java
   // В CourierApiKeyFilter
   log.warn("Invalid API key..."); // → алерт в мониторинге
   ```

2. **Количество успешных запросов**
   ```java
   // В CourierIntegrationLog
   status = "success"
   ```

3. **IP адреса запросов**
   ```sql
   -- Проверить в БД какие IP используют API
   SELECT request_payload->>'ip', COUNT(*) 
   FROM applications.courier_integration_log 
   WHERE created_at > NOW() - INTERVAL '1 day'
   GROUP BY request_payload->>'ip';
   ```

---

## Смена API ключа

Если ключ скомпрометирован:

### 1. Генерируем новый ключ
```bash
openssl rand -base64 32
# Новый ключ: coube_NEW_yZ9kL2pM4nQ7rS8tV1wX3xY5zA6bC8dE0fG2hI4jK6lM8nO
```

### 2. Обновляем конфигурацию
```bash
# В production environment
kubectl set env deployment/coube-backend \
  COURIER_API_KEY="coube_NEW_yZ9kL2pM4nQ7rS8tV1wX3xY5zA6bC8dE0fG2hI4jK6lM8nO"

# Перезапускаем приложение
kubectl rollout restart deployment/coube-backend
```

### 3. Уведомляем TEEZ о новом ключе
- Даем переходный период (например, 24 часа)
- TEEZ обновляют ключ на своей стороне
- Старый ключ перестает работать

---

## Безопасность

### ✅ Что делаем:
- Используем HTTPS (TLS) для всех запросов
- Ключ в заголовке (не в URL!)
- Ключ в environment variable (не в коде!)
- Логируем все попытки доступа
- Периодическая ротация ключа (раз в год)

### ❌ Что НЕ делаем (в MVP):
- Не храним в БД (упрощение!)
- Не хешируем (простое сравнение строк)
- Не ограничиваем по IP
- Не делаем rate limiting
- Не делаем UI для управления

---

## Миграция на полную версию (после MVP)

Когда понадобится более сложная система (несколько маркетплейсов, разные ключи, права доступа):

### Шаг 1: Создать таблицу
```sql
CREATE TABLE applications.integration_api_keys (
  id BIGSERIAL PRIMARY KEY,
  key_name VARCHAR(255) NOT NULL UNIQUE,
  api_key_hash VARCHAR(512) NOT NULL UNIQUE,
  source_system VARCHAR(100) NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Шаг 2: Мигрировать текущий ключ
```sql
INSERT INTO applications.integration_api_keys 
  (key_name, api_key_hash, source_system) 
VALUES 
  ('teez-production', 
   -- BCrypt hash текущего ключа
   '$2a$10$...',
   'TEEZ_PVZ');
```

### Шаг 3: Обновить Filter
Использовать полную версию `ApiKeyService` с проверкой БД.

### Шаг 4: Добавить Admin UI
Создать `ApiKeyManagementController` для управления ключами.

---

## Checklist реализации MVP

- [ ] Создать `CourierIntegrationProperties` (config class)
- [ ] Создать `CourierApiKeyFilter` (security filter)
- [ ] Обновить `SecurityConfig` (добавить фильтр)
- [ ] Добавить конфигурацию в `application.yml`
- [ ] Сгенерировать production ключ (`openssl rand -base64 32`)
- [ ] Передать ключ TEEZ команде (через защищенный канал)
- [ ] Добавить в Kubernetes Secret (для production)
- [ ] Unit тест для `CourierApiKeyFilter`
- [ ] Integration тест: запрос с валидным ключом → 200
- [ ] Integration тест: запрос с невалидным ключом → 401
- [ ] Integration тест: запрос без ключа → 401
- [ ] Документация для TEEZ (как использовать ключ)

---

## Пример теста

```java
@SpringBootTest
@AutoConfigureMockMvc
class CourierApiKeyFilterTest {
    
    @Autowired
    private MockMvc mockMvc;
    
    @Value("${courier.integration.api-key}")
    private String validApiKey;
    
    @Test
    void shouldAllow_whenValidApiKey() throws Exception {
        mockMvc.perform(post("/api/v1/integration/waybills")
                .header("X-API-Key", validApiKey)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
                .andExpect(status().isOk()); // или 400 если payload невалиден
    }
    
    @Test
    void shouldDeny_whenInvalidApiKey() throws Exception {
        mockMvc.perform(post("/api/v1/integration/waybills")
                .header("X-API-Key", "wrong-key")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
                .andExpect(status().isUnauthorized());
    }
    
    @Test
    void shouldDeny_whenNoApiKey() throws Exception {
        mockMvc.perform(post("/api/v1/integration/waybills")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}"))
                .andExpect(status().isUnauthorized());
    }
}
```

---

## Сравнение: MVP vs Полная версия

| Аспект | MVP (Упрощенная) | Полная версия |
|--------|------------------|---------------|
| **Сложность** | Очень простая | Средняя |
| **Время реализации** | 2-4 часа | 2-3 дня |
| **Хранение ключа** | application.yml | БД с хешированием |
| **Количество ключей** | 1 (статический) | Множество (на маркетплейс) |
| **Генерация** | Вручную (openssl) | Через Admin UI |
| **Ротация** | Ручная (через config) | Автоматическая (с историей) |
| **IP whitelist** | Нет | Да |
| **Rate limiting** | Нет | Да |
| **Статистика** | Через integration_log | Детальная в отдельной таблице |
| **Scopes** | Нет | Да |
| **Подходит для** | MVP, 1 маркетплейс | Production, много маркетплейсов |

---

## Выводы

### Для MVP используем упрощенную версию:
✅ **Статический ключ** в конфигурации  
✅ **Простой фильтр** с проверкой строки  
✅ **Логирование** в существующую таблицу  
✅ **Экономия времени**: 2-3 дня вместо недели  

### Когда мигрировать на полную версию:
- Появляется 2+ маркетплейса (Kaspi, Wildberries)
- Нужны разные права доступа
- Требуется автоматическая ротация
- Нужен IP whitelist
- Требуется детальная статистика

**Для MVP упрощенной версии достаточно!** Можно всегда мигрировать позже.

---

**Дата создания**: 2025-01-06  
**Версия**: MVP 1.0  
**Оценка времени реализации**: 2-4 часа  
**Приоритет**: High
