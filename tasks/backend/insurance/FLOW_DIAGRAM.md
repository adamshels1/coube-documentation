# Диаграммы процесса страхования

## 1. Общий флоу процесса

```mermaid
sequenceDiagram
    participant Client as Клиент
    participant Frontend as Frontend
    participant Backend as Backend API
    participant InsuranceAPI as API Страховой
    participant DB as База данных

    Client->>Frontend: Создать заявку + свич "Со страхованием"
    Frontend->>Backend: POST /api/transportations {withInsurance: true}
    Backend->>DB: Создать Transportation
    Backend->>DB: Создать InsurancePolicy (status: pending)
    Backend-->>Frontend: 200 OK {insurancePolicy: {id, status}}

    Backend->>InsuranceAPI: CheckClient (страхователь)
    InsuranceAPI-->>Backend: Result: 0 (OK)
    Backend->>InsuranceAPI: CheckClient (руководитель)
    InsuranceAPI-->>Backend: Result: 0 (OK)
    Backend->>DB: Сохранить результаты проверок

    alt Проверка пройдена (Result = 0)
        Backend-->>Frontend: Notification: "Проверка пройдена"
    else Проверка не пройдена (Result ≠ 0)
        Backend->>DB: Статус: client_check_failed
        Backend-->>Frontend: Показать модалку с причиной отказа
        Frontend->>Client: Предложить продолжить БЕЗ страхования
        Client->>Frontend: Продолжить без страхования
        Frontend->>Backend: PUT /api/insurance/decline/{policyId}
        Backend->>DB: Статус: insurance_declined
    end

    Frontend->>Backend: GET /api/insurance/documents/preview/{policyId}
    Backend->>Backend: Получить данные документов из API для preview
    Backend-->>Frontend: {applicationForm, contract, excludedTerritories}

    Frontend->>Client: Показать документы для ознакомления
    Client->>Frontend: Согласен с условиями + подпись ЭЦП (на фронте)
    Note over Client,Frontend: Клиент подписывает документы своей ЭЦП<br/>Фронт конвертирует подписанные документы в base64
    Frontend->>Backend: POST /api/insurance/sign/{policyId} + signed docs (base64)
    Backend->>DB: Сохранить подпись + документы
    Backend->>DB: Обновить статус -> "documents_signed"

    Frontend->>Backend: POST /api/insurance/create-contract/{policyId}
    Note over Backend: Получить данные из БД:<br/>- Transportation (груз, маршрут)<br/>- CargoLoading (размеры, форма, кузов)<br/>- Справочники (типы груза)
    Backend->>InsuranceAPI: CreateNewDocument (XML с данными груза и страхования)
    InsuranceAPI-->>Backend: {contractNumber: "ST-2025-012345"}
    Backend->>DB: Обновить contractNumber + статус

    Note over Backend: Взять подписанные клиентом документы<br/>из предыдущего шага (base64)
    Backend->>InsuranceAPI: SavePicture (документ 1 - base64)
    InsuranceAPI-->>Backend: OK
    Backend->>InsuranceAPI: SavePicture (документ 2 - base64)
    InsuranceAPI-->>Backend: OK
    Backend->>InsuranceAPI: SavePicture (документ N - base64)
    InsuranceAPI-->>Backend: OK

    Note over InsuranceAPI: Страховая подписывает договор

    InsuranceAPI->>Backend: Webhook: Договор подписан
    Backend->>DB: Сохранить подписанный PDF
    Backend->>DB: Обновить статус -> "active"
    Backend->>Frontend: Notification: "Договор готов"

    Client->>Frontend: Просмотр договора
    Frontend->>Backend: GET /api/insurance/status/{policyId}
    Backend-->>Frontend: {signedContractUrl, status: "active"}
```

## 2. Проверка клиента (CheckClient)

```mermaid
flowchart TD
    Start([Начало: создана InsurancePolicy]) --> GetData[Получить данные организации]
    GetData --> CheckInsurer[Проверить страхователя]
    CheckInsurer --> InsOk{Result = 0?}

    InsOk -->|Нет| FailInsurer[Сохранить: check_result = failed]
    FailInsurer --> Reject[Статус policy: client_check_failed]
    Reject --> NotifyFail[Уведомить клиента об отказе]
    NotifyFail --> AllowWithout[Предложить продолжить БЕЗ страхования]
    AllowWithout --> End([Конец])

    InsOk -->|Да| SaveInsurer[Сохранить: check_result = passed]
    SaveInsurer --> CheckDirector[Проверить руководителя]
    CheckDirector --> DirOk{Result = 0?}

    DirOk -->|Нет| FailDirector[check_result = failed]
    FailDirector --> Reject

    DirOk -->|Да| SaveDirector[check_result = passed]
    SaveDirector --> CheckBeneficial[Проверить бенефициара если есть]
    CheckBeneficial --> BenOk{Result = 0?}

    BenOk -->|Нет| FailBen[check_result = failed]
    FailBen --> Reject

    BenOk -->|Да| AllPassed[Все проверки пройдены]
    AllPassed --> UpdateStatus[Статус policy: client_check_passed]
    UpdateStatus --> NotifySuccess[Уведомить: можно продолжать]
    NotifySuccess --> End
```

## 3. Генерация и подписание документов

```mermaid
flowchart LR
    Start([Клиент прошел проверку]) --> Collect[Собрать данные из БД]
    Collect --> GenApp[Сгенерировать заявление-анкету PDF]
    GenApp --> GenContract[Сгенерировать договор PDF]
    GenContract --> GenExcluded[Приложение исключенные территории]

    GenExcluded --> Preview[Показать Preview клиенту]
    Preview --> Agree{Клиент согласен?}

    Agree -->|Нет| Cancel[Отменить страхование]
    Cancel --> End([Конец])

    Agree -->|Да| SignApp[Подписать заявление ЭЦП]
    SignApp --> SignContract[Подписать договор ЭЦП]
    SignContract --> Validate[Валидировать подписи]
    Validate --> Valid{Подписи валидны?}

    Valid -->|Нет| Error[Ошибка: неверная ЭЦП]
    Error --> Preview

    Valid -->|Да| SaveDocs[Сохранить документы в БД]
    SaveDocs --> UpdateSigned[Статус: documents_signed]
    UpdateSigned --> Next([Следующий шаг: создание договора])
```

## 4. Создание договора в страховой

```mermaid
flowchart TD
    Start([Документы подписаны]) --> BuildXML[Сформировать XML запрос]
    BuildXML --> CallAPI[CreateNewDocument API]
    CallAPI --> APISuccess{API Success?}

    APISuccess -->|Нет| LogError[Логировать ошибку]
    LogError --> Retry{Попытка < 3?}
    Retry -->|Да| Wait[Ждать 2 сек]
    Wait --> CallAPI
    Retry -->|Нет| MarkFailed[Статус: contract_creation_failed]
    MarkFailed --> NotifyError[Уведомить об ошибке]
    NotifyError --> End([Конец])

    APISuccess -->|Да| SaveContract[Сохранить contractNumber]
    SaveContract --> UpdateStatus[Статус: contract_created]
    UpdateStatus --> UploadDocs[Загрузить документы SavePicture]

    UploadDocs --> ForEachDoc{Для каждого документа}
    ForEachDoc --> ConvertBase64[Конвертировать в base64]
    ConvertBase64 --> CallSave[SavePicture API]
    CallSave --> SaveSuccess{Success?}

    SaveSuccess -->|Нет| LogUploadError[Логировать ошибку загрузки]
    LogUploadError --> ForEachDoc

    SaveSuccess -->|Да| MarkUploaded[upload_status: sent]
    MarkUploaded --> MoreDocs{Еще документы?}
    MoreDocs -->|Да| ForEachDoc
    MoreDocs -->|Нет| AllUploaded[Все документы загружены]
    AllUploaded --> WaitSign[Ждать подписания страховой]
    WaitSign --> End
```

## 5. Статусы InsurancePolicy

```mermaid
stateDiagram-v2
    [*] --> pending: Создание заявки

    pending --> client_check_in_progress: Начало проверки
    client_check_in_progress --> client_check_failed: Проверка не пройдена
    client_check_in_progress --> client_check_passed: Проверка пройдена

    client_check_failed --> cancelled: Отказ от страхования
    client_check_passed --> documents_preview: Показ документов

    documents_preview --> documents_signing: Клиент подписывает
    documents_signing --> documents_signed: Подписи сохранены

    documents_signed --> contract_creating: Создание в 1С
    contract_creating --> contract_creation_failed: Ошибка API
    contract_creation_failed --> contract_creating: Retry
    contract_creating --> contract_created: Договор создан

    contract_created --> documents_uploading: Загрузка документов
    documents_uploading --> documents_uploaded: Все загружены

    documents_uploaded --> waiting_signature: Ждем подпись страховой
    waiting_signature --> active: Договор подписан

    active --> completed: Перевозка завершена
    active --> claimed: Страховой случай

    claimed --> [*]
    completed --> [*]
    cancelled --> [*]
```

## 6. Архитектура компонентов

```mermaid
graph TB
    subgraph "Frontend Layer"
        UI[Vue.js UI]
    end

    subgraph "Backend Layer"
        Controller[InsuranceController]
        Service[InsuranceService]
        ApiClient[InsuranceApiClient]
        DocGen[InsuranceDocumentGenerator]
        Notif[NotificationService]
    end

    subgraph "Data Layer"
        PolicyRepo[InsurancePolicyRepository]
        CheckRepo[InsuranceClientCheckRepository]
        DocRepo[InsuranceDocumentRepository]
        LogRepo[InsuranceApiLogRepository]
    end

    subgraph "Storage"
        DB[(PostgreSQL)]
        MinIO[(MinIO/S3)]
    end

    subgraph "External APIs"
        EurasiaAPI[УСК Евразия API]
        KalkanAPI[Kalkan ЭЦП]
    end

    UI --> Controller
    Controller --> Service
    Service --> ApiClient
    Service --> DocGen
    Service --> Notif
    Service --> PolicyRepo
    Service --> CheckRepo
    Service --> DocRepo
    Service --> LogRepo

    PolicyRepo --> DB
    CheckRepo --> DB
    DocRepo --> DB
    LogRepo --> DB

    DocGen --> MinIO
    Service --> MinIO

    ApiClient --> EurasiaAPI
    Service --> KalkanAPI
```

## 7. ER-диаграмма таблиц

```mermaid
erDiagram
    TRANSPORTATION ||--o| INSURANCE_POLICIES : has
    INSURANCE_POLICIES ||--o{ INSURANCE_CLIENT_CHECKS : has
    INSURANCE_POLICIES ||--o{ INSURANCE_DOCUMENTS : has
    INSURANCE_POLICIES ||--o{ INSURANCE_API_LOGS : has
    INSURANCE_DOCUMENTS }o--|| FILE_META_INFO : references
    INSURANCE_DOCUMENTS }o--o| SIGNATURE : references

    TRANSPORTATION {
        bigint id PK
        boolean with_insurance
        text status
    }

    INSURANCE_POLICIES {
        bigint id PK
        bigint transportation_id FK
        text contract_number
        text status
        numeric insurance_premium
        uuid signed_contract_file_id
        timestamp contract_start_date
        timestamp contract_end_date
    }

    INSURANCE_CLIENT_CHECKS {
        bigint id PK
        bigint insurance_policy_id FK
        text client_type
        text id_number
        text check_result
        integer api_response
        timestamp checked_at
    }

    INSURANCE_DOCUMENTS {
        bigint id PK
        bigint insurance_policy_id FK
        text document_type_code
        uuid file_id FK
        text file_name
        bigint signature_id FK
        text upload_status
    }

    INSURANCE_API_LOGS {
        bigint id PK
        bigint insurance_policy_id FK
        text api_method
        jsonb request_payload
        jsonb response_payload
        text status
    }
```

## 8. Обработка ошибок

```mermaid
flowchart TD
    Operation[Операция] --> Try{Try}
    Try -->|Success| Log[Логировать успех]
    Log --> Return[Return result]

    Try -->|Exception| Catch[Catch exception]
    Catch --> CheckRetryable{Retryable?}

    CheckRetryable -->|Да| CheckAttempts{Попытки < max?}
    CheckAttempts -->|Да| Backoff[Exponential backoff]
    Backoff --> Try

    CheckAttempts -->|Нет| LogFinalError[Логировать финальную ошибку]
    LogFinalError --> UpdateStatus[Обновить статус: failed]
    UpdateStatus --> NotifyUser[Уведомить пользователя]
    NotifyUser --> ThrowError[Throw exception]

    CheckRetryable -->|Нет| LogImmediateError[Логировать ошибку]
    LogImmediateError --> UpdateStatus
```
