# Backend Task 3: EgovSignSessionService - Управление сессиями

## 📋 Описание

Создать сервис для управления сессиями подписания через eGov Mobile: создание, получение, обновление статуса, проверка истечения срока.

## 📍 Расположение

**Файл:** `coube-backend/src/main/java/kz/coube/backend/egov/service/EgovSignSessionService.java`

## 🎯 Функциональность

Сервис управляет жизненным циклом сессий подписания:
- Создание новой сессии
- Генерация уникального sessionId
- Генерация JWT токена для авторизации
- Получение сессии по ID
- Проверка срока действия
- Обновление статуса сессии
- Очистка истекших сессий

## ✅ Чеклист реализации

### 1. Создание класса сервиса

- [ ] Создать `EgovSignSessionService.java` с аннотацией `@Service`
- [ ] Добавить `@RequiredArgsConstructor` для DI
- [ ] Добавить логирование `@Slf4j`

### 2. Зависимости

- [ ] Внедрить `EgovSignSessionRepository`
- [ ] Внедрить `JwtTokenProvider` (для генерации JWT)
- [ ] Внедрить `AgreementService`
- [ ] Внедрить `InvoiceService`
- [ ] Внедрить `ActService`
- [ ] Внедрить `RegistryService`
- [ ] Внедрить `OrganizationService`
- [ ] Внедрить конфигурацию: `@Value("${egov.sign.session.ttl-minutes}")` (default: 30)
- [ ] Внедрить конфигурацию: `@Value("${egov.sign.api.base-url}")` (например: "https://api.coube.kz")

### 3. Метод: Создание сессии

- [ ] Реализовать `createSession`:
  ```java
  @Transactional
  public EgovSignSession createSession(String documentId, String documentType, Long userId) {

      // 1. Валидация: проверить существование документа
      validateDocument(documentId, documentType);

      // 2. Генерация UUID для sessionId
      String sessionId = UUID.randomUUID().toString();

      // 3. Генерация JWT токена для auth_token
      String authToken = generateAuthToken(sessionId, documentId, documentType);

      // 4. Установка времени
      LocalDateTime now = LocalDateTime.now();
      LocalDateTime expiresAt = now.plusMinutes(sessionTtlMinutes); // 30 минут

      // 5. Создание entity
      EgovSignSession session = EgovSignSession.builder()
          .sessionId(sessionId)
          .documentId(documentId)
          .documentType(documentType)
          .userId(userId)
          .status(SessionStatus.PENDING)
          .authToken(authToken)
          .createdAt(now)
          .expiresAt(expiresAt)
          .build();

      // 6. Сохранение в БД
      session = sessionRepository.save(session);

      // 7. Логирование
      log.info("Created eGov sign session: sessionId={}, documentType={}, documentId={}",
               sessionId, documentType, documentId);

      return session;
  }
  ```

### 4. Метод: Валидация документа

- [ ] Реализовать `validateDocument`:
  ```java
  private void validateDocument(String documentId, String documentType) {
      switch (documentType) {
          case "agreement":
              if (!agreementService.existsById(Long.parseLong(documentId))) {
                  throw new ResourceNotFoundException("Agreement not found: " + documentId);
              }
              break;
          case "invoice":
              if (!invoiceService.existsById(Long.parseLong(documentId))) {
                  throw new ResourceNotFoundException("Invoice not found: " + documentId);
              }
              break;
          case "act":
              if (!actService.existsById(Long.parseLong(documentId))) {
                  throw new ResourceNotFoundException("Act not found: " + documentId);
              }
              break;
          case "registry":
              if (!registryService.existsById(Long.parseLong(documentId))) {
                  throw new ResourceNotFoundException("Registry not found: " + documentId);
              }
              break;
          default:
              throw new IllegalArgumentException("Unknown document type: " + documentType);
      }
  }
  ```

### 5. Метод: Генерация JWT токена

- [ ] Реализовать `generateAuthToken`:
  ```java
  private String generateAuthToken(String sessionId, String documentId, String documentType) {
      Map<String, Object> claims = new HashMap<>();
      claims.put("sessionId", sessionId);
      claims.put("documentId", documentId);
      claims.put("documentType", documentType);
      claims.put("purpose", "egov-mobile-sign");

      // TTL = 30 минут
      long expirationMillis = sessionTtlMinutes * 60 * 1000;

      return jwtTokenProvider.generateToken(claims, expirationMillis);
  }
  ```

### 6. Метод: Получение сессии

- [ ] Реализовать `getSession`:
  ```java
  @Transactional(readOnly = true)
  public EgovSignSession getSession(String sessionId) {
      return sessionRepository.findBySessionId(sessionId)
          .orElseThrow(() -> new SessionNotFoundException("Session not found: " + sessionId));
  }
  ```

- [ ] Реализовать `getSessionWithValidation`:
  ```java
  @Transactional(readOnly = true)
  public EgovSignSession getSessionWithValidation(String sessionId) {
      EgovSignSession session = getSession(sessionId);

      // Проверка срока действия
      if (session.getExpiresAt().isBefore(LocalDateTime.now())) {
          throw new SessionExpiredException("Session expired: " + sessionId);
      }

      return session;
  }
  ```

### 7. Метод: Обновление статуса

- [ ] Реализовать `updateStatus`:
  ```java
  @Transactional
  public void updateStatus(String sessionId, SessionStatus newStatus) {
      EgovSignSession session = getSession(sessionId);

      SessionStatus oldStatus = session.getStatus();
      session.setStatus(newStatus);

      if (newStatus == SessionStatus.SIGNED) {
          session.setSignedAt(LocalDateTime.now());
      }

      sessionRepository.save(session);

      log.info("Updated session status: sessionId={}, {} -> {}",
               sessionId, oldStatus, newStatus);
  }
  ```

- [ ] Реализовать `markAsSigned`:
  ```java
  @Transactional
  public void markAsSigned(String sessionId) {
      updateStatus(sessionId, SessionStatus.SIGNED);
  }
  ```

- [ ] Реализовать `markAsError`:
  ```java
  @Transactional
  public void markAsError(String sessionId, String errorMessage) {
      EgovSignSession session = getSession(sessionId);
      session.setStatus(SessionStatus.ERROR);
      session.setErrorMessage(errorMessage);
      sessionRepository.save(session);

      log.error("Session marked as error: sessionId={}, error={}", sessionId, errorMessage);
  }
  ```

### 8. Метод: Генерация API URL и QR кода

- [ ] Реализовать `getApiUrl`:
  ```java
  public String getApiUrl(String sessionId) {
      return String.format("%s/api/v1/egov-sign/session/%s", apiBaseUrl, sessionId);
  }
  ```

- [ ] Реализовать `getQrCodeContent`:
  ```java
  public String getQrCodeContent(String sessionId) {
      String apiUrl = getApiUrl(sessionId);
      return "mobileSign:" + apiUrl;
  }
  ```

### 9. Метод: Очистка истекших сессий

- [ ] Реализовать scheduled task для очистки:
  ```java
  @Scheduled(cron = "0 0 * * * *") // каждый час
  @Transactional
  public void cleanupExpiredSessions() {
      LocalDateTime now = LocalDateTime.now();

      List<EgovSignSession> expiredSessions =
          sessionRepository.findByExpiresAtBeforeAndStatusIn(
              now,
              Arrays.asList(SessionStatus.PENDING)
          );

      int count = expiredSessions.size();

      if (count > 0) {
          expiredSessions.forEach(session -> {
              session.setStatus(SessionStatus.EXPIRED);
          });

          sessionRepository.saveAll(expiredSessions);

          log.info("Cleaned up {} expired eGov sign sessions", count);
      }
  }
  ```

### 10. Метод: Получение статистики

- [ ] Реализовать `getSessionStatistics`:
  ```java
  @Transactional(readOnly = true)
  public Map<String, Long> getSessionStatistics() {
      Map<String, Long> stats = new HashMap<>();
      stats.put("total", sessionRepository.count());
      stats.put("pending", sessionRepository.countByStatus(SessionStatus.PENDING));
      stats.put("signed", sessionRepository.countByStatus(SessionStatus.SIGNED));
      stats.put("expired", sessionRepository.countByStatus(SessionStatus.EXPIRED));
      stats.put("error", sessionRepository.countByStatus(SessionStatus.ERROR));
      return stats;
  }
  ```

### 11. Exception классы

- [ ] Создать `SessionNotFoundException.java`:
  ```java
  public class SessionNotFoundException extends RuntimeException {
      public SessionNotFoundException(String message) {
          super(message);
      }
  }
  ```

- [ ] Создать `SessionExpiredException.java`:
  ```java
  public class SessionExpiredException extends RuntimeException {
      public SessionExpiredException(String message) {
          super(message);
      }
  }
  ```

### 12. JWT Token Provider

- [ ] Создать/обновить `JwtTokenProvider.java`:
  ```java
  @Component
  public class JwtTokenProvider {

      @Value("${jwt.secret}")
      private String secret;

      public String generateToken(Map<String, Object> claims, long expirationMillis) {
          Date now = new Date();
          Date expiryDate = new Date(now.getTime() + expirationMillis);

          return Jwts.builder()
              .setClaims(claims)
              .setIssuedAt(now)
              .setExpiration(expiryDate)
              .signWith(SignatureAlgorithm.HS512, secret)
              .compact();
      }

      public Claims parseToken(String token) {
          return Jwts.parser()
              .setSigningKey(secret)
              .parseClaimsJws(token)
              .getBody();
      }

      public boolean validateToken(String token) {
          try {
              parseToken(token);
              return true;
          } catch (Exception e) {
              return false;
          }
      }
  }
  ```

### 13. Конфигурация

- [ ] Добавить в `application.yml`:
  ```yaml
  egov:
    sign:
      session:
        ttl-minutes: 30
      api:
        base-url: ${API_BASE_URL:https://api.coube.kz}

  jwt:
    secret: ${JWT_SECRET:your-secret-key-change-in-production}
  ```

### 14. Логирование

- [ ] Логировать создание сессии (INFO)
- [ ] Логировать обновление статуса (INFO)
- [ ] Логировать истечение сессии (WARN)
- [ ] Логировать ошибки (ERROR)
- [ ] Логировать очистку истекших сессий (INFO)

### 15. Тестирование

- [ ] Unit-тесты для `createSession`:
  - Успешное создание
  - Несуществующий документ
  - Генерация sessionId
  - Генерация JWT токена
  - Установка expiresAt

- [ ] Unit-тесты для `getSession`:
  - Получение существующей сессии
  - Несуществующая сессия (exception)

- [ ] Unit-тесты для `getSessionWithValidation`:
  - Валидная сессия
  - Истекшая сессия (exception)

- [ ] Unit-тесты для `updateStatus`:
  - Обновление на SIGNED
  - Обновление на ERROR
  - Установка signedAt

- [ ] Unit-тесты для `cleanupExpiredSessions`:
  - Очистка истекших сессий
  - Не трогать активные сессии

- [ ] Integration-тесты:
  - End-to-end создание и получение сессии
  - Проверка сохранения в БД

## 📚 Требования

### Время жизни сессии
- **TTL**: 30 минут (согласно документации eGov Mobile)
- **Автоочистка**: Каждый час помечать истекшие как EXPIRED

### JWT токен
- **Алгоритм**: HS512
- **Claims**: sessionId, documentId, documentType, purpose
- **Expiration**: 30 минут

### Статусы сессии
- `PENDING` - ожидает подписания
- `SIGNED` - успешно подписана
- `EXPIRED` - истек срок действия
- `ERROR` - ошибка при подписании

## 🔗 Зависимости

**Зависит от:**
- Task 4: `EgovSignSession` entity и `EgovSignSessionRepository`

**Необходимо для:**
- Task 1: `EgovSignController`
- Task 2: `EgovDocumentController`

## ⚠️ Важные замечания

1. **Thread-safety**: Все методы должны быть thread-safe
2. **Transactional**: Использовать `@Transactional` для операций с БД
3. **Cleanup**: Scheduled task должен работать в отдельной транзакции
4. **JWT Secret**: В production использовать сильный секретный ключ из environment variables

## 📊 Критерии приемки

- [ ] `createSession` создает сессию с валидным sessionId и JWT токеном
- [ ] `getSession` возвращает сессию по sessionId
- [ ] `getSessionWithValidation` проверяет срок действия
- [ ] `updateStatus` корректно обновляет статус и signedAt
- [ ] JWT токен содержит необходимые claims
- [ ] Истекшие сессии автоматически помечаются как EXPIRED
- [ ] Все exception обрабатываются корректно
- [ ] Все unit-тесты проходят
- [ ] Логирование работает корректно

---

**Приоритет:** 🔴 Высокий
**Оценка:** 4-6 часов
**Assignee:** Backend Developer
**Зависит от:** Task 4
