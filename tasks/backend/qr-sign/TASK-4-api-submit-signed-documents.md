# TASK-4: API №2 - Прием подписанных документов

## Описание
Реализовать API для приема подписанных документов от eGov Mobile и валидацию ЭЦП согласно требованиям НУЦ РК.

## Приоритет
Critical

## Story Points
13

## API Спецификация

### Эндпоинт
```
PUT /api/egov-sign/documents/{sessionId}
```

### Path Parameters
| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| sessionId | Long | Да | ID сессии подписания |

### Request Headers
```
Content-Type: application/json
Authorization: Bearer {token}  // если auth_type = TOKEN
Accept-Language: ru | kk | en
```

### Request Body (для CMS_WITH_DATA)
```json
{
  "signMethod": "CMS_WITH_DATA",
  "version": 1,
  "documentsToSign": [
    {
      "id": "doc-1",
      "document": {
        "mime": "application/pdf",
        "data": "MIIGhwYJKoZIhvcNAQcCoIIG..." // подписанный base64
      }
    }
  ]
}
```

### Request Body (для XML)
```json
{
  "signMethod": "XML",
  "version": 1,
  "documentsToSign": [
    {
      "id": "doc-1",
      "documentXml": "<contract>...<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\">...</Signature></contract>"
    }
  ]
}
```

### Request Body (для SIGN_BYTES_ARRAY)
```json
{
  "signMethod": "SIGN_BYTES_ARRAY",
  "version": 1,
  "documentsToSign": [
    {
      "id": "doc-1",
      "document": {
        "mime": "application/pdf",
        "data": "{\"signature\":\"MIIGhw...\",\"certificate\":\"MIIFdDCC...\"}" // JSON строка
      }
    }
  ]
}
```

### Response 200 OK
```json
{
  "status": "success",
  "message": "Документы успешно подписаны"
}
```

### Response 403 Forbidden
```json
{
  "status": "failed",
  "message": "Подпись не прошла валидацию: Сертификат отозван"
}
```

### Response 400 Bad Request
```json
{
  "status": "failed",
  "message": "Некорректный формат данных"
}
```

## DTO классы

### SignedDocumentsRequest.java
```java
@Data
public class SignedDocumentsRequest {
    @NotNull
    private String signMethod;

    @NotNull
    private Integer version;

    @NotNull
    @NotEmpty
    private List<SignedDocumentDTO> documentsToSign;
}

@Data
public class SignedDocumentDTO {
    @NotNull
    private String id;

    private String documentXml; // для XML signMethod

    private DocumentFileDTO document; // для остальных
}

@Data
public class SigningResultDTO {
    private String status; // "success" или "failed"
    private String message;
}
```

## Сервис валидации подписей

### SignatureValidationService.java
```java
@Service
@Slf4j
public class SignatureValidationService {

    @Autowired
    private KalkanIntegrationService kalkanService;

    @Autowired
    private AuditLoggingService auditService;

    public ValidationResult validateSignature(SignedDocumentDTO document, String signMethod) {
        try {
            // 1. Извлечь подпись и сертификат
            SignatureData sigData = extractSignature(document, signMethod);

            // 2. Проверить издателя (НУЦ РК)
            if (!isIssuedByNUC(sigData.getCertificate())) {
                return ValidationResult.failed("Сертификат не выдан НУЦ РК");
            }

            // 3. Проверить срок действия сертификата
            sigData.getCertificate().checkValidity(new Date());

            // 4. Проверить цепочку сертификатов
            if (!kalkanService.verifyCertificateChain(sigData.getCertificate())) {
                return ValidationResult.failed("Некорректная цепочка сертификатов");
            }

            // 5. OCSP проверка с fallback на CRL
            String certSerial = sigData.getCertificate().getSerialNumber().toString();
            CertificateStatus status = checkCertificateStatus(certSerial);

            if (status == CertificateStatus.REVOKED) {
                auditService.logOCSPRequest(certSerial, "REVOKED");
                return ValidationResult.failed("Сертификат отозван");
            }

            auditService.logOCSPRequest(certSerial, "VALID");

            // 6. Проверить KeyUsage
            if (!hasRequiredKeyUsage(sigData.getCertificate())) {
                return ValidationResult.failed("Неверный KeyUsage сертификата");
            }

            // 7. Проверить алгоритм (ГОСТ 34.310-2004)
            if (!isGOSTAlgorithm(sigData.getCertificate())) {
                return ValidationResult.failed("Некорректный алгоритм подписи");
            }

            // 8. Проверить timestamp НУЦ РК
            if (!validateTimestamp(sigData)) {
                return ValidationResult.failed("Некорректный timestamp");
            }

            // 9. Проверить саму подпись
            if (!verifySignatureData(sigData, signMethod)) {
                return ValidationResult.failed("Подпись не соответствует документу");
            }

            return ValidationResult.success(sigData.getCertificate(), certSerial);

        } catch (CertificateExpiredException e) {
            log.error("Certificate expired", e);
            return ValidationResult.failed("Срок действия сертификата истек");
        } catch (Exception e) {
            log.error("Signature validation error", e);
            return ValidationResult.failed("Ошибка валидации: " + e.getMessage());
        }
    }

    private SignatureData extractSignature(SignedDocumentDTO doc, String signMethod) {
        if ("XML".equals(signMethod)) {
            return extractFromXml(doc.getDocumentXml());
        } else if ("SIGN_BYTES_ARRAY".equals(signMethod)) {
            return extractFromBytesArray(doc.getDocument().getData());
        } else {
            return extractFromCMS(doc.getDocument().getData());
        }
    }

    private CertificateStatus checkCertificateStatus(String certSerial) {
        // Сначала OCSP
        try {
            OCSPResponse ocspResp = kalkanService.checkOCSP(certSerial);
            if (ocspResp != null) {
                return ocspResp.getStatus();
            }
        } catch (Exception e) {
            log.warn("OCSP failed, falling back to CRL", e);
        }

        // Fallback на CRL
        return kalkanService.checkCRL(certSerial);
    }

    private boolean isIssuedByNUC(X509Certificate cert) {
        String issuer = cert.getIssuerDN().getName();
        return issuer.contains("НУЦ") || issuer.contains("NCA") || issuer.contains("ҰЛТТЫҚ КУӘЛАНДЫРУШЫ ОРТАЛЫҚ");
    }

    private boolean hasRequiredKeyUsage(X509Certificate cert) {
        boolean[] keyUsage = cert.getKeyUsage();
        // digitalSignature (0) и nonRepudiation (1)
        return keyUsage != null && keyUsage.length > 1 && keyUsage[0] && keyUsage[1];
    }

    private boolean isGOSTAlgorithm(X509Certificate cert) {
        String sigAlg = cert.getSigAlgName();
        return sigAlg.contains("GOST") || sigAlg.contains("34.310");
    }
}

@Data
@AllArgsConstructor
public class ValidationResult {
    private boolean valid;
    private String errorMessage;
    private X509Certificate certificate;
    private String certificateSerial;

    public static ValidationResult success(X509Certificate cert, String serial) {
        return new ValidationResult(true, null, cert, serial);
    }

    public static ValidationResult failed(String error) {
        return new ValidationResult(false, error, null, null);
    }
}

@Data
class SignatureData {
    private byte[] signature;
    private X509Certificate certificate;
    private byte[] originalData;
    private Timestamp timestamp;
}
```

### KalkanIntegrationService.java
```java
@Service
public class KalkanIntegrationService {

    @Value("${app.nuc.ocsp-url}")
    private String ocspUrl;

    @Value("${app.nuc.crl-url}")
    private String crlUrl;

    // OCSP запрос
    public OCSPResponse checkOCSP(String certificateSerial) throws Exception {
        // Реализация OCSP запроса к НУЦ РК
        // URL: http://ocsp.pki.gov.kz
        OCSPReq request = buildOCSPRequest(certificateSerial);

        HttpClient client = HttpClient.newHttpClient();
        HttpRequest httpReq = HttpRequest.newBuilder()
            .uri(URI.create(ocspUrl))
            .header("Content-Type", "application/ocsp-request")
            .POST(HttpRequest.BodyPublishers.ofByteArray(request.getEncoded()))
            .build();

        HttpResponse<byte[]> response = client.send(httpReq, HttpResponse.BodyHandlers.ofByteArray());

        OCSPResp ocspResp = new OCSPResp(response.body());
        return parseOCSPResponse(ocspResp);
    }

    // Проверка по CRL
    public CertificateStatus checkCRL(String certificateSerial) {
        try {
            // Скачать Base CRL и Delta CRL
            X509CRL baseCRL = downloadCRL(crlUrl + "/base.crl");
            X509CRL deltaCRL = downloadCRL(crlUrl + "/delta.crl");

            BigInteger serial = new BigInteger(certificateSerial);

            // Проверить в Base CRL
            if (baseCRL.getRevokedCertificate(serial) != null) {
                return CertificateStatus.REVOKED;
            }

            // Проверить в Delta CRL
            if (deltaCRL != null && deltaCRL.getRevokedCertificate(serial) != null) {
                return CertificateStatus.REVOKED;
            }

            return CertificateStatus.VALID;
        } catch (Exception e) {
            log.error("CRL check failed", e);
            return CertificateStatus.UNKNOWN;
        }
    }

    // Проверка цепочки сертификатов
    public boolean verifyCertificateChain(X509Certificate cert) {
        try {
            // Построить цепочку до корневого НУЦ РК
            CertPathValidator validator = CertPathValidator.getInstance("PKIX");
            CertPath certPath = buildCertPath(cert);

            PKIXParameters params = new PKIXParameters(getTrustedRootCertificates());
            params.setRevocationEnabled(false); // мы уже проверили через OCSP/CRL

            validator.validate(certPath, params);
            return true;
        } catch (Exception e) {
            log.error("Certificate chain validation failed", e);
            return false;
        }
    }

    private Set<TrustAnchor> getTrustedRootCertificates() {
        // Загрузить корневые сертификаты НУЦ РК
        // Обычно это RSA 2048, GOST корневые сертификаты
        return trustedCerts;
    }
}
```

## Основной сервис

### EgovSigningService.java (расширение)
```java
@Service
@Transactional
public class EgovSigningService {

    @Autowired
    private SignatureValidationService validationService;

    @Autowired
    private SignatureRepository signatureRepository;

    @Autowired
    private AuditLoggingService auditService;

    public SigningResultDTO submitSignedDocuments(Long sessionId, SignedDocumentsRequest request) {
        // 1. Получить сессию
        EgovSigningSession session = sessionRepository.findById(sessionId)
            .orElseThrow(() -> new SessionNotFoundException());

        if (!"PENDING".equals(session.getStatus())) {
            throw new InvalidSessionStatusException("Сессия уже обработана");
        }

        // 2. Валидировать каждый документ
        List<ValidationResult> results = new ArrayList<>();
        for (SignedDocumentDTO doc : request.getDocumentsToSign()) {
            ValidationResult result = validationService.validateSignature(doc, request.getSignMethod());
            results.add(result);

            if (!result.isValid()) {
                // Логировать ошибку
                auditService.logSigningFailure(
                    sessionId,
                    extractIIN(result.getCertificate()),
                    getDocumentId(session),
                    result.getErrorMessage()
                );

                // Обновить статус сессии
                session.setStatus("FAILED");
                sessionRepository.save(session);

                return SigningResultDTO.builder()
                    .status("failed")
                    .message("Подпись не прошла валидацию: " + result.getErrorMessage())
                    .build();
            }
        }

        // 3. Все подписи валидны - сохранить
        for (ValidationResult result : results) {
            Signature signature = new Signature();
            signature.setSigningSessionId(sessionId);
            signature.setSigningMethod("EGOV_QR");
            signature.setCertificateSerial(result.getCertificateSerial());
            signature.setIin(extractIIN(result.getCertificate()));
            signature.setValidationStatus("VALID");
            signature.setValidatedAt(LocalDateTime.now());
            // ... другие поля

            signatureRepository.save(signature);

            // Логировать успех
            auditService.logSigningSuccess(
                sessionId,
                signature.getIin(),
                getDocumentId(session),
                signature.getCertificateSerial()
            );
        }

        // 4. Обновить сессию
        session.setStatus("SIGNED");
        session.setSignedAt(LocalDateTime.now());
        session.setActualSignersCount(results.size());
        sessionRepository.save(session);

        // 5. Обновить статус основного документа (договор/счет/акт)
        updateDocumentStatus(session);

        return SigningResultDTO.builder()
            .status("success")
            .message("Документы успешно подписаны")
            .build();
    }

    private String extractIIN(X509Certificate cert) {
        if (cert == null) return null;
        // Извлечь ИИН из Subject DN
        String dn = cert.getSubjectDN().getName();
        // Формат: CN=..., SERIALNUMBER=IIN123456789012, ...
        Pattern pattern = Pattern.compile("SERIALNUMBER=IIN(\\d{12})");
        Matcher matcher = pattern.matcher(dn);
        if (matcher.find()) {
            return matcher.group(1);
        }
        return null;
    }
}
```

## Контроллер

### EgovSignController.java (расширение)
```java
@PutMapping("/documents/{sessionId}")
@Operation(summary = "Принять подписанные документы (API №2 PUT)")
public ResponseEntity<SigningResultDTO> submitSignedDocuments(
    @PathVariable Long sessionId,
    @RequestBody @Valid SignedDocumentsRequest request
) {
    SigningResultDTO result = signingService.submitSignedDocuments(sessionId, request);

    if ("success".equals(result.getStatus())) {
        return ResponseEntity.ok(result);
    } else {
        return ResponseEntity.status(403).body(result);
    }
}
```

## Критерии приемки
- ✅ Реализован PUT /api/egov-sign/documents/{sessionId}
- ✅ Валидация подписей согласно требованиям НУЦ РК
- ✅ Проверка издателя, срока действия, цепочки сертификатов
- ✅ OCSP интеграция с fallback на CRL
- ✅ Проверка KeyUsage и алгоритма ГОСТ
- ✅ Сохранение подписей в БД
- ✅ Обновление статуса сессии и документа
- ✅ Логирование успеха/ошибок в SIEM
- ✅ Обработка всех типов подписания (XML, CMS, BYTES)
- ✅ Unit и integration тесты

## Зависимости
- TASK-1 (database schema)
- TASK-3 (API get documents)

## Связанная документация
- [Flow диаграмма 5.1](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#51-отправка-и-валидация-подписанных-документов)
- [Flow диаграмма 5.2](../../business_analysis/converted/QR%20sign/QR-Signing-Flow-Diagrams.md#52-процесс-валидации-эцп-детализация)
