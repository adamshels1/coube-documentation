# TASK-2: API №1 - Получение информации о подписании

## Описание
Реализовать API №1 для получения метаданных документа для подписания через eGov Mobile.

## Приоритет
High

## Story Points
5

## API Спецификация

### Эндпоинт
```
GET /api/egov-sign/info/{sessionId}
```

### Path Parameters
| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| sessionId | Long | Да | ID сессии подписания |

### Query Parameters
| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| token | String | Нет | Токен авторизации (если auth_type=TOKEN) |

### Request Headers
```
Accept-Language: ru | kk | en
```

### Response 200 OK
```json
{
  "description": "Договор на транспортные услуги №123",
  "expiryDate": "2025-10-19T18:30:00Z",
  "organisation": {
    "bin": "123456789012",
    "name": "ТОО COUBE"
  },
  "document": {
    "uri": "https://backend.coube.kz/api/egov-sign/documents/456",
    "authType": "TOKEN",
    "authToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

### Response 404 Not Found
```json
{
  "message": "Сессия подписания не найдена",
  "code": "SESSION_NOT_FOUND"
}
```

### Response 410 Gone
```json
{
  "message": "Срок действия сессии истек",
  "code": "SESSION_EXPIRED"
}
```

## DTO классы

### SigningInfoDTO.java
```java
@Data
@Builder
public class SigningInfoDTO {
    private String description;
    private String expiryDate; // ISO8601 format
    private OrganisationDTO organisation;
    private DocumentAuthDTO document;
}

@Data
@Builder
public class OrganisationDTO {
    private String bin;
    private String name;
}

@Data
@Builder
public class DocumentAuthDTO {
    private String uri;
    private String authType; // NONE, TOKEN, EDS
    private String authToken; // опционально
}
```

## Сервис

### EgovSigningService.java
```java
@Service
public class EgovSigningService {

    @Autowired
    private EgovSigningSessionRepository sessionRepository;

    @Autowired
    private OrganizationRepository organizationRepository;

    public SigningInfoDTO getSigningInfo(Long sessionId) {
        EgovSigningSession session = sessionRepository.findById(sessionId)
            .orElseThrow(() -> new SessionNotFoundException());

        // Проверить срок действия
        if (session.getExpiresAt().isBefore(LocalDateTime.now())) {
            session.setStatus("EXPIRED");
            sessionRepository.save(session);
            throw new SessionExpiredException();
        }

        // Получить организацию
        Organization org = getOrganizationByDocumentType(session);

        // Построить ответ
        return SigningInfoDTO.builder()
            .description(buildDescription(session))
            .expiryDate(session.getExpiresAt().toString())
            .organisation(OrganisationDTO.builder()
                .bin(org.getIinBin())
                .name(org.getOrganizationName())
                .build())
            .document(DocumentAuthDTO.builder()
                .uri(buildDocumentUri(session.getId()))
                .authType(session.getAuthType())
                .authToken(session.getAuthToken())
                .build())
            .build();
    }

    private String buildDocumentUri(Long sessionId) {
        return baseUrl + "/api/egov-sign/documents/" + sessionId;
    }

    private String buildDescription(EgovSigningSession session) {
        // Генерировать описание в зависимости от типа документа
        return "Документ для подписания";
    }
}
```

## Контроллер

### EgovSignController.java
```java
@RestController
@RequestMapping("/api/egov-sign")
@Tag(name = "eGov Signing", description = "API для подписания через eGov Mobile")
public class EgovSignController {

    @Autowired
    private EgovSigningService signingService;

    @GetMapping("/info/{sessionId}")
    @Operation(summary = "Получить информацию о документе для подписания (API №1)")
    public ResponseEntity<SigningInfoDTO> getSigningInfo(
        @PathVariable Long sessionId,
        @RequestParam(required = false) String token,
        @RequestHeader(value = "Accept-Language", defaultValue = "ru") String language
    ) {
        SigningInfoDTO info = signingService.getSigningInfo(sessionId);
        return ResponseEntity.ok(info);
    }
}
```

## Exception Handlers

### GlobalExceptionHandler.java
```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(SessionNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleSessionNotFound(SessionNotFoundException ex) {
        return ResponseEntity.status(404)
            .body(new ErrorResponse("SESSION_NOT_FOUND", "Сессия подписания не найдена"));
    }

    @ExceptionHandler(SessionExpiredException.class)
    public ResponseEntity<ErrorResponse> handleSessionExpired(SessionExpiredException ex) {
        return ResponseEntity.status(410)
            .body(new ErrorResponse("SESSION_EXPIRED", "Срок действия сессии истек"));
    }
}
```

## Тесты

### EgovSignControllerTest.java
```java
@WebMvcTest(EgovSignController.class)
class EgovSignControllerTest {

    @Test
    void getSigningInfo_Success() throws Exception {
        mockMvc.perform(get("/api/egov-sign/info/123"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.description").exists())
            .andExpect(jsonPath("$.document.uri").exists());
    }

    @Test
    void getSigningInfo_SessionNotFound() throws Exception {
        mockMvc.perform(get("/api/egov-sign/info/999"))
            .andExpect(status().isNotFound());
    }
}
```

## Критерии приемки
- ✅ Реализован эндпоинт GET /api/egov-sign/info/{sessionId}
- ✅ Возвращает корректный JSON с метаданными
- ✅ Проверяется срок действия сессии
- ✅ Обрабатываются ошибки 404 и 410
- ✅ Добавлены unit тесты
- ✅ Добавлена Swagger документация

## Зависимости
- TASK-1 (database schema)

## Связанная документация
- [Flow диаграмма 1.1](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#11-общий-поток-qr-подписания)
