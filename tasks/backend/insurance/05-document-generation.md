# Задача 5: Генерация документов страхования

## Описание
Реализовать генерацию документов для страхования: заявление-анкета и договор страхования.

## Документы для генерации

### 1. Заявление-анкета
**Формат**: PDF
**Содержание**:
- Данные страхователя
- Данные о грузе
- Условия страхования
- Согласие на обработку персональных данных

### 2. Договор страхования
**Формат**: PDF
**Содержание** (согласно ТЗ раздел 5):
- Страхователь
- Застрахованный
- Выгодоприобретатель
- Срок действия
- Страховая сумма
- Тариф и франшиза
- Программа страхования (секция с рисками)
- Вид груза/его описание
- Маршрут перевозки
- Подписант страхователя

## Данные для заполнения документов

### Источники данных:

#### 1. Страхователь (из `users.organization`)
```java
{
    "organizationName": "ТОО Компания",
    "iinBin": "123456789012",
    "legalAddress": "г. Алматы, ул. Абая 1",
    "actualAddress": "г. Алматы, ул. Абая 1",
    "vat": true
}
```

#### 2. Банковские реквизиты (из `users.bank_requisite`)
```java
{
    "accountNumber": "KZ123456789012345678",
    "bank": "Kaspi Bank",
    "bic": "CASPKZKA"
}
```

#### 3. Руководитель организации (из `users.employee` с ролью CEO)
```java
{
    "firstName": "Иван",
    "lastName": "Иванов",
    "middleName": "Иванович",
    "iin": "890123456789",
    "phone": "+77001234567",
    "email": "ivan@company.kz"
}
```

#### 4. Груз (из `applications.transportation`)
```java
{
    "cargoName": "Мебель",
    "cargoTypeName": "Бытовая техника",
    "cargoPrice": 500000,
    "cargoPriceCurrency": "KZT",
    "cargoWeight": 5000,
    "cargoWeightUnit": "kg",
    "cargoVolume": 25,
    "tareType": "Контейнер"
}
```

#### 5. Маршрут (из `applications.cargo_loading`)
```java
{
    "loadingPoints": [
        {
            "orderNum": 1,
            "loadingType": "loading",
            "address": "г. Алматы, ул. Промышленная 10",
            "loadingDatetime": "2025-10-15T08:00:00",
            "shipperBin": "111222333444",
            "contactPerson": "Петров Петр",
            "contactNumber": "+77002345678"
        },
        {
            "orderNum": 2,
            "loadingType": "unloading",
            "address": "г. Астана, ул. Кабанбай батыра 20",
            "loadingDatetime": "2025-10-18T14:00:00",
            "contactPerson": "Сидоров Сидор",
            "contactNumber": "+77003456789"
        }
    ]
}
```

#### 6. Условия страхования (расчетные)
```java
{
    "insuranceSum": 500000, // = cargoPrice
    "insurancePremium": 25000, // рассчитывается по тарифу (5%)
    "tariffRate": 5.0,
    "franchiseAmount": 5000, // 1% от страховой суммы
    "contractStartDate": "2025-10-15T00:00:00",
    "contractEndDate": "2025-10-18T23:59:59",
    "programType": "standard" // стандартная программа
}
```

## Расчет страховой премии

### Формула
```java
insurancePremium = insuranceSum * (tariffRate / 100)
franchiseAmount = insuranceSum * 0.01
```

### Тарифы (из справочника)
- Стандартная программа: 5%
- Расширенная программа: 7%

**ВАЖНО**: Тариф зависит от типа груза и маршрута. Нужен справочник тарифов.

## Генератор документов

### InsuranceDocumentGenerator.java
```java
@Service
public class InsuranceDocumentGenerator {

    @Autowired
    private TemplateEngine templateEngine;

    @Autowired
    private PdfGenerator pdfGenerator;

    /**
     * Генерация заявления-анкеты
     */
    public byte[] generateApplicationForm(InsuranceDocumentData data) {
        // 1. Подготовить данные для шаблона
        Context context = prepareApplicationFormContext(data);

        // 2. Сгенерировать HTML из шаблона
        String html = templateEngine.process("insurance/application-form", context);

        // 3. Конвертировать HTML в PDF
        return pdfGenerator.generatePdf(html);
    }

    /**
     * Генерация договора страхования
     */
    public byte[] generateContract(InsuranceDocumentData data) {
        // 1. Подготовить данные для шаблона
        Context context = prepareContractContext(data);

        // 2. Сгенерировать HTML из шаблона
        String html = templateEngine.process("insurance/contract", context);

        // 3. Конвертировать HTML в PDF
        return pdfGenerator.generatePdf(html);
    }

    /**
     * Генерация документа "Исключенные территории"
     */
    public byte[] generateExcludedTerritories() {
        // Статичный документ, можно взять из resources
        return loadStaticPdf("insurance/excluded-territories.pdf");
    }

    private Context prepareApplicationFormContext(InsuranceDocumentData data) {
        Context context = new Context();
        context.setVariable("organization", data.getOrganization());
        context.setVariable("director", data.getDirector());
        context.setVariable("cargo", data.getCargo());
        context.setVariable("route", data.getRoute());
        context.setVariable("insurance", data.getInsuranceTerms());
        context.setVariable("generatedDate", LocalDateTime.now());
        return context;
    }

    private Context prepareContractContext(InsuranceDocumentData data) {
        Context context = new Context();
        context.setVariable("contractNumber", data.getContractNumber());
        context.setVariable("insurer", data.getOrganization());
        context.setVariable("insured", data.getOrganization()); // может отличаться
        context.setVariable("beneficiary", data.getBeneficiary());
        context.setVariable("cargo", data.getCargo());
        context.setVariable("route", data.getRoute());
        context.setVariable("insurance", data.getInsuranceTerms());
        context.setVariable("signatory", data.getSignatory());
        context.setVariable("generatedDate", LocalDateTime.now());
        return context;
    }
}
```

### InsuranceDocumentData.java
```java
@Data
@Builder
public class InsuranceDocumentData {
    private String contractNumber;
    private OrganizationData organization;
    private DirectorData director;
    private CargoData cargo;
    private RouteData route;
    private InsuranceTerms insuranceTerms;
    private SignatoryData signatory;
    private BeneficiaryData beneficiary;
}
```

## Шаблоны документов

### Создать Thymeleaf шаблоны

#### application-form.html
```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<head>
    <meta charset="UTF-8"/>
    <title>Заявление-анкета на страхование груза</title>
    <style>
        body { font-family: 'Times New Roman', serif; font-size: 12pt; }
        .header { text-align: center; font-weight: bold; }
        .section { margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; }
        td { padding: 5px; border: 1px solid #000; }
    </style>
</head>
<body>
    <div class="header">
        <h2>ЗАЯВЛЕНИЕ-АНКЕТА</h2>
        <p>на страхование груза</p>
    </div>

    <div class="section">
        <h3>1. СТРАХОВАТЕЛЬ</h3>
        <table>
            <tr>
                <td>Наименование:</td>
                <td th:text="${organization.name}"></td>
            </tr>
            <tr>
                <td>ИИН/БИН:</td>
                <td th:text="${organization.iinBin}"></td>
            </tr>
            <tr>
                <td>Юридический адрес:</td>
                <td th:text="${organization.legalAddress}"></td>
            </tr>
            <!-- ... остальные поля -->
        </table>
    </div>

    <div class="section">
        <h3>2. ОБЪЕКТ СТРАХОВАНИЯ</h3>
        <table>
            <tr>
                <td>Наименование груза:</td>
                <td th:text="${cargo.cargoName}"></td>
            </tr>
            <tr>
                <td>Стоимость груза:</td>
                <td th:text="${cargo.cargoPrice + ' ' + cargo.currency}"></td>
            </tr>
            <!-- ... -->
        </table>
    </div>

    <!-- ... остальные секции -->
</body>
</html>
```

#### contract.html
```html
<!DOCTYPE html>
<html xmlns:th="http://www.thymeleaf.org">
<head>
    <meta charset="UTF-8"/>
    <title>Договор страхования груза</title>
    <style>
        /* стили аналогично application-form.html */
    </style>
</head>
<body>
    <div class="header">
        <h2>ДОГОВОР СТРАХОВАНИЯ ГРУЗА</h2>
        <p>№ <span th:text="${contractNumber}"></span></p>
    </div>

    <!-- Содержание договора -->
</body>
</html>
```

## PDF генератор

### Использовать библиотеку Flying Saucer (iText)

#### pom.xml
```xml
<dependency>
    <groupId>org.xhtmlrenderer</groupId>
    <artifactId>flying-saucer-pdf</artifactId>
    <version>9.1.22</version>
</dependency>
```

#### PdfGenerator.java
```java
@Service
public class PdfGenerator {

    public byte[] generatePdf(String html) throws IOException {
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {
            ITextRenderer renderer = new ITextRenderer();
            renderer.setDocumentFromString(html);
            renderer.layout();
            renderer.createPDF(outputStream);
            return outputStream.toByteArray();
        }
    }
}
```

## Интеграция в InsuranceService

```java
@Service
public class InsuranceService {

    @Autowired
    private InsuranceDocumentGenerator documentGenerator;

    @Autowired
    private MinioService minioService;

    public void generateInsuranceDocuments(Long insurancePolicyId) {
        InsurancePolicy policy = insurancePolicyRepository.findById(insurancePolicyId);
        Transportation transportation = policy.getTransportation();

        // 1. Собрать данные
        InsuranceDocumentData data = buildDocumentData(transportation);

        // 2. Сгенерировать заявление-анкету
        byte[] applicationForm = documentGenerator.generateApplicationForm(data);
        UUID applicationFormFileId = minioService.uploadFile(
            applicationForm,
            "insurance/application-forms",
            "application-form-" + policy.getId() + ".pdf"
        );

        // 3. Сгенерировать договор
        byte[] contract = documentGenerator.generateContract(data);
        UUID contractFileId = minioService.uploadFile(
            contract,
            "insurance/contracts",
            "contract-" + policy.getId() + ".pdf"
        );

        // 4. Сохранить в БД
        policy.setApplicationFormFileId(applicationFormFileId);
        insurancePolicyRepository.save(policy);
    }
}
```

## Тестирование
- Unit тесты для генератора
- Проверка корректности данных в PDF
- Валидация PDF формата
