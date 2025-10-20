# TASK-5: Генерация QR кода и создание сессии

## Описание
Реализовать сервис для создания сессии подписания и генерации QR кода с префиксом `mobileSign:` для eGov Mobile.

## Приоритет
High

## Story Points
5

## API Спецификация

### Эндпоинт (внутренний для фронтенда)
```
POST /api/contracts/{contractId}/create-signing-session
```

### Path Parameters
| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| contractId | Long | Да | ID договора для подписания |

### Request Body
```json
{
  "signingMethod": "QR",  // или "CROSS_SIGN" для deep links
  "authType": "TOKEN",    // NONE, TOKEN, EDS
  "expiryMinutes": 30
}
```

### Response 201 Created
```json
{
  "sessionId": 123,
  "qrCodeUrl": "mobileSign:https://backend.coube.kz/api/egov-sign/info/123?token=eyJhbG...",
  "qrCodeImage": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
  "expiresAt": "2025-10-19T18:30:00Z",
  "status": "PENDING"
}
```

### Response для других типов документов
```
POST /api/invoices/{invoiceId}/create-signing-session
POST /api/acts/{actId}/create-signing-session
POST /api/registries/{registryId}/create-signing-session
```

## DTO классы

### CreateSigningSessionRequest.java
```java
@Data
public class CreateSigningSessionRequest {
    @NotNull
    private String signingMethod; // QR, CROSS_SIGN

    @NotNull
    private String authType; // NONE, TOKEN, EDS

    private Integer expiryMinutes = 30;
}

@Data
@Builder
public class SigningSessionResponse {
    private Long sessionId;
    private String qrCodeUrl;
    private String qrCodeImage; // base64 PNG
    private String expiresAt;
    private String status;
}
```

## Сервис генерации QR

### QrCodeGenerator.java
```java
@Service
public class QrCodeGenerator {

    @Value("${app.egov.base-url}")
    private String baseUrl;

    // Сгенерировать QR URL
    public String generateQrUrl(Long sessionId, String token) {
        StringBuilder url = new StringBuilder();
        url.append(baseUrl)
           .append("/api/egov-sign/info/")
           .append(sessionId);

        if (token != null && !token.isEmpty()) {
            url.append("?token=").append(token);
        }

        // Добавить префикс и удалить пробелы
        String qrUrl = "mobileSign:" + url.toString();
        return qrUrl.replaceAll("\\s", "");
    }

    // Сгенерировать QR изображение
    public String generateQrCodeImage(String qrUrl) throws Exception {
        // Параметры QR кода
        int width = 300;
        int height = 300;

        Map<EncodeHintType, Object> hints = new HashMap<>();
        hints.put(EncodeHintType.CHARACTER_SET, "UTF-8");
        hints.put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M);
        hints.put(EncodeHintType.MARGIN, 1);

        // Генерация QR матрицы
        BitMatrix bitMatrix = new MultiFormatWriter().encode(
            qrUrl,
            BarcodeFormat.QR_CODE,
            width,
            height,
            hints
        );

        // Конвертация в PNG
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        MatrixToImageWriter.writeToStream(bitMatrix, "PNG", outputStream);

        // Кодирование в base64
        byte[] imageBytes = outputStream.toByteArray();
        String base64Image = Base64.getEncoder().encodeToString(imageBytes);

        return "data:image/png;base64," + base64Image;
    }
}
```

## Сервис создания сессии

### SigningSessionManager.java
```java
@Service
public class SigningSessionManager {

    @Autowired
    private EgovSigningSessionRepository sessionRepository;

    @Autowired
    private QrCodeGenerator qrGenerator;

    @Autowired
    private TokenGenerator tokenGenerator;

    @Value("${app.egov.qr-expiry-minutes}")
    private Integer defaultExpiryMinutes;

    public SigningSessionResponse createSessionForContract(
        Long contractId,
        CreateSigningSessionRequest request
    ) {
        // 1. Создать сессию
        EgovSigningSession session = new EgovSigningSession();
        session.setContractId(contractId);
        session.setDocumentType("CONTRACT");
        session.setSigningMethod(request.getSigningMethod());
        session.setAuthType(request.getAuthType());
        session.setStatus("PENDING");

        // 2. Генерировать токен если нужен
        String token = null;
        if ("TOKEN".equals(request.getAuthType())) {
            token = tokenGenerator.generateSecureToken();
            session.setAuthToken(token);
        }

        // 3. Установить срок действия
        int expiryMinutes = request.getExpiryMinutes() != null
            ? request.getExpiryMinutes()
            : defaultExpiryMinutes;

        LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(expiryMinutes);
        session.setExpiresAt(expiresAt);

        // 4. Сохранить сессию
        session = sessionRepository.save(session);

        // 5. Генерировать QR URL
        String qrUrl = qrGenerator.generateQrUrl(session.getId(), token);
        session.setQrUrl(qrUrl);
        sessionRepository.save(session);

        // 6. Генерировать QR изображение
        String qrImage = null;
        try {
            qrImage = qrGenerator.generateQrCodeImage(qrUrl);
        } catch (Exception e) {
            log.error("Failed to generate QR code image", e);
        }

        // 7. Вернуть ответ
        return SigningSessionResponse.builder()
            .sessionId(session.getId())
            .qrCodeUrl(qrUrl)
            .qrCodeImage(qrImage)
            .expiresAt(expiresAt.toString())
            .status(session.getStatus())
            .build();
    }

    public SigningSessionResponse createSessionForInvoice(Long invoiceId, CreateSigningSessionRequest request) {
        // Аналогично, но для invoice
        EgovSigningSession session = new EgovSigningSession();
        session.setInvoiceId(invoiceId);
        session.setDocumentType("INVOICE");
        // ... rest of logic
    }

    public SigningSessionResponse createSessionForAct(Long actId, CreateSigningSessionRequest request) {
        // Аналогично для act
    }

    public SigningSessionResponse createSessionForRegistry(Long registryId, CreateSigningSessionRequest request) {
        // Аналогично для registry
    }
}
```

### TokenGenerator.java
```java
@Service
public class TokenGenerator {

    public String generateSecureToken() {
        // Генерировать случайный токен
        SecureRandom random = new SecureRandom();
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);

        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    public String generateJwtToken(Long sessionId, Long userId) {
        // Опционально: генерировать JWT токен с подписью
        return Jwts.builder()
            .setSubject(userId.toString())
            .claim("sessionId", sessionId)
            .setIssuedAt(new Date())
            .setExpiration(new Date(System.currentTimeMillis() + 1800000)) // 30 min
            .signWith(SignatureAlgorithm.HS256, secret)
            .compact();
    }
}
```

## Контроллер

### ContractSigningController.java
```java
@RestController
@RequestMapping("/api/contracts")
public class ContractSigningController {

    @Autowired
    private SigningSessionManager sessionManager;

    @PostMapping("/{contractId}/create-signing-session")
    @Operation(summary = "Создать сессию подписания для договора")
    public ResponseEntity<SigningSessionResponse> createSigningSession(
        @PathVariable Long contractId,
        @RequestBody @Valid CreateSigningSessionRequest request
    ) {
        SigningSessionResponse response = sessionManager.createSessionForContract(contractId, request);
        return ResponseEntity.status(201).body(response);
    }
}

@RestController
@RequestMapping("/api/invoices")
public class InvoiceSigningController {

    @PostMapping("/{invoiceId}/create-signing-session")
    @Operation(summary = "Создать сессию подписания для счета-фактуры")
    public ResponseEntity<SigningSessionResponse> createSigningSession(
        @PathVariable Long invoiceId,
        @RequestBody @Valid CreateSigningSessionRequest request
    ) {
        SigningSessionResponse response = sessionManager.createSessionForInvoice(invoiceId, request);
        return ResponseEntity.status(201).body(response);
    }
}
```

## Deep Link генерация (для мобильного)

### DeepLinkGenerator.java
```java
@Service
public class DeepLinkGenerator {

    @Value("${app.egov.deep-link-base}")
    private String deepLinkBase; // https://mgovsign.page.link/

    // Генерировать deep link для iOS
    public String generateiOSDeepLink(String api1Url) {
        String encodedUrl = URLEncoder.encode(api1Url, StandardCharsets.UTF_8);

        return deepLinkBase + "?link=" + encodedUrl
            + "&isi=1476128386"  // App Store ID
            + "&ibi=kz.egov.mobile"; // Bundle ID
    }

    // Генерировать deep link для Android
    public String generateAndroidDeepLink(String api1Url) {
        String encodedUrl = URLEncoder.encode(api1Url, StandardCharsets.UTF_8);

        return deepLinkBase + "?link=" + encodedUrl
            + "&apn=kz.mobile.mgov"; // Package name
    }
}
```

## Зависимости в pom.xml

```xml
<!-- QR Code generation -->
<dependency>
    <groupId>com.google.zxing</groupId>
    <artifactId>core</artifactId>
    <version>3.5.1</version>
</dependency>
<dependency>
    <groupId>com.google.zxing</groupId>
    <artifactId>javase</artifactId>
    <version>3.5.1</version>
</dependency>

<!-- JWT (optional) -->
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt</artifactId>
    <version>0.9.1</version>
</dependency>
```

## Конфигурация

### application.yml
```yaml
app:
  egov:
    base-url: ${EGOV_BASE_URL:https://backend.coube.kz}
    qr-expiry-minutes: 30
    deep-link-base: https://mgovsign.page.link/
```

## Тесты

### QrCodeGeneratorTest.java
```java
@SpringBootTest
class QrCodeGeneratorTest {

    @Autowired
    private QrCodeGenerator generator;

    @Test
    void generateQrUrl_WithToken_ReturnsCorrectFormat() {
        String url = generator.generateQrUrl(123L, "test-token");

        assertTrue(url.startsWith("mobileSign:"));
        assertTrue(url.contains("/api/egov-sign/info/123"));
        assertTrue(url.contains("?token=test-token"));
        assertFalse(url.contains(" ")); // no spaces
    }

    @Test
    void generateQrCodeImage_ReturnsBase64Image() throws Exception {
        String url = "mobileSign:https://test.com";
        String image = generator.generateQrCodeImage(url);

        assertTrue(image.startsWith("data:image/png;base64,"));
        assertTrue(image.length() > 100); // has actual image data
    }
}
```

## Критерии приемки
- ✅ Реализован POST /api/contracts/{id}/create-signing-session
- ✅ Реализованы аналогичные эндпоинты для invoices, acts, registries
- ✅ Генерируется QR URL с префиксом `mobileSign:`
- ✅ Генерируется QR изображение в base64
- ✅ Создается сессия в БД со статусом PENDING
- ✅ Генерируется токен для auth_type=TOKEN
- ✅ Устанавливается срок действия сессии
- ✅ Поддержка deep links для iOS/Android
- ✅ Unit тесты для генератора QR
- ✅ Integration тесты для создания сессии

## Зависимости
- TASK-1 (database schema)

## Связанная документация
- [Flow диаграмма 1.2](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#12-детализация-генерации-qr-кода)
- [Flow диаграмма 2.2](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#22-построение-динамической-ссылки)
