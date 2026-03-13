# Backend Task 1: EgovSignController - API №1 (Метаданные подписания)

## 📋 Описание

Создать REST контроллер для инициализации сессии подписания и предоставления метаданных согласно спецификации eGov Mobile API №1.

## 📍 Расположение

**Файл:** `coube-backend/src/main/java/kz/coube/backend/egov/api/EgovSignController.java`

## 🎯 Функциональность

### Endpoint 1: Инициализация сессии
**POST** `/api/v1/egov-sign/init`

Создает новую сессию подписания для документа.

**Request Body:**
```json
{
  "documentId": "123",
  "documentType": "agreement" // или "invoice", "act", "registry"
}
```

**Response:**
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "apiUrl": "https://api.coube.kz/api/v1/egov-sign/session/550e8400-e29b-41d4-a716-446655440000",
  "qrCode": "mobileSign:https://api.coube.kz/api/v1/egov-sign/session/550e8400-e29b-41d4-a716-446655440000",
  "expiresAt": "2026-01-07T15:30:00.000Z"
}
```

### Endpoint 2: Получение метаданных (API №1)
**GET** `/api/v1/egov-sign/session/{sessionId}`

Возвращает метаданные для eGov Mobile согласно спецификации.

**Response (согласно документации eGov Mobile):**
```json
{
  "description": "Подписание договора №123 от 07.01.2026",
  "expiry_date": "2026-01-07T15:30:00.000Z",
  "organisation": {
    "nameRu": "Товарищество с ограниченной ответственностью \"COUBE\"",
    "nameKz": "\"COUBE\" жауапкершілігі шектеулі серіктестігі",
    "nameEn": "COUBE LLP",
    "bin": "000740000728"
  },
  "document": {
    "uri": "https://api.coube.kz/api/v1/egov-sign/session/550e8400-e29b-41d4-a716-446655440000/document",
    "auth_type": "Token",
    "auth_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

### Endpoint 3: Проверка статуса сессии
**GET** `/api/v1/egov-sign/session/{sessionId}/status`

Возвращает текущий статус сессии подписания.

**Response:**
```json
{
  "sessionId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "PENDING", // PENDING, SIGNED, EXPIRED, ERROR
  "documentId": "123",
  "documentType": "agreement",
  "createdAt": "2026-01-07T15:00:00.000Z",
  "expiresAt": "2026-01-07T15:30:00.000Z",
  "signedAt": null
}
```

## ✅ Чеклист реализации

### 1. Создание структуры пакетов
- [ ] Создать пакет `kz.coube.backend.egov.api`
- [ ] Создать пакет `kz.coube.backend.egov.dto.request`
- [ ] Создать пакет `kz.coube.backend.egov.dto.response`

### 2. DTO классы
- [ ] Создать `EgovSignInitRequest.java`:
  ```java
  @Data
  public class EgovSignInitRequest {
      @NotBlank
      private String documentId;

      @NotBlank
      private String documentType; // agreement, invoice, act, registry
  }
  ```

- [ ] Создать `EgovSignInitResponse.java`:
  ```java
  @Data
  @Builder
  public class EgovSignInitResponse {
      private String sessionId;
      private String apiUrl;
      private String qrCode;
      private LocalDateTime expiresAt;
  }
  ```

- [ ] Создать `EgovApi1Response.java` (согласно спецификации):
  ```java
  @Data
  @Builder
  public class EgovApi1Response {
      private String description;
      @JsonProperty("expiry_date")
      private String expiryDate; // ISO 8601: "yyyy-MM-dd'T'HH:mm:ss.SSSz"
      private OrganisationDto organisation;
      private DocumentDto document;

      @Data
      @Builder
      public static class OrganisationDto {
          private String nameRu;
          private String nameKz;
          private String nameEn;
          private String bin;
      }

      @Data
      @Builder
      public static class DocumentDto {
          private String uri;
          @JsonProperty("auth_type")
          private String authType; // "Token", "Eds", "None"
          @JsonProperty("auth_token")
          private String authToken;
      }
  }
  ```

- [ ] Создать `EgovSessionStatusResponse.java`:
  ```java
  @Data
  @Builder
  public class EgovSessionStatusResponse {
      private String sessionId;
      private String status;
      private String documentId;
      private String documentType;
      private LocalDateTime createdAt;
      private LocalDateTime expiresAt;
      private LocalDateTime signedAt;
  }
  ```

### 3. Контроллер
- [ ] Создать `EgovSignController.java` с аннотацией `@RestController`
- [ ] Добавить `@RequestMapping("/api/v1/egov-sign")`
- [ ] Добавить `@RequiredArgsConstructor` для DI

- [ ] Реализовать метод `initSession`:
  ```java
  @PostMapping("/init")
  @Operation(summary = "Инициализация сессии подписания через eGov Mobile")
  public ResponseEntity<EgovSignInitResponse> initSession(
      @Valid @RequestBody EgovSignInitRequest request) {

      // Вызвать EgovSignSessionService.createSession()
      // Вернуть sessionId, apiUrl, qrCode, expiresAt
  }
  ```

- [ ] Реализовать метод `getSessionMetadata` (API №1):
  ```java
  @GetMapping("/session/{sessionId}")
  @Operation(summary = "API №1: Получение метаданных для eGov Mobile")
  public ResponseEntity<EgovApi1Response> getSessionMetadata(
      @PathVariable String sessionId) {

      // Получить сессию по sessionId
      // Проверить срок действия (expiresAt)
      // Получить документ и организацию
      // Сформировать ответ согласно спецификации eGov Mobile
      // Установить expiry_date в формате ISO 8601
      // Сгенерировать JWT токен для auth_token
  }
  ```

- [ ] Реализовать метод `getSessionStatus`:
  ```java
  @GetMapping("/session/{sessionId}/status")
  @Operation(summary = "Получение статуса сессии подписания")
  public ResponseEntity<EgovSessionStatusResponse> getSessionStatus(
      @PathVariable String sessionId) {

      // Получить сессию по sessionId
      // Вернуть текущий статус
  }
  ```

### 4. Обработка ошибок
- [ ] Добавить обработку `SessionNotFoundException` → 404
- [ ] Добавить обработку `SessionExpiredException` → 410 Gone
- [ ] Добавить обработку `DocumentNotFoundException` → 404
- [ ] Добавить валидацию входных данных

### 5. Безопасность
- [ ] Добавить CORS конфигурацию для eGov Mobile (если требуется)
- [ ] Генерировать JWT токен для `auth_token` с TTL 30 минут
- [ ] Включить payload в JWT: `{sessionId, documentId, documentType, iat, exp}`

### 6. Интеграция с сервисами
- [ ] Внедрить `EgovSignSessionService` через конструктор
- [ ] Внедрить `AgreementService` для получения документов
- [ ] Внедрить `InvoiceService` для счетов-фактур
- [ ] Внедрить `ActService` для актов
- [ ] Внедрить `OrganizationService` для данных организации

### 7. Логирование
- [ ] Добавить логирование создания сессии (INFO)
- [ ] Добавить логирование запросов от eGov Mobile (INFO)
- [ ] Добавить логирование ошибок (ERROR)

### 8. Тестирование
- [ ] Написать unit-тесты для всех методов контроллера
- [ ] Написать integration-тесты с MockMvc
- [ ] Протестировать формат даты `expiry_date` (ISO 8601)
- [ ] Протестировать генерацию JWT токена
- [ ] Протестировать обработку истекших сессий

### 9. Документация
- [ ] Добавить Swagger аннотации (@Operation, @ApiResponse)
- [ ] Описать все параметры и коды ошибок
- [ ] Добавить примеры запросов/ответов

## 📚 Требования из документации

### Формат даты (согласно eGov Mobile)
- ❗ **ВАЖНО**: Использовать формат ISO 8601: `"yyyy-MM-dd'T'HH:mm:ss.SSSz"`
- Пример: `"2024-01-01T04:52:23.626Z"`

### Поле `auth_type`
- **"Token"** - использовать JWT токен в `auth_token`
- **"Eds"** - требуется подписанный XML (не используем)
- **"None"** - без аутентификации (не рекомендуется)

### Организация
- Получить данные из `Organization` entity
- Заполнить названия на 3 языках (ru, kk, en)
- БИН организации

## 🔗 Зависимости

**Зависит от:**
- Task 3: `EgovSignSessionService` (создание и управление сессиями)
- Task 4: `EgovSignSession` entity
- Существующие сервисы: `AgreementService`, `InvoiceService`, `ActService`, `OrganizationService`

**Необходимо для:**
- Task 2: `EgovDocumentController` (API №2)
- Frontend Task 6: QR Sign Modal
- Mobile Task 10: eGov Sign Service

## ⚠️ Важные замечания

1. **Срок действия сессии**: 30 минут (согласно документации)
2. **Формат URL**: Использовать полный URL с доменом (не относительный)
3. **QR код**: Формат `mobileSign:{API_URL}`
4. **JWT токен**: Включить `sessionId` для валидации в API №2
5. **Timezone**: Все даты в UTC (Z)

## 📊 Критерии приемки

- [ ] POST `/api/v1/egov-sign/init` создает сессию и возвращает корректные данные
- [ ] GET `/api/v1/egov-sign/session/{sessionId}` возвращает JSON согласно спецификации eGov Mobile
- [ ] GET `/api/v1/egov-sign/session/{sessionId}/status` возвращает актуальный статус
- [ ] Формат `expiry_date` строго соответствует ISO 8601
- [ ] JWT токен валидный и содержит необходимые claims
- [ ] Истекшие сессии возвращают 410 Gone
- [ ] Несуществующие сессии возвращают 404 Not Found
- [ ] Все unit и integration тесты проходят
- [ ] Swagger документация полная и корректная

---

**Приоритет:** 🔴 Высокий
**Оценка:** 6-8 часов
**Assignee:** Backend Developer
