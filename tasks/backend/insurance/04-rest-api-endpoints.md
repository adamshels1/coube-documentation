# Задача 4: REST API endpoints для страхования

## Описание
Создать REST API endpoints для работы со страхованием на фронтенде.

## Endpoints

### 1. Создание/обновление заявки со страхованием
**Изменить существующий endpoint**:
```
POST /api/transportations
PUT /api/transportations/{id}
```

**Добавить в request body**:
```json
{
  "withInsurance": true,
  // ... остальные поля заявки
}
```

**Response**:
```json
{
  "id": 123,
  "status": "INSURANCE_PENDING",
  "withInsurance": true,
  "insurancePolicy": {
    "id": 456,
    "status": "pending"
  },
  // ... остальные поля
}
```

### 2. Проверка клиента для страхования
```
POST /api/insurance/check-client/{transportationId}
```

**Response**:
```json
{
  "result": "passed", // passed | failed
  "checks": [
    {
      "clientType": "insured",
      "fullName": "ТОО Компания",
      "idNumber": "123456789012",
      "checkResult": "passed",
      "checkedAt": "2025-10-13T10:00:00"
    },
    {
      "clientType": "director",
      "fullName": "Иванов Иван Иванович",
      "idNumber": "890123456789",
      "checkResult": "passed",
      "checkedAt": "2025-10-13T10:00:01"
    }
  ],
  "message": "Все проверки пройдены успешно"
}
```

### 3. Получение документов для ознакомления
```
GET /api/insurance/documents/preview/{insurancePolicyId}
```

**Response**:
```json
{
  "applicationForm": {
    "previewUrl": "https://coube.kz/api/insurance/preview/application-form/456.pdf",
    "content": "base64_encoded_pdf_or_html"
  },
  "contract": {
    "previewUrl": "https://coube.kz/api/insurance/preview/contract/456.pdf",
    "content": "base64_encoded_pdf_or_html"
  },
  "excludedTerritories": {
    "previewUrl": "https://coube.kz/api/insurance/preview/excluded-territories.pdf"
  },
  "insurancePremium": {
    "amount": 25000,
    "currency": "KZT"
  }
}
```

### 4. Подтверждение ознакомления
```
POST /api/insurance/confirm-agreement/{insurancePolicyId}
```

**Request**:
```json
{
  "agreedToTerms": true,
  "agreedToDataProcessing": true,
  "confirmedAt": "2025-10-13T10:05:00"
}
```

### 5. Подписание документов ЭЦП
```
POST /api/insurance/sign/{insurancePolicyId}
```

**Request**:
```json
{
  "signatureData": "base64_signature_data",
  "certificateSerialNumber": "12345678",
  "signedDocuments": [
    {
      "documentType": "application_form",
      "documentTypeCode": "00086",
      "fileId": "uuid-here",
      "fileName": "application-form-signed.pdf"
    },
    {
      "documentType": "contract",
      "documentTypeCode": "00085",
      "fileId": "uuid-here",
      "fileName": "contract-signed.pdf"
    }
  ]
}
```

**Response**:
```json
{
  "status": "documents_signed",
  "message": "Документы успешно подписаны",
  "nextStep": "contract_creation"
}
```

### 6. Создание договора в страховой
```
POST /api/insurance/create-contract/{insurancePolicyId}
```

**Response**:
```json
{
  "status": "contract_created",
  "contractNumber": "ST-2025-012345",
  "message": "Договор создан в системе страховой. Ожидается подписание страховщиком."
}
```

### 7. Получение статуса страхования
```
GET /api/insurance/status/{insurancePolicyId}
```

**Response**:
```json
{
  "id": 456,
  "transportationId": 123,
  "status": "active",
  "contractNumber": "ST-2025-012345",
  "insurancePremium": 25000,
  "insuranceSum": 500000,
  "contractStartDate": "2025-10-13T00:00:00",
  "contractEndDate": "2025-10-20T23:59:59",
  "signedContractUrl": "https://coube.kz/api/files/download/uuid-here",
  "createdAt": "2025-10-13T09:00:00",
  "updatedAt": "2025-10-13T11:00:00"
}
```

### 8. Получение списка документов страхования
```
GET /api/insurance/documents/{insurancePolicyId}
```

**Response**:
```json
{
  "documents": [
    {
      "id": 1,
      "documentTypeName": "Договор подписанный ЭЦП",
      "documentTypeCode": "00085",
      "fileName": "contract-ST-2025-012345.pdf",
      "fileId": "uuid-here",
      "downloadUrl": "https://coube.kz/api/files/download/uuid-here",
      "uploadStatus": "confirmed",
      "uploadedAt": "2025-10-13T10:30:00"
    },
    {
      "id": 2,
      "documentTypeName": "Заявление, подписанное ЭЦП",
      "documentTypeCode": "00086",
      "fileName": "application-form-ST-2025-012345.pdf",
      "fileId": "uuid-here",
      "downloadUrl": "https://coube.kz/api/files/download/uuid-here",
      "uploadStatus": "confirmed",
      "uploadedAt": "2025-10-13T10:30:01"
    }
  ]
}
```

### 9. Отмена страхования
```
POST /api/insurance/cancel/{insurancePolicyId}
```

**Request**:
```json
{
  "reason": "Клиент отказался от страхования",
  "continueWithoutInsurance": true
}
```

**Response**:
```json
{
  "status": "cancelled",
  "message": "Страхование отменено. Заявка продолжит обработку без страхования.",
  "transportationStatus": "ACTIVE"
}
```

### 10. Получение истории API логов (для отладки)
```
GET /api/insurance/api-logs/{insurancePolicyId}
```

**Response**:
```json
{
  "logs": [
    {
      "id": 1,
      "apiMethod": "CheckClient",
      "status": "success",
      "httpStatus": 200,
      "requestPayload": {...},
      "responsePayload": {...},
      "createdAt": "2025-10-13T09:05:00"
    },
    {
      "id": 2,
      "apiMethod": "CreateNewDocument",
      "status": "success",
      "httpStatus": 200,
      "createdAt": "2025-10-13T10:35:00"
    }
  ]
}
```

## Controller

### InsuranceController.java
```java
@RestController
@RequestMapping("/api/insurance")
@Validated
public class InsuranceController {

    @Autowired
    private InsuranceService insuranceService;

    @PostMapping("/check-client/{transportationId}")
    public ResponseEntity<InsuranceCheckResponse> checkClient(
        @PathVariable Long transportationId
    );

    @GetMapping("/documents/preview/{insurancePolicyId}")
    public ResponseEntity<InsuranceDocumentsPreviewResponse> getDocumentsPreview(
        @PathVariable Long insurancePolicyId
    );

    @PostMapping("/confirm-agreement/{insurancePolicyId}")
    public ResponseEntity<Void> confirmAgreement(
        @PathVariable Long insurancePolicyId,
        @RequestBody @Valid ConfirmAgreementRequest request
    );

    @PostMapping("/sign/{insurancePolicyId}")
    public ResponseEntity<SignatureResponse> signDocuments(
        @PathVariable Long insurancePolicyId,
        @RequestBody @Valid SignDocumentsRequest request
    );

    @PostMapping("/create-contract/{insurancePolicyId}")
    public ResponseEntity<CreateContractResponse> createContract(
        @PathVariable Long insurancePolicyId
    );

    @GetMapping("/status/{insurancePolicyId}")
    public ResponseEntity<InsurancePolicyDTO> getStatus(
        @PathVariable Long insurancePolicyId
    );

    @GetMapping("/documents/{insurancePolicyId}")
    public ResponseEntity<InsuranceDocumentsResponse> getDocuments(
        @PathVariable Long insurancePolicyId
    );

    @PostMapping("/cancel/{insurancePolicyId}")
    public ResponseEntity<CancelInsuranceResponse> cancelInsurance(
        @PathVariable Long insurancePolicyId,
        @RequestBody @Valid CancelInsuranceRequest request
    );

    @GetMapping("/api-logs/{insurancePolicyId}")
    public ResponseEntity<InsuranceApiLogsResponse> getApiLogs(
        @PathVariable Long insurancePolicyId
    );
}
```

## Безопасность
- Все endpoints требуют аутентификации
- Проверка прав доступа к заявке
- Rate limiting для API вызовов

## Валидация
- Проверка существования заявки
- Проверка статуса перед выполнением операции
- Валидация подписи ЭЦП

## Обработка ошибок
```java
@ExceptionHandler(InsuranceException.class)
public ResponseEntity<ErrorResponse> handleInsuranceException(InsuranceException e) {
    return ResponseEntity
        .status(HttpStatus.BAD_REQUEST)
        .body(new ErrorResponse(e.getCode(), e.getMessage()));
}
```

## Коды ошибок
- `INSURANCE_CHECK_FAILED` - Проверка клиента не пройдена
- `INSURANCE_SIGNATURE_INVALID` - Неверная ЭЦП
- `INSURANCE_API_ERROR` - Ошибка API страховой
- `INSURANCE_NOT_FOUND` - Страховка не найдена
- `INSURANCE_INVALID_STATUS` - Неверный статус для операции
