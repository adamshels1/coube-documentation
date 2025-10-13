# Задача 6: Тестирование и интеграция

## Описание
Написать тесты и подготовить систему к production.

## Unit тесты

### InsuranceServiceTest.java
```java
@SpringBootTest
@Transactional
class InsuranceServiceTest {

    @Autowired
    private InsuranceService insuranceService;

    @MockBean
    private InsuranceApiClient insuranceApiClient;

    @Test
    void testCreateInsurancePolicy_Success() {
        // Given
        Long transportationId = 1L;

        // When
        InsurancePolicy policy = insuranceService.createInsurancePolicy(transportationId);

        // Then
        assertNotNull(policy);
        assertEquals("pending", policy.getStatus());
        assertEquals(transportationId, policy.getTransportationId());
    }

    @Test
    void testCheckClient_AllPassed() {
        // Given
        Long policyId = 1L;
        when(insuranceApiClient.checkClient(any()))
            .thenReturn(new CheckClientResponse(0)); // 0 = OK

        // When
        InsuranceCheckResult result = insuranceService.checkClientForInsurance(policyId);

        // Then
        assertEquals(InsuranceCheckResult.PASSED, result);
    }

    @Test
    void testCheckClient_OneFailed() {
        // Given
        Long policyId = 1L;
        when(insuranceApiClient.checkClient(any()))
            .thenReturn(new CheckClientResponse(1)); // 1 = в черном списке

        // When
        InsuranceCheckResult result = insuranceService.checkClientForInsurance(policyId);

        // Then
        assertEquals(InsuranceCheckResult.FAILED, result);

        InsurancePolicy policy = insurancePolicyRepository.findById(policyId).get();
        assertEquals("client_check_failed", policy.getStatus());
    }

    @Test
    void testSignDocuments_Success() {
        // Given
        Long policyId = 1L;
        SignatureData signatureData = new SignatureData(...);

        // When
        insuranceService.signInsuranceDocuments(policyId, signatureData);

        // Then
        InsurancePolicy policy = insurancePolicyRepository.findById(policyId).get();
        assertEquals("documents_signed", policy.getStatus());

        List<InsuranceDocument> docs = insuranceDocumentRepository
            .findByInsurancePolicyId(policyId);
        assertTrue(docs.size() > 0);
    }

    @Test
    void testCreateContract_Success() {
        // Given
        Long policyId = 1L;
        when(insuranceApiClient.createNewDocument(any()))
            .thenReturn(new CreateDocumentResponse("ST-2025-012345"));

        // When
        insuranceService.createInsuranceContract(policyId);

        // Then
        InsurancePolicy policy = insurancePolicyRepository.findById(policyId).get();
        assertEquals("contract_created", policy.getStatus());
        assertEquals("ST-2025-012345", policy.getContractNumber());
    }
}
```

### InsuranceApiClientTest.java
```java
@SpringBootTest
class InsuranceApiClientTest {

    @Autowired
    private InsuranceApiClient insuranceApiClient;

    @Test
    void testCheckClient_RealApi() {
        // Тест с реальным API (использовать test environment страховой)
        CheckClientRequest request = CheckClientRequest.builder()
            .idNumber("123456789012")
            .name("ТОО Компания")
            .build();

        CheckClientResponse response = insuranceApiClient.checkClient(request);

        assertNotNull(response);
        assertTrue(response.getResult() == 0 || response.getResult() == 1);
    }

    @Test
    void testCreateNewDocument_MockApi() {
        // Тест с mock API
        // ...
    }
}
```

### InsuranceDocumentGeneratorTest.java
```java
@SpringBootTest
class InsuranceDocumentGeneratorTest {

    @Autowired
    private InsuranceDocumentGenerator documentGenerator;

    @Test
    void testGenerateApplicationForm_Success() throws IOException {
        // Given
        InsuranceDocumentData data = InsuranceDocumentData.builder()
            .organization(createTestOrganization())
            .cargo(createTestCargo())
            .route(createTestRoute())
            .insuranceTerms(createTestInsuranceTerms())
            .build();

        // When
        byte[] pdf = documentGenerator.generateApplicationForm(data);

        // Then
        assertNotNull(pdf);
        assertTrue(pdf.length > 0);

        // Сохранить для визуальной проверки
        Files.write(Paths.get("/tmp/application-form-test.pdf"), pdf);
    }

    @Test
    void testGenerateContract_Success() throws IOException {
        // Аналогично application form
    }
}
```

## Integration тесты

### InsuranceFlowIntegrationTest.java
```java
@SpringBootTest
@Transactional
@AutoConfigureMockMvc
class InsuranceFlowIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void testFullInsuranceFlow_Success() throws Exception {
        // 1. Создать заявку со страхованием
        CreateTransportationRequest request = new CreateTransportationRequest();
        request.setWithInsurance(true);
        // ... заполнить остальные поля

        MvcResult createResult = mockMvc.perform(post("/api/transportations")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request)))
            .andExpect(status().isOk())
            .andReturn();

        TransportationResponse transportation = objectMapper.readValue(
            createResult.getResponse().getContentAsString(),
            TransportationResponse.class
        );

        Long transportationId = transportation.getId();
        Long insurancePolicyId = transportation.getInsurancePolicy().getId();

        // 2. Проверить клиента
        mockMvc.perform(post("/api/insurance/check-client/" + transportationId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.result").value("passed"));

        // 3. Получить документы для ознакомления
        mockMvc.perform(get("/api/insurance/documents/preview/" + insurancePolicyId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.applicationForm").exists())
            .andExpect(jsonPath("$.contract").exists());

        // 4. Подписать документы
        SignDocumentsRequest signRequest = new SignDocumentsRequest();
        // ... заполнить данные подписи

        mockMvc.perform(post("/api/insurance/sign/" + insurancePolicyId)
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(signRequest)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("documents_signed"));

        // 5. Создать договор в страховой
        mockMvc.perform(post("/api/insurance/create-contract/" + insurancePolicyId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.contractNumber").exists());

        // 6. Проверить финальный статус
        mockMvc.perform(get("/api/insurance/status/" + insurancePolicyId))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("contract_created"));
    }

    @Test
    void testInsuranceFlow_CheckClientFailed() throws Exception {
        // Тест сценария с отказом в проверке клиента
        // ...
    }
}
```

## Нагрузочное тестирование

### Gatling сценарий
```scala
class InsuranceLoadTest extends Simulation {

  val httpProtocol = http
    .baseUrl("https://api.coube.kz")
    .acceptHeader("application/json")

  val scn = scenario("Insurance Flow")
    .exec(
      http("Create Transportation with Insurance")
        .post("/api/transportations")
        .body(StringBody("""{"withInsurance": true, ...}"""))
        .check(status.is(200))
        .check(jsonPath("$.insurancePolicy.id").saveAs("policyId"))
    )
    .pause(1)
    .exec(
      http("Check Client")
        .post("/api/insurance/check-client/${transportationId}")
        .check(status.is(200))
    )
    .pause(2)
    .exec(
      http("Sign Documents")
        .post("/api/insurance/sign/${policyId}")
        .body(StringBody("""{"signatureData": "..."}"""))
        .check(status.is(200))
    )

  setUp(
    scn.inject(
      rampUsers(100) during (60 seconds)
    ).protocols(httpProtocol)
  )
}
```

## Мониторинг и логирование

### Добавить метрики
```java
@Service
public class InsuranceService {

    @Autowired
    private MeterRegistry meterRegistry;

    public InsurancePolicy createInsurancePolicy(Long transportationId) {
        meterRegistry.counter("insurance.policy.created").increment();

        // ...
    }

    public InsuranceCheckResult checkClientForInsurance(Long policyId) {
        Timer.Sample sample = Timer.start(meterRegistry);

        try {
            // проверка клиента
            InsuranceCheckResult result = ...;

            sample.stop(meterRegistry.timer("insurance.check.duration",
                "result", result.toString()));

            meterRegistry.counter("insurance.check.total",
                "result", result.toString()).increment();

            return result;
        } catch (Exception e) {
            meterRegistry.counter("insurance.check.errors").increment();
            throw e;
        }
    }
}
```

### Добавить структурированное логирование
```java
@Service
@Slf4j
public class InsuranceService {

    public void createInsuranceContract(Long insurancePolicyId) {
        InsurancePolicy policy = insurancePolicyRepository.findById(insurancePolicyId);

        log.info("Creating insurance contract",
            StructuredArguments.keyValue("insurancePolicyId", insurancePolicyId),
            StructuredArguments.keyValue("transportationId", policy.getTransportationId())
        );

        try {
            CreateDocumentResponse response = insuranceApiClient.createNewDocument(request);

            log.info("Insurance contract created successfully",
                StructuredArguments.keyValue("insurancePolicyId", insurancePolicyId),
                StructuredArguments.keyValue("contractNumber", response.getContractNumber())
            );
        } catch (Exception e) {
            log.error("Failed to create insurance contract",
                StructuredArguments.keyValue("insurancePolicyId", insurancePolicyId),
                StructuredArguments.keyValue("error", e.getMessage())
            );
            throw e;
        }
    }
}
```

## Production Checklist

### Перед запуском в production:

1. **API ключи и credentials**:
   - [ ] Получить production credentials от страховой компании
   - [ ] Настроить переменные окружения

2. **Тестирование**:
   - [ ] Пройти все unit тесты
   - [ ] Пройти integration тесты
   - [ ] Провести нагрузочное тестирование
   - [ ] Тестирование с реальным API страховой (test environment)

3. **Безопасность**:
   - [ ] Проверка SSL сертификатов
   - [ ] Валидация ЭЦП
   - [ ] Rate limiting
   - [ ] CSRF защита

4. **Мониторинг**:
   - [ ] Настроить алерты в Grafana
   - [ ] Настроить логирование в ELK/Loki
   - [ ] Добавить health checks

5. **Документация**:
   - [ ] API документация (Swagger)
   - [ ] Runbook для операторов
   - [ ] Инструкция по troubleshooting

6. **Резервное копирование**:
   - [ ] Backup стратегия для БД
   - [ ] Backup файлов в MinIO

7. **Rollback план**:
   - [ ] Feature toggle для отключения страхования
   - [ ] План отката миграций БД
