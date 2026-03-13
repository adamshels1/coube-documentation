# Backend Task 2: EgovDocumentController - API №2 (Документы)

## 📋 Описание

Создать REST контроллер для получения документов на подписание и приема подписанных документов согласно спецификации eGov Mobile API №2.

## 📍 Расположение

**Файл:** `coube-backend/src/main/java/kz/coube/backend/egov/api/EgovDocumentController.java`

## 🎯 Функциональность

### Endpoint 1: Получение документов для подписания (API №2 GET)
**GET** `/api/v1/egov-sign/session/{sessionId}/document`

**Headers:**
```
Authorization: Bearer {JWT_TOKEN_FROM_API1}
```

**Response (согласно документации eGov Mobile):**
```json
{
  "signMethod": "CMS_WITH_DATA",
  "version": 1,
  "documentsToSign": [
    {
      "id": 1,
      "nameRu": "Договор перевозки №123 от 07.01.2026",
      "nameKz": "07.01.2026 №123 тасымалдау шарты",
      "nameEn": "Transportation Agreement #123 dated 07.01.2026",
      "meta": [
        {
          "name": "Номер договора",
          "value": "123"
        },
        {
          "name": "Дата создания",
          "value": "07.01.2026"
        }
      ],
      "document": {
        "file": {
          "mime": "application/pdf",
          "data": "JVBERi0xLjcKJeLjz9MKMyAw..."
        }
      }
    }
  ]
}
```

### Endpoint 2: Прием подписанных документов (API №2 PUT)
**PUT** `/api/v1/egov-sign/session/{sessionId}/document`

**Headers:**
```
Authorization: Bearer {JWT_TOKEN_FROM_API1}
```

**Request Body:** (тот же JSON, но с подписанными данными)
```json
{
  "signMethod": "CMS_WITH_DATA",
  "version": 1,
  "documentsToSign": [
    {
      "id": 1,
      "nameRu": "Договор перевозки №123 от 07.01.2026",
      "nameKz": "07.01.2026 №123 тасымалдау шарты",
      "nameEn": "Transportation Agreement #123 dated 07.01.2026",
      "meta": [...],
      "document": {
        "file": {
          "mime": "application/pdf",
          "data": "MIIKzgYJKoZIhvcNAQcCoIIKvzCCCrsCAQExDj..." // подписанный CMS
        }
      }
    }
  ]
}
```

**Response:**
```json
{
  "code": "200",
  "message": "success"
}
```

**Error Response (403):**
```json
{
  "code": "403",
  "message": "Подпись не прошла валидацию"
}
```

## ✅ Чеклист реализации

### 1. DTO классы для API №2

- [ ] Создать `EgovApi2GetResponse.java`:
  ```java
  @Data
  @Builder
  public class EgovApi2GetResponse {
      private String signMethod; // "CMS_WITH_DATA", "CMS_SIGN_ONLY", "XML", "SIGN_BYTES_ARRAY", "MIX_SIGN"
      private Integer version; // всегда 1
      private List<DocumentToSignDto> documentsToSign;
  }
  ```

- [ ] Создать `DocumentToSignDto.java`:
  ```java
  @Data
  @Builder
  public class DocumentToSignDto {
      private Integer id;
      private String signMethod; // только для MIX_SIGN
      private String nameRu;
      private String nameKz;
      private String nameEn;
      private List<MetaDto> meta;
      private DocumentFileDto document;
      private String documentXml; // только для XML метода
  }
  ```

- [ ] Создать `MetaDto.java`:
  ```java
  @Data
  @Builder
  public class MetaDto {
      private String name;
      private String value;
  }
  ```

- [ ] Создать `DocumentFileDto.java`:
  ```java
  @Data
  @Builder
  public class DocumentFileDto {
      private FileDto file;

      @Data
      @Builder
      public static class FileDto {
          private String mime; // "application/pdf", "text/plain", "application/xml"
          private String data; // Base64
      }
  }
  ```

- [ ] Создать `EgovApi2PutRequest.java` (такой же как Response)

- [ ] Создать `EgovApi2PutResponse.java`:
  ```java
  @Data
  @Builder
  public class EgovApi2PutResponse {
      private String code; // "200" или "403"
      private String message;
  }
  ```

### 2. Контроллер

- [ ] Создать `EgovDocumentController.java` с аннотацией `@RestController`
- [ ] Добавить `@RequestMapping("/api/v1/egov-sign/session")`
- [ ] Добавить `@RequiredArgsConstructor` для DI

- [ ] Реализовать метод `getDocuments` (API №2 GET):
  ```java
  @GetMapping("/{sessionId}/document")
  @Operation(summary = "API №2: Получение документов для подписания в eGov Mobile")
  public ResponseEntity<EgovApi2GetResponse> getDocuments(
      @PathVariable String sessionId,
      @RequestHeader("Authorization") String authHeader) {

      // 1. Извлечь и валидировать JWT токен из Bearer header
      // 2. Проверить sessionId из токена
      // 3. Получить сессию из БД
      // 4. Проверить статус сессии (PENDING)
      // 5. Проверить срок действия (expiresAt)
      // 6. Получить документ (Agreement/Invoice/Act) по documentId из сессии
      // 7. Получить PDF файл документа
      // 8. Конвертировать PDF в Base64
      // 9. Сформировать ответ согласно спецификации
      // 10. Установить signMethod = "CMS_WITH_DATA"
      // 11. Заполнить meta данные (номер договора, дата и т.д.)
      // 12. Вернуть JSON
  }
  ```

- [ ] Реализовать метод `putSignedDocuments` (API №2 PUT):
  ```java
  @PutMapping("/{sessionId}/document")
  @Operation(summary = "API №2: Прием подписанных документов от eGov Mobile")
  public ResponseEntity<EgovApi2PutResponse> putSignedDocuments(
      @PathVariable String sessionId,
      @RequestHeader("Authorization") String authHeader,
      @Valid @RequestBody EgovApi2PutRequest request) {

      // 1. Извлечь и валидировать JWT токен
      // 2. Проверить sessionId из токена
      // 3. Получить сессию из БД
      // 4. Проверить статус (должен быть PENDING)
      // 5. Извлечь подписанный CMS из request.documentsToSign[0].document.file.data
      // 6. Получить оригинальный PDF (тот же что отдавали в GET)
      // 7. Конвертировать PDF в Base64 (для originalData)
      // 8. Вызвать SignVerifyService.verifyCmsWithOneSigner() или verifyCmsWithTwoSigners()
      //    - cms: подписанный CMS из запроса
      //    - originalData: Base64 оригинального PDF
      //    - iinBin: БИН организации
      //    - isSoloProprietor: false (для ТОО)
      // 9. Если проверка успешна:
      //    - Создать Signature entity через SignatureClient.createSignature()
      //    - Сохранить подпись к документу (Agreement/Invoice/Act)
      //    - Обновить статус сессии на SIGNED
      //    - Вернуть {code: "200", message: "success"}
      // 10. Если проверка неуспешна:
      //    - Логировать ошибку
      //    - Вернуть {code: "403", message: "Подпись не прошла валидацию"}
  }
  ```

### 3. JWT Token валидация

- [ ] Создать утилиту `JwtTokenUtil.java`:
  ```java
  public class JwtTokenUtil {
      public static String extractToken(String authHeader);
      public static Claims validateAndParseClaims(String token, String secret);
      public static String getSessionId(Claims claims);
  }
  ```

- [ ] Валидировать токен:
  - Проверить формат `Bearer {token}`
  - Проверить подпись JWT
  - Проверить срок действия (exp)
  - Извлечь sessionId из payload
  - Сравнить sessionId из токена с sessionId из URL

### 4. Получение документов

- [ ] Реализовать логику получения документа по типу:
  ```java
  private Object getDocument(String documentId, String documentType) {
      switch (documentType) {
          case "agreement":
              return agreementService.getAgreementById(Long.parseLong(documentId));
          case "invoice":
              return invoiceService.getInvoiceById(Long.parseLong(documentId));
          case "act":
              return actService.getActById(Long.parseLong(documentId));
          case "registry":
              return registryService.getRegistryById(Long.parseLong(documentId));
          default:
              throw new IllegalArgumentException("Unknown document type");
      }
  }
  ```

- [ ] Реализовать получение PDF файла:
  ```java
  private byte[] getDocumentPdf(Object document, String documentType) {
      // Получить FileMetaInfo ID печатной формы
      // Скачать файл через FileService
      // Вернуть byte[]
  }
  ```

- [ ] Реализовать конвертацию в Base64:
  ```java
  private String convertToBase64(byte[] pdfBytes) {
      return Base64.getEncoder().encodeToString(pdfBytes);
  }
  ```

### 5. Формирование мета-данных

- [ ] Реализовать метод создания мета-данных:
  ```java
  private List<MetaDto> createMetadata(Object document, String documentType) {
      // Для Agreement:
      // - "Номер договора": agreement.getNumber()
      // - "Дата создания": agreement.getCreatedAt()
      // - "БИН заказчика": agreement.getCustomer().getBin()
      // - "БИН исполнителя": agreement.getExecutor().getBin()

      // Для Invoice:
      // - "Номер счета-фактуры": invoice.getNumber()
      // - "Дата": invoice.getDate()

      // И т.д.
  }
  ```

### 6. Проверка и сохранение подписей

- [ ] Внедрить `SignVerifyService` для проверки CMS
- [ ] Внедрить `SignatureClient` для создания Signature entity
- [ ] Реализовать сохранение подписи к документу:
  ```java
  private void saveSignature(String cms, VerifyCmsResponse verifyCmsResponse,
                             Object document, String documentType) {
      // 1. Создать Signature через SignatureClient
      Signature signature = signatureClient.createSignature(
          cms,
          verifyCmsResponse,
          organization.getName()
      );

      // 2. Привязать подпись к документу
      switch (documentType) {
          case "agreement":
              Agreement agreement = (Agreement) document;
              agreement.getSignatures().add(signature);
              agreementRepository.save(agreement);
              break;
          // ... аналогично для других типов
      }
  }
  ```

### 7. Обработка ошибок

- [ ] Добавить обработку `InvalidJwtException` → 401 Unauthorized
- [ ] Добавить обработку `SessionNotFoundException` → 404
- [ ] Добавить обработку `SessionExpiredException` → 410 Gone
- [ ] Добавить обработку `InvalidSignatureException` → 403
- [ ] Добавить обработку ошибок проверки CMS → 403
- [ ] Возвращать корректные коды согласно спецификации eGov:
  - 200: успешно
  - 403: подпись не прошла валидацию

### 8. Безопасность

- [ ] Валидировать JWT токен на каждый запрос
- [ ] Проверять соответствие sessionId из токена и URL
- [ ] Проверять БИН подписанта (должен совпадать с организацией)
- [ ] Проверять метку времени (TSP) в подписи
- [ ] Проверять статус сессии (только PENDING можно подписать)

### 9. Интеграция с существующими сервисами

- [ ] Внедрить `EgovSignSessionService`
- [ ] Внедрить `AgreementService`
- [ ] Внедрить `InvoiceService`
- [ ] Внедрить `ActService`
- [ ] Внедрить `RegistryService`
- [ ] Внедрить `FileService`
- [ ] Внедрить `SignVerifyService`
- [ ] Внедрить `SignatureClient`
- [ ] Внедрить `OrganizationService`

### 10. Логирование

- [ ] Логировать запросы документов (INFO)
- [ ] Логировать прием подписанных документов (INFO)
- [ ] Логировать результат проверки подписи (INFO/ERROR)
- [ ] Логировать ошибки валидации JWT (WARN)
- [ ] Логировать детали проверки CMS (DEBUG)

### 11. Тестирование

- [ ] Unit-тесты для GET `/document`:
  - Успешное получение документа
  - Невалидный JWT токен
  - Несуществующая сессия
  - Истекшая сессия
  - Несуществующий документ

- [ ] Unit-тесты для PUT `/document`:
  - Успешное сохранение подписи
  - Невалидная подпись (403)
  - Невалидный JWT
  - Попытка подписать дважды
  - Неправильный БИН подписанта

- [ ] Integration-тесты с MockMvc:
  - End-to-end flow: GET → PUT
  - Проверка сохранения подписи в БД

### 12. Документация

- [ ] Swagger аннотации для обоих методов
- [ ] Описать формат JWT токена
- [ ] Описать коды ошибок
- [ ] Примеры запросов/ответов

## 📚 Требования из документации

### Методы подписания (signMethod)
- **CMS_WITH_DATA** ✅ - используем (подпись + данные)
- **CMS_SIGN_ONLY** - только хэш подписи
- **XML** - для XML документов
- **SIGN_BYTES_ARRAY** - массив байтов
- **MIX_SIGN** - комбинированный (с версии iOS 2.4.1 / Android 1.6.77)

### MIME типы
- `"application/pdf"` ✅ - для PDF документов (используем)
- `"text/plain"` - для текста
- `"application/xml"` - для XML

### Accept-Language Header
❗ С версии iOS 2.4.1 / Android 1.6.77 eGov Mobile отправляет заголовок:
```
Accept-Language: ru
Accept-Language: kk
Accept-Language: en
```

- [ ] Обрабатывать `Accept-Language` для мультиязычности

### Валидация подписи
Согласно "Правилам проверки подлинности ЭЦП":
- [ ] Проверка подписи через НУЦ РК (Kalkan)
- [ ] Проверка сертификата
- [ ] Проверка срока действия сертификата
- [ ] Проверка отзыва (OCSP)
- [ ] Проверка метки времени (TSP)
- [ ] Проверка БИН/ИИН

## 🔗 Зависимости

**Зависит от:**
- Task 1: `EgovSignController` (для JWT токена)
- Task 3: `EgovSignSessionService`
- Task 4: `EgovSignSession` entity
- Существующие: `SignVerifyService`, `SignatureClient`, `FileService`

**Необходимо для:**
- Frontend Task 6: QR Sign Modal (для polling статуса)
- Mobile Task 10: eGov Sign Service

## ⚠️ Важные замечания

1. **Токен авторизации**: JWT из API №1, передается в Header `Authorization: Bearer {token}`
2. **Формат данных**: Строго Base64 для `data` поля
3. **Проверка подписи**: Использовать существующий `SignVerifyService.verifyCmsWithOneSigner()`
4. **Оригинальные данные**: Для проверки CMS нужен Base64 оригинального PDF (тот же что отдали в GET)
5. **Статус 403**: Возвращать при невалидной подписи (не 400!)
6. **Version**: Всегда = 1

## 📊 Критерии приемки

- [ ] GET `/document` возвращает корректный JSON согласно спецификации eGov Mobile
- [ ] PDF конвертируется в Base64 корректно
- [ ] Meta данные заполнены для всех типов документов
- [ ] PUT `/document` принимает подписанный CMS
- [ ] Проверка подписи работает через `SignVerifyService`
- [ ] Валидная подпись сохраняется в БД как `Signature` entity
- [ ] Невалидная подпись возвращает 403 с message
- [ ] JWT токен валидируется на каждый запрос
- [ ] Статус сессии обновляется на SIGNED после успешного подписания
- [ ] Все unit и integration тесты проходят
- [ ] Логирование работает корректно

---

**Приоритет:** 🔴 Высокий
**Оценка:** 10-12 часов
**Assignee:** Backend Developer
**Зависит от:** Task 1, 3, 4
