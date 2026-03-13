# Задача 3: Бизнес-логика страхования

## Описание
Реализовать сервисный слой для обработки процесса страхования грузов.

## Основной флоу

### 1. Создание заявки со страхованием
**Endpoint**: `POST /api/transportations`

**Изменения**:
- Добавить поле `withInsurance: boolean` в запрос создания заявки
- Если `withInsurance = true`:
  - Создать запись в `insurance_policies` со статусом `pending`
  - Заявка получает промежуточный статус (например, `INSURANCE_PENDING`)
  - Запустить процесс страхования

### 2. Процесс страхования (InsuranceService)

#### Шаг 1: Проверка клиента (CheckClient)
```java
public InsuranceCheckResult checkClientForInsurance(Long transportationId) {
    // 1. Получить данные заявки и организации
    Transportation transportation = transportationRepository.findById(transportationId);
    Organization organization = transportation.getOrganization();

    // 2. Проверить страхователя (owner организации)
    CheckClientResponse insurerCheck = insuranceApiClient.checkClient(
        buildCheckRequest(organization)
    );

    // 3. Проверить застрахованного (если отличается)
    // 4. Проверить выгодоприобретателя (если указан)
    // 5. Проверить бенефициарного собственника
    // 6. Проверить первого руководителя (CEO)

    // 7. Сохранить результаты проверок в insurance_client_checks

    // 8. Если хотя бы одна проверка failed:
    //    - Обновить статус insurance_policies -> 'client_check_failed'
    //    - Обновить статус заявки -> 'INSURANCE_REJECTED'
    //    - Отправить уведомление клиенту
    //    - return CheckResult.FAILED

    // 9. Если все проверки passed:
    //    - return CheckResult.PASSED
}
```

**ВАЖНО**: Если проверка не прошла - отказ от страхования, заявка может продолжить БЕЗ страхования.

#### Шаг 2: Отображение документов для ознакомления
**Frontend задача**: Показать пользователю:
- Заявление-анкету (драфт, предзаполненный)
- Договор страхования (драфт, предзаполненный)
- Приложение "Исключенные территории"
- Чекбокс согласия с условиями
- Сумма страховой премии

#### Шаг 3: Подписание документов ЭЦП
```java
public void signInsuranceDocuments(Long insurancePolicyId, SignatureData signatureData) {
    // 1. Подписать заявление-анкету ЭЦП
    // 2. Подписать договор страхования ЭЦП
    // 3. Сохранить подписи в file.signature
    // 4. Сохранить документы в insurance_documents
    // 5. Обновить статус insurance_policies -> 'documents_signed'
}
```

#### Шаг 4: Создание договора в страховой
```java
public void createInsuranceContract(Long insurancePolicyId) {
    InsurancePolicy policy = insurancePolicyRepository.findById(insurancePolicyId);
    Transportation transportation = policy.getTransportation();

    // 1. Сформировать XML запрос CreateNewDocument
    CreateDocumentRequest request = buildCreateDocumentRequest(transportation);

    // 2. Вызвать API страховой
    CreateDocumentResponse response = insuranceApiClient.createNewDocument(request);

    // 3. Сохранить номер договора
    policy.setContractNumber(response.getContractNumber());
    policy.setStatus("contract_created");

    // 4. Передать документы методом SavePicture
    uploadInsuranceDocuments(insurancePolicyId);
}

private void uploadInsuranceDocuments(Long insurancePolicyId) {
    List<InsuranceDocument> documents = insuranceDocumentRepository
        .findByInsurancePolicyId(insurancePolicyId);

    for (InsuranceDocument doc : documents) {
        // Конвертировать документ в base64
        byte[] fileData = minioService.downloadFile(doc.getFileId());

        // Вызвать SavePicture для каждого документа
        insuranceApiClient.savePicture(
            buildSavePictureRequest(doc, fileData)
        );

        doc.setUploadStatus("sent");
    }
}
```

#### Шаг 5: Получение подписанного договора
**Асинхронно или по webhook от страховой**:
```java
public void receiveSignedContract(String contractNumber, byte[] signedPdf) {
    // 1. Найти policy по contractNumber
    InsurancePolicy policy = insurancePolicyRepository
        .findByContractNumber(contractNumber);

    // 2. Сохранить PDF в MinIO
    UUID fileId = minioService.uploadFile(signedPdf, "insurance-contracts");

    // 3. Обновить policy
    policy.setSignedContractFileId(fileId);
    policy.setStatus("active");

    // 4. Обновить статус заявки на активный (снять INSURANCE_PENDING)
    Transportation transportation = policy.getTransportation();
    transportation.setStatus("ACTIVE"); // или другой статус

    // 5. Отправить уведомление клиенту
}
```

## Java классы

### InsuranceService.java
```java
@Service
@Transactional
public class InsuranceService {

    @Autowired
    private InsuranceApiClient insuranceApiClient;

    @Autowired
    private InsurancePolicyRepository insurancePolicyRepository;

    @Autowired
    private InsuranceClientCheckRepository clientCheckRepository;

    @Autowired
    private InsuranceDocumentRepository documentRepository;

    @Autowired
    private TransportationRepository transportationRepository;

    @Autowired
    private MinioService minioService;

    @Autowired
    private NotificationService notificationService;

    /**
     * Создать полис страхования для заявки
     */
    public InsurancePolicy createInsurancePolicy(Long transportationId);

    /**
     * Проверить клиента по спискам ПОД/ФТ
     */
    public InsuranceCheckResult checkClientForInsurance(Long insurancePolicyId);

    /**
     * Подписать документы страхования ЭЦП
     */
    public void signInsuranceDocuments(Long insurancePolicyId, SignatureData signatureData);

    /**
     * Создать договор в системе страховой
     */
    public void createInsuranceContract(Long insurancePolicyId);

    /**
     * Загрузить документы в систему страховой
     */
    public void uploadInsuranceDocuments(Long insurancePolicyId);

    /**
     * Получить подписанный договор от страховой
     */
    public void receiveSignedContract(String contractNumber, byte[] signedPdf);

    /**
     * Отменить страхование
     */
    public void cancelInsurance(Long insurancePolicyId, String reason);
}
```

### InsurancePolicyRepository.java
```java
@Repository
public interface InsurancePolicyRepository extends JpaRepository<InsurancePolicy, Long> {
    Optional<InsurancePolicy> findByTransportationId(Long transportationId);
    Optional<InsurancePolicy> findByContractNumber(String contractNumber);
    List<InsurancePolicy> findByStatus(String status);
}
```

## Обработка ошибок

### Сценарии отказа:
1. **Проверка ПОД/ФТ не прошла**:
   - Статус заявки: без страхования
   - Уведомление: "Страхование недоступно. Заявка создана без страхования."

2. **Ошибка API страховой**:
   - Retry 3 раза
   - Если не помогло: отложить на фоновую задачу
   - Статус: `INSURANCE_PENDING`

3. **Пользователь отменил подписание**:
   - Предложить продолжить без страхования
   - Удалить/архивировать insurance_policy

## Уведомления
- После успешного создания договора
- При получении подписанного договора
- При отказе в страховании

## Фоновые задачи
Создать scheduled job для:
- Проверки статусов договоров в страховой
- Повторной отправки документов при ошибках
- Синхронизации данных
