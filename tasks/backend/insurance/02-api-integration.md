# Задача 2: Интеграция с API страховой компании

## Описание
Реализовать REST клиент для взаимодействия с SOAP API страховой компании УСК Евразия.

## Endpoint страховой
```
https://ws.theeurasia.kz/ws/wsNovelty.1cws
```

## Методы для реализации

### 1. CheckClient - Проверка по спискам ПОД/ФТ
**Описание**: Проверка клиента по террористическим и санкционным спискам

**Запрос (SOAP XML)**:
```xml
<CheckClient>
    <IDNumber>123456789012</IDNumber>
    <Name>ТОО "Компания"</Name>
    <LastName>Иванов</LastName>
    <FirstName>Иван</FirstName>
    <MiddleName>Иванович</MiddleName>
</CheckClient>
```

**Ответ**:
- `0` - проверка пройдена (OK)
- `1` - найдено совпадение в списке (ОТКАЗ)

**Кого проверять**:
- Страхователь (владелец заявки/организация)
- Застрахованный (если отличается)
- Выгодоприобретатель (если указан)
- Бенефициарный собственник (из профиля организации)
- Первый руководитель (CEO организации)

### 2. CreateNewDocument - Создание договора страхования
**Описание**: Создание нового документа страхования в системе 1С

**Запрос**: XML структура с данными страхования (см. ТЗ в разделе 5)

**Ответ**:
```json
{
    "status": "ok",
    "contractNumber": "ST-2025-012345"
}
```

**Что передавать**:
- Данные страхователя/застрахованного/выгодоприобретателя
- Условия страхования (сумма, тариф, срок)
- Сведения о грузе (из transportation)
- Маршрут перевозки (из cargo_loading)
- Данные подписанта

### 3. SavePicture - Загрузка документов
**Описание**: Передача подписанных и сопутствующих документов

**Параметры**:
- `ID` (int) - ID документа
- `DestinationID` (string) - код типа документа
- `ClientName` (string) - название клиента
- `ClientID` (string) - ИИН/БИН
- `ObjectName` (string) - имя объекта
- `DocumentXML` (base64Binary) - файл в base64
- `ContractNumber` (string) - номер договора
- `FileName` (string) - имя файла
- `CRC32` (int) - контрольная сумма

**Коды документов для передачи**:
- `00085` - Договор подписанный ЭЦП
- `00086` - Заявление, подписанное ЭЦП
- `00026` - Доверенность
- `00003` - Документ госрегистрации ИП
- `00005` - Документ госрегистрации ЮЛ
- `00061` - Справка о зарегистрированном юридическом лице
- `00010` - Удостоверение личности первого руководителя
- `00001` - Документ, удостоверяющий личность

## Java классы для создания

### InsuranceApiClient.java
```java
@Service
public class InsuranceApiClient {

    @Value("${insurance.api.url}")
    private String apiUrl;

    public CheckClientResponse checkClient(CheckClientRequest request);

    public CreateDocumentResponse createNewDocument(CreateDocumentRequest request);

    public SavePictureResponse savePicture(SavePictureRequest request);
}
```

### DTO классы

```java
// CheckClientRequest.java
public class CheckClientRequest {
    private String idNumber;
    private String name;
    private String lastName;
    private String firstName;
    private String middleName;
}

// CreateDocumentRequest.java
public class CreateDocumentRequest {
    // По структуре из ТЗ раздел 5
}

// SavePictureRequest.java
public class SavePictureRequest {
    private Integer id;
    private String destinationId;
    private String clientName;
    private String clientId;
    private String objectName;
    private byte[] documentXML;
    private String contractNumber;
    private String fileName;
    private Integer crc32;
}
```

## Логирование
Все запросы и ответы логировать в таблицу `insurance_api_logs`.

## Обработка ошибок
- Retry логика для сетевых ошибок (3 попытки)
- Timeout: 30 секунд
- Сохранение ошибок в БД

## Конфигурация
Добавить в `application.yml`:
```yaml
insurance:
  api:
    url: https://ws.theeurasia.kz/ws/wsNovelty.1cws
    timeout: 30000
    retry:
      max-attempts: 3
      backoff: 2000
```
