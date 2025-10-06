# Отчеты заказчика - Логи подписей документов

## Описание задачи
Реализовать API для отчета "Логи подписей" с трекингом всех цифровых подписей документов, аудитом безопасности и соответствием требованиям ЭЦП в Казахстане.

## Frontend UI референс
- Компонент: `SignatureLogsReport.vue` (существующий)
- Фильтры: тип документа, статус подписи, подписант, период
- Метрики: всего подписей, валидных подписей, просроченных сертификатов, ошибок верификации
- Аудит: история подписей, цепочка доверия, статус сертификатов
- Compliance: соответствие казахстанскому законодательству об ЭЦП

## Эндпоинты для реализации

### 1. GET `/api/reports/signature-logs/list`
Получение логов подписей документов

**Параметры запроса:**
```json
{
  "documentType": "string (optional)", // contract, invoice, act, agreement
  "signatureStatus": "string (optional)", // valid, invalid, expired, revoked, pending
  "signerId": "number (optional)",
  "certificateType": "string (optional)", // kalkan, rsa, gost
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "page": "number (default: 0)",
  "size": "number (default: 20)"
}
```

**Ответ:**
```json
{
  "data": [
    {
      "id": "number",
      "documentId": "number",
      "documentType": "string",
      "documentNumber": "string",
      "signerName": "string",
      "signerBin": "string",
      "signerRole": "string", // customer, executor, platform_admin
      "signatureStatus": "string",
      "signatureMethod": "string", // kalkan, mobile_signature, cloud_signature
      "signatureTimestamp": "string",
      "certificateInfo": {
        "serialNumber": "string",
        "issuer": "string", // НУЦ РК, Казахтелеком и др.
        "subject": "string",
        "validFrom": "string",
        "validTo": "string",
        "keyUsage": ["string"],
        "isRevoked": "boolean",
        "certificateChain": ["string"]
      },
      "verification": {
        "isValid": "boolean",
        "verificationTime": "string",
        "verificationErrors": ["string"],
        "timestampValid": "boolean",
        "certificateValid": "boolean",
        "signatureIntact": "boolean"
      },
      "compliance": {
        "lawCompliant": "boolean", // соответствие закону РК об ЭЦП
        "archivalRequirement": "boolean", // требование архивирования
        "legalForce": "boolean" // юридическая сила
      },
      "technicalDetails": {
        "signatureAlgorithm": "string",
        "hashAlgorithm": "string",
        "signatureFormat": "string", // CAdES, XAdES, PAdES
        "timestampProvider": "string",
        "fileHash": "string"
      }
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalSignatures": "number",
    "validSignatures": "number",
    "invalidSignatures": "number",
    "expiredCertificates": "number",
    "revokedCertificates": "number",
    "complianceRate": "number" // процент
  }
}
```

### 2. GET `/api/reports/signature-logs/audit`
Получение аудиторского отчета по подписям

**Ответ:**
```json
{
  "auditSummary": {
    "auditPeriod": {
      "from": "string",
      "to": "string"
    },
    "totalDocuments": "number",
    "signedDocuments": "number",
    "unsignedDocuments": "number",
    "signingRate": "number", // процент
    "complianceScore": "number" // 0-100
  },
  "certificateAnalysis": {
    "activeCertificates": "number",
    "expiringSoon": "number", // истекают в течение 30 дней
    "expired": "number",
    "revoked": "number",
    "providers": [
      {
        "issuer": "string",
        "count": "number",
        "validityRate": "number"
      }
    ]
  },
  "signatureDistribution": {
    "byDocumentType": [
      {
        "documentType": "string",
        "totalSignatures": "number",
        "validSignatures": "number",
        "invalidSignatures": "number"
      }
    ],
    "bySignerRole": [
      {
        "role": "string",
        "signatureCount": "number",
        "errorRate": "number"
      }
    ],
    "bySignatureMethod": [
      {
        "method": "string",
        "usage": "number",
        "successRate": "number"
      }
    ]
  },
  "securityEvents": [
    {
      "eventType": "string", // certificate_expired, signature_invalid, suspicious_activity
      "description": "string",
      "severity": "string", // low, medium, high, critical
      "timestamp": "string",
      "affectedDocuments": "number"
    }
  ]
}
```

### 3. GET `/api/reports/signature-logs/compliance`
Получение отчета о соответствии требованиям ЭЦП

**Ответ:**
```json
{
  "compliance": {
    "lawCompliance": {
      "score": "number", // 0-100
      "requirements": [
        {
          "requirement": "string",
          "status": "string", // compliant, non_compliant, partial
          "description": "string",
          "evidence": ["string"]
        }
      ]
    },
    "technicalStandards": {
      "gost34102012": {
        "compliant": "boolean",
        "usage": "number", // процент использования
        "recommendation": "string"
      },
      "rsa2048": {
        "compliant": "boolean", 
        "usage": "number",
        "recommendation": "string"
      },
      "timestamping": {
        "used": "boolean",
        "provider": "string",
        "coverage": "number" // процент документов с метками времени
      }
    },
    "archival": {
      "archivalPolicy": "boolean",
      "storageCompliance": "boolean",
      "retentionPeriod": "number", // лет
      "backupProcedure": "boolean"
    },
    "recommendations": [
      {
        "priority": "string", // high, medium, low
        "issue": "string",
        "solution": "string",
        "deadline": "string"
      }
    ]
  }
}
```

### 4. GET `/api/reports/signature-logs/verification`
Массовая верификация подписей

**Параметры запроса:**
```json
{
  "documentIds": ["number"], // массив ID документов для проверки
  "verificationLevel": "string" // basic, full, forensic
}
```

**Ответ:**
```json
{
  "verificationResults": [
    {
      "documentId": "number",
      "documentNumber": "string",
      "overallStatus": "string", // valid, invalid, warning
      "signatures": [
        {
          "signatureId": "number",
          "signerName": "string",
          "status": "string",
          "checks": {
            "signatureIntegrity": "boolean",
            "certificateValidity": "boolean",
            "certificateChain": "boolean",
            "revocationStatus": "boolean",
            "timestampVerification": "boolean",
            "documentIntegrity": "boolean"
          },
          "errors": ["string"],
          "warnings": ["string"]
        }
      ],
      "verificationTimestamp": "string",
      "verificationReport": "string" // ссылка на детальный отчет
    }
  ],
  "summary": {
    "totalDocuments": "number",
    "validDocuments": "number",
    "invalidDocuments": "number",
    "documentsWithWarnings": "number"
  }
}
```

### 5. GET `/api/reports/signature-logs/charts`
Получение данных для графиков подписей

**Ответ:**
```json
{
  "signatureTrends": {
    "dates": ["string"],
    "totalSignatures": ["number"],
    "validSignatures": ["number"],
    "invalidSignatures": ["number"]
  },
  "certificateProviders": {
    "providers": ["string"],
    "usage": ["number"],
    "reliability": ["number"]
  },
  "documentTypeDistribution": {
    "types": ["string"],
    "signedCount": ["number"],
    "unsignedCount": ["number"]
  },
  "complianceMetrics": {
    "months": ["string"],
    "complianceScore": ["number"],
    "target": ["number"] // целевой уровень
  }
}
```

### 6. GET `/api/reports/signature-logs/export`
Экспорт логов подписей в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с детальными логами

## SQL запросы (базовая логика)

### Основной запрос для логов подписей
```sql
SELECT 
    ds.id,
    d.id as documentId,
    d.document_type as documentType,
    d.document_number as documentNumber,
    u.full_name as signerName,
    o.bin as signerBin,
    ds.signer_role as signerRole,
    ds.signature_status as signatureStatus,
    ds.signature_method as signatureMethod,
    ds.signed_at as signatureTimestamp,
    
    -- Информация о сертификате
    ds.certificate_serial as certificateSerial,
    ds.certificate_issuer as certificateIssuer,
    ds.certificate_subject as certificateSubject,
    ds.certificate_valid_from as certificateValidFrom,
    ds.certificate_valid_to as certificateValidTo,
    ds.certificate_key_usage as certificateKeyUsage,
    ds.is_certificate_revoked as isCertificateRevoked,
    
    -- Информация о верификации
    ds.is_signature_valid as isSignatureValid,
    ds.verification_timestamp as verificationTimestamp,
    ds.verification_errors as verificationErrors,
    ds.is_timestamp_valid as isTimestampValid,
    ds.is_certificate_valid as isCertificateValid,
    ds.is_signature_intact as isSignatureIntact,
    
    -- Соответствие требованиям
    CASE 
        WHEN ds.signature_algorithm IN ('GOST34.10-2012', 'RSA-2048') 
        AND ds.is_signature_valid = true 
        AND ds.timestamp_provider IS NOT NULL
        THEN true 
        ELSE false 
    END as lawCompliant,
    
    -- Технические детали
    ds.signature_algorithm as signatureAlgorithm,
    ds.hash_algorithm as hashAlgorithm,
    ds.signature_format as signatureFormat,
    ds.timestamp_provider as timestampProvider,
    ds.file_hash as fileHash
    
FROM signature.document_signature ds
    LEFT JOIN signature.document d ON ds.document_id = d.id
    LEFT JOIN user.user u ON ds.signer_user_id = u.id
    LEFT JOIN user.organization o ON u.organization_id = o.id
WHERE 
    ($organizationId IS NULL OR o.id = $organizationId OR d.organization_id = $organizationId)
    AND ($documentType IS NULL OR d.document_type = $documentType)
    AND ($signatureStatus IS NULL OR ds.signature_status = $signatureStatus)
    AND ($signerId IS NULL OR ds.signer_user_id = $signerId)
    AND ($certificateType IS NULL OR 
        CASE 
            WHEN ds.signature_algorithm LIKE '%GOST%' THEN 'gost'
            WHEN ds.signature_algorithm LIKE '%RSA%' THEN 'rsa'
            WHEN ds.signature_method = 'kalkan' THEN 'kalkan'
            ELSE 'other'
        END = $certificateType)
    AND ($dateFrom IS NULL OR ds.signed_at >= $dateFrom)
    AND ($dateTo IS NULL OR ds.signed_at <= $dateTo)
ORDER BY ds.signed_at DESC;
```

### Запрос для аудиторского анализа
```sql
WITH signature_stats AS (
    SELECT 
        COUNT(*) as totalSignatures,
        COUNT(CASE WHEN ds.is_signature_valid = true THEN 1 END) as validSignatures,
        COUNT(CASE WHEN ds.is_signature_valid = false THEN 1 END) as invalidSignatures,
        COUNT(CASE WHEN ds.certificate_valid_to < NOW() THEN 1 END) as expiredCertificates,
        COUNT(CASE WHEN ds.is_certificate_revoked = true THEN 1 END) as revokedCertificates,
        COUNT(DISTINCT ds.document_id) as signedDocuments
    FROM signature.document_signature ds
        LEFT JOIN signature.document d ON ds.document_id = d.id
    WHERE d.organization_id = $organizationId
        AND ds.signed_at >= $dateFrom
        AND ds.signed_at <= $dateTo
),
document_stats AS (
    SELECT 
        COUNT(*) as totalDocuments
    FROM signature.document d
    WHERE d.organization_id = $organizationId
        AND d.created_at >= $dateFrom
        AND d.created_at <= $dateTo
),
certificate_providers AS (
    SELECT 
        ds.certificate_issuer,
        COUNT(*) as certificateCount,
        ROUND((COUNT(CASE WHEN ds.is_signature_valid = true THEN 1 END)::float / COUNT(*)) * 100, 1) as validityRate
    FROM signature.document_signature ds
        LEFT JOIN signature.document d ON ds.document_id = d.id
    WHERE d.organization_id = $organizationId
        AND ds.signed_at >= $dateFrom
        AND ds.signed_at <= $dateTo
    GROUP BY ds.certificate_issuer
),
security_events AS (
    SELECT 
        'certificate_expired' as eventType,
        'Истек срок действия сертификата' as description,
        'medium' as severity,
        MAX(ds.signed_at) as timestamp,
        COUNT(*) as affectedDocuments
    FROM signature.document_signature ds
        LEFT JOIN signature.document d ON ds.document_id = d.id
    WHERE d.organization_id = $organizationId
        AND ds.certificate_valid_to < NOW()
        AND ds.signed_at >= $dateFrom
    
    UNION ALL
    
    SELECT 
        'signature_invalid' as eventType,
        'Обнаружены недействительные подписи' as description,
        'high' as severity,
        MAX(ds.signed_at) as timestamp,
        COUNT(*) as affectedDocuments
    FROM signature.document_signature ds
        LEFT JOIN signature.document d ON ds.document_id = d.id
    WHERE d.organization_id = $organizationId
        AND ds.is_signature_valid = false
        AND ds.signed_at >= $dateFrom
)
SELECT 
    ss.*,
    ds.totalDocuments,
    cp.certificate_issuer,
    cp.certificateCount,
    cp.validityRate,
    se.eventType,
    se.description,
    se.severity,
    se.timestamp,
    se.affectedDocuments
FROM signature_stats ss
    CROSS JOIN document_stats ds
    LEFT JOIN certificate_providers cp ON true
    LEFT JOIN security_events se ON true;
```

## Необходимые таблицы БД

### `signature.document` - документы для подписи
```sql
CREATE SCHEMA IF NOT EXISTS signature;

CREATE TABLE signature.document (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    document_type VARCHAR(30) NOT NULL, -- contract, invoice, act, agreement
    document_number VARCHAR(100) NOT NULL,
    document_title VARCHAR(255),
    file_path VARCHAR(500),
    file_hash VARCHAR(128), -- SHA-256 хеш файла
    file_size BIGINT,
    mime_type VARCHAR(100),
    requires_signature BOOLEAN DEFAULT true,
    signature_order INTEGER[], -- порядок подписания
    status VARCHAR(20) DEFAULT 'draft', -- draft, ready_for_signing, signed, archived
    created_by BIGINT REFERENCES user.user(id),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `signature.document_signature` - подписи документов
```sql
CREATE TABLE signature.document_signature (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT REFERENCES signature.document(id),
    signer_user_id BIGINT REFERENCES user.user(id),
    signer_role VARCHAR(30) NOT NULL, -- customer, executor, platform_admin, witness
    signature_method VARCHAR(30) NOT NULL, -- kalkan, mobile_signature, cloud_signature
    signature_status VARCHAR(20) DEFAULT 'pending', -- pending, valid, invalid, expired, revoked
    
    -- Данные подписи
    signature_data TEXT, -- Base64 encoded signature
    signature_algorithm VARCHAR(50), -- GOST34.10-2012, RSA-2048, etc.
    hash_algorithm VARCHAR(30), -- SHA-256, GOST34.11-2012
    signature_format VARCHAR(20), -- CAdES-BES, CAdES-T, XAdES, PAdES
    
    -- Сертификат
    certificate_data TEXT, -- Base64 encoded certificate
    certificate_serial VARCHAR(100),
    certificate_issuer VARCHAR(255),
    certificate_subject VARCHAR(255),
    certificate_valid_from TIMESTAMP,
    certificate_valid_to TIMESTAMP,
    certificate_key_usage TEXT[],
    is_certificate_revoked BOOLEAN DEFAULT false,
    
    -- Временная метка
    timestamp_data TEXT, -- TSA timestamp
    timestamp_provider VARCHAR(100),
    timestamp_algorithm VARCHAR(50),
    
    -- Верификация
    is_signature_valid BOOLEAN,
    is_timestamp_valid BOOLEAN,
    is_certificate_valid BOOLEAN,
    is_signature_intact BOOLEAN,
    verification_timestamp TIMESTAMP,
    verification_errors TEXT[],
    verification_warnings TEXT[],
    
    -- Метаданные
    signed_at TIMESTAMP,
    signed_from_ip INET,
    user_agent TEXT,
    signing_device VARCHAR(100),
    
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `signature.certificate_revocation` - отозванные сертификаты
```sql
CREATE TABLE signature.certificate_revocation (
    id BIGSERIAL PRIMARY KEY,
    certificate_serial VARCHAR(100) NOT NULL,
    certificate_issuer VARCHAR(255) NOT NULL,
    revocation_date TIMESTAMP NOT NULL,
    revocation_reason VARCHAR(50), -- key_compromise, ca_compromise, cessation_of_operation, etc.
    crl_url VARCHAR(500), -- URL списка отозванных сертификатов
    ocsp_url VARCHAR(500), -- URL OCSP сервиса
    checked_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(certificate_serial, certificate_issuer)
);
```

### `signature.compliance_check` - проверки соответствия
```sql
CREATE TABLE signature.compliance_check (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT REFERENCES signature.document(id),
    check_type VARCHAR(30) NOT NULL, -- law_compliance, technical_standards, archival
    check_result VARCHAR(20) NOT NULL, -- pass, fail, warning
    check_details JSONB,
    recommendations TEXT[],
    checked_by VARCHAR(50), -- system, auditor
    checked_at TIMESTAMP DEFAULT NOW()
);
```

## Техническая реализация

1. Создать схему `signature` в БД
2. Создать контроллер `SignatureLogsReportController`  
3. Создать сервис `SignatureLogsReportService`
4. Интегрировать с библиотеками верификации ЭЦП (Kalkan, BouncyCastle)
5. Реализовать автоматическую проверку отзыва сертификатов
6. Добавить валидацию временных меток
7. Создать систему мониторинга истечения сертификатов
8. Реализовать compliance проверки по казахстанскому законодательству

## Интеграция с Kalkan

### Сервис верификации подписей
```java
@Service
public class KalkanSignatureVerificationService {
    
    public SignatureVerificationResult verifySignature(
            byte[] documentData, 
            byte[] signatureData, 
            byte[] certificateData) {
        
        try {
            // Инициализация Kalkan
            KalkanCrypt kalkan = new KalkanCrypt();
            
            // Верификация подписи
            boolean isValid = kalkan.verifyData(documentData, signatureData, certificateData);
            
            // Проверка сертификата
            X509Certificate cert = kalkan.loadCertificate(certificateData);
            boolean isCertValid = kalkan.verifyCertificate(cert);
            
            // Проверка отзыва через OCSP
            boolean isRevoked = checkRevocationStatus(cert);
            
            // Проверка временной метки
            boolean isTimestampValid = verifyTimestamp(signatureData);
            
            return SignatureVerificationResult.builder()
                .isSignatureValid(isValid)
                .isCertificateValid(isCertValid)
                .isRevoked(isRevoked)
                .isTimestampValid(isTimestampValid)
                .build();
                
        } catch (Exception e) {
            log.error("Ошибка верификации подписи: {}", e.getMessage());
            return SignatureVerificationResult.invalid(e.getMessage());
        }
    }
    
    private boolean checkRevocationStatus(X509Certificate cert) {
        // Проверка через OCSP или CRL
        // Реализация зависит от используемого провайдера
        return false;
    }
    
    private boolean verifyTimestamp(byte[] signatureData) {
        // Верификация временной метки TSA
        return true;
    }
}
```

## Критерии приемки

- ✅ API корректно отслеживает все подписи документов
- ✅ Верификация подписей работает с казахстанскими сертификатами
- ✅ Проверка отзыва сертификатов выполняется автоматически
- ✅ Соответствие требованиям закона РК об ЭЦП проверяется
- ✅ Аудиторские отчеты содержат всю необходимую информацию
- ✅ Мониторинг истечения сертификатов настроен
- ✅ Массовая верификация работает эффективно
- ✅ Экспорт включает все детали для аудита
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для больших объемов подписей