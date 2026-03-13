# TASK-3: API №2 - Получение документов для подписания

## Описание
Реализовать API №2 для получения документов, которые нужно подписать в eGov Mobile. Поддержка трех типов аутентификации: NONE, TOKEN, EDS.

## Приоритет
High

## Story Points
8

## API Спецификация

### Эндпоинт 1: GET (для auth_type = NONE или TOKEN)
```
GET /api/egov-sign/documents/{sessionId}
```

### Path Parameters
| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| sessionId | Long | Да | ID сессии подписания |

### Request Headers (для TOKEN)
```
Authorization: Bearer {token}
Accept-Language: ru | kk | en
```

### Эндпоинт 2: POST (для auth_type = EDS)
```
POST /api/egov-sign/documents/{sessionId}
```

### Request Body (EDS)
```json
{
  "xml": "<login><url>...</url><timestamp>...</timestamp><Signature>...</Signature></login>"
}
```

### Response 200 OK
```json
{
  "signMethod": "CMS_WITH_DATA",
  "version": 1,
  "documentsToSign": [
    {
      "id": "doc-1",
      "nameRu": "Договор на транспортные услуги",
      "nameKk": "Көлік қызметтеріне арналған шарт",
      "nameEn": "Transport Services Agreement",
      "meta": [
        {
          "key": "contract_number",
          "value": "Д-123/2025"
        },
        {
          "key": "amount",
          "value": "500000 KZT"
        }
      ],
      "document": {
        "mime": "application/pdf",
        "data": "JVBERi0xLjQKJeLjz9MKMyAwIG9ia..." // base64
      }
    }
  ]
}
```

### Response для signMethod = XML
```json
{
  "signMethod": "XML",
  "version": 1,
  "documentsToSign": [
    {
      "id": "doc-1",
      "nameRu": "Договор",
      "nameKk": "Шарт",
      "nameEn": "Contract",
      "meta": [],
      "documentXml": "<contract><number>123</number><date>2025-10-19</date></contract>"
    }
  ]
}
```

### Response 401 Unauthorized
```json
{
  "message": "Неверный токен авторизации",
  "code": "INVALID_TOKEN"
}
```

### Response 403 Forbidden
```json
{
  "message": "Доступ запрещен",
  "code": "ACCESS_DENIED"
}
```

## DTO классы

### DocumentsToSignDTO.java
```java
@Data
@Builder
public class DocumentsToSignDTO {
    private String signMethod; // XML, CMS_WITH_DATA, CMS_SIGN_ONLY, SIGN_BYTES_ARRAY, MIX_SIGN
    private Integer version;
    private List<DocumentToSignDTO> documentsToSign;
}

@Data
@Builder
public class DocumentToSignDTO {
    private String id;
    private String signMethod; // для MIX_SIGN
    private String nameRu;
    private String nameKz;
    private String nameEn;
    private List<MetaDTO> meta;
    private String documentXml; // для XML signMethod
    private DocumentFileDTO document; // для CMS/BYTES signMethod
}

@Data
@Builder
public class DocumentFileDTO {
    private String mime; // application/pdf, text/plain, application/xml
    private String data; // base64 encoded
}

@Data
@Builder
public class MetaDTO {
    private String key;
    private String value;
}

@Data
public class SignedXmlRequest {
    private String xml;
}
```

## Сервис

### DocumentPreparationService.java
```java
@Service
public class DocumentPreparationService {

    @Autowired
    private FileMetaInfoRepository fileRepository;

    public DocumentsToSignDTO prepareDocuments(EgovSigningSession session) {
        // Получить файл документа
        FileMetaInfo file = getDocumentFile(session);

        // Определить метод подписания (по умолчанию CMS_WITH_DATA для PDF)
        String signMethod = determineSignMethod(file);

        // Подготовить документ
        DocumentToSignDTO doc = DocumentToSignDTO.builder()
            .id("doc-" + session.getId())
            .nameRu(buildDocumentName(session, "ru"))
            .nameKz(buildDocumentName(session, "kk"))
            .nameEn(buildDocumentName(session, "en"))
            .meta(buildMetadata(session))
            .build();

        if ("XML".equals(signMethod)) {
            doc.setDocumentXml(generateXmlDocument(session));
        } else {
            doc.setDocument(DocumentFileDTO.builder()
                .mime(file.getFileType())
                .data(encodeFileToBase64(file))
                .build());
        }

        return DocumentsToSignDTO.builder()
            .signMethod(signMethod)
            .version(1)
            .documentsToSign(List.of(doc))
            .build();
    }

    private String determineSignMethod(FileMetaInfo file) {
        String mimeType = file.getFileType();
        if ("application/pdf".equals(mimeType)) {
            return "CMS_WITH_DATA";
        } else if ("application/xml".equals(mimeType) || "text/xml".equals(mimeType)) {
            return "XML";
        } else {
            return "SIGN_BYTES_ARRAY";
        }
    }

    private List<MetaDTO> buildMetadata(EgovSigningSession session) {
        List<MetaDTO> meta = new ArrayList<>();

        if ("CONTRACT".equals(session.getDocumentType())) {
            Contract contract = contractRepository.findById(session.getContractId()).get();
            meta.add(new MetaDTO("transportation_id", contract.getTransportationId().toString()));
            // добавить другие мета данные
        }

        return meta;
    }

    private String encodeFileToBase64(FileMetaInfo file) {
        // Скачать файл из MinIO
        byte[] fileBytes = minioService.downloadFile(file.getMinioFilePath());
        return Base64.getEncoder().encodeToString(fileBytes);
    }
}
```

### EgovSigningService.java (расширение)
```java
@Service
public class EgovSigningService {

    @Autowired
    private DocumentPreparationService documentService;

    @Autowired
    private AuthenticationService authService;

    public DocumentsToSignDTO getDocuments(Long sessionId, String authToken) {
        EgovSigningSession session = sessionRepository.findById(sessionId)
            .orElseThrow(() -> new SessionNotFoundException());

        // Проверить аутентификацию
        validateAuthentication(session, authToken);

        // Подготовить документы
        return documentService.prepareDocuments(session);
    }

    public DocumentsToSignDTO getDocumentsWithEds(Long sessionId, String signedXml) {
        EgovSigningSession session = sessionRepository.findById(sessionId)
            .orElseThrow(() -> new SessionNotFoundException());

        // Валидировать подписанный XML
        if (!authService.validateEdsXml(signedXml)) {
            throw new InvalidEdsSignatureException();
        }

        return documentService.prepareDocuments(session);
    }

    private void validateAuthentication(EgovSigningSession session, String token) {
        if ("TOKEN".equals(session.getAuthType())) {
            if (!session.getAuthToken().equals(token)) {
                throw new InvalidTokenException();
            }
        }
    }
}
```

## Контроллер

### EgovSignController.java (расширение)
```java
@RestController
@RequestMapping("/api/egov-sign")
public class EgovSignController {

    @GetMapping("/documents/{sessionId}")
    @Operation(summary = "Получить документы для подписания (API №2 GET)")
    public ResponseEntity<DocumentsToSignDTO> getDocuments(
        @PathVariable Long sessionId,
        @RequestHeader(value = "Authorization", required = false) String authHeader,
        @RequestHeader(value = "Accept-Language", defaultValue = "ru") String language
    ) {
        String token = extractToken(authHeader);
        DocumentsToSignDTO documents = signingService.getDocuments(sessionId, token);
        return ResponseEntity.ok(documents);
    }

    @PostMapping("/documents/{sessionId}")
    @Operation(summary = "Получить документы с ЭЦП авторизацией (API №2 POST)")
    public ResponseEntity<DocumentsToSignDTO> getDocumentsWithEds(
        @PathVariable Long sessionId,
        @RequestBody @Valid SignedXmlRequest request,
        @RequestHeader(value = "Accept-Language", defaultValue = "ru") String language
    ) {
        DocumentsToSignDTO documents = signingService.getDocumentsWithEds(sessionId, request.getXml());
        return ResponseEntity.ok(documents);
    }

    private String extractToken(String authHeader) {
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            return authHeader.substring(7);
        }
        return null;
    }
}
```

## Тесты

### DocumentPreparationServiceTest.java
```java
@SpringBootTest
class DocumentPreparationServiceTest {

    @Test
    void prepareDocuments_PDF_ReturnsCmsWithData() {
        // Arrange
        EgovSigningSession session = createTestSession();
        FileMetaInfo file = createPdfFile();

        // Act
        DocumentsToSignDTO result = service.prepareDocuments(session);

        // Assert
        assertEquals("CMS_WITH_DATA", result.getSignMethod());
        assertEquals(1, result.getDocumentsToSign().size());
        assertNotNull(result.getDocumentsToSign().get(0).getDocument());
        assertEquals("application/pdf", result.getDocumentsToSign().get(0).getDocument().getMime());
    }
}
```

## Критерии приемки
- ✅ Реализован GET /api/egov-sign/documents/{sessionId}
- ✅ Реализован POST /api/egov-sign/documents/{sessionId}
- ✅ Поддержка трех типов аутентификации: NONE, TOKEN, EDS
- ✅ Возвращает документы в правильном формате
- ✅ Определяет signMethod автоматически по MIME типу
- ✅ Кодирует файлы в base64
- ✅ Добавлены метаданные документов
- ✅ Обработка ошибок 401, 403
- ✅ Unit и integration тесты

## Зависимости
- TASK-1 (database schema)
- TASK-2 (API №1)

## Связанная документация
- [Flow диаграмма 3.1](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#31-получение-документов-в-зависимости-от-типа-аутентификации)
