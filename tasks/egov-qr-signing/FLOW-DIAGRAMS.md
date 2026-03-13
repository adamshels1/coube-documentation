# Диаграммы Flow для eGov QR Подписания

## 1. Web Flow (QR Код Подписание)

```mermaid
sequenceDiagram
    participant User as Пользователь
    participant Browser as Веб Браузер
    participant Frontend as Frontend (Vue.js)
    participant Backend as Backend API
    participant DB as База Данных
    participant EgovApp as eGov Mobile App
    participant EgovAPI as eGov Mobile API

    User->>Browser: Открывает документ
    Browser->>Frontend: Показать документ
    User->>Frontend: Нажимает "Подписать"
    Frontend->>Frontend: Показать модалку выбора метода
    User->>Frontend: Выбирает "Через QR код"

    Frontend->>Backend: POST /egov-sign/init<br/>{documentId, documentType}
    Backend->>DB: Создать сессию (PENDING)
    Backend->>Backend: Генерировать JWT токен
    Backend->>Backend: Создать API #1 URL
    Backend->>Backend: Генерировать QR код<br/>mobileSign:{API_URL}
    Backend-->>Frontend: {sessionId, qrCode, expiresAt}

    Frontend->>Frontend: Показать QR модалку с кодом
    Frontend->>Frontend: Запустить polling (каждые 3 сек)

    User->>EgovApp: Сканирует QR код в eGov Mobile
    EgovApp->>Backend: GET /egov-document/api1<br/>?sessionId=XXX
    Backend->>DB: Найти сессию
    Backend-->>EgovApp: JSON с метаданными<br/>{orgInfo, documentUri, authToken}

    EgovApp->>Backend: GET /egov-document/document<br/>Header: Authorization: Token {authToken}
    Backend->>DB: Проверить authToken
    Backend->>Backend: Получить документ (PDF)
    Backend-->>EgovApp: Base64 документ

    EgovApp->>EgovApp: Показать документ пользователю
    User->>EgovApp: Подписывает с помощью ЭЦП
    EgovApp->>EgovApp: Создать CMS подпись

    EgovApp->>Backend: PUT /egov-document/document<br/>Header: Authorization: Token {authToken}<br/>Body: {cms}
    Backend->>Backend: Проверить CMS подпись
    Backend->>DB: Обновить статус сессии → SIGNED
    Backend->>DB: Сохранить подписанный документ
    Backend-->>EgovApp: 200 OK

    EgovApp->>User: Показать успех

    Note over Frontend,Backend: Polling продолжается
    Frontend->>Backend: GET /egov-sign/session/{id}/status
    Backend->>DB: Проверить статус
    Backend-->>Frontend: {status: "SIGNED"}

    Frontend->>Frontend: Остановить polling
    Frontend->>Frontend: Показать "Успешно подписано"
    Frontend->>User: Автозакрыть модалку<br/>Обновить UI
```

## 2. Mobile Flow (Cross Подписание)

```mermaid
sequenceDiagram
    participant User as Пользователь
    participant CoubeApp as Coube Mobile App
    participant Backend as Backend API
    participant DB as База Данных
    participant EgovApp as eGov Mobile App

    User->>CoubeApp: Открывает документ
    CoubeApp->>CoubeApp: Показать SigningOrderDetailsScreen
    User->>CoubeApp: Нажимает "Подписать договор"

    CoubeApp->>Backend: POST /egov-sign/init<br/>{documentId, documentType}
    Backend->>DB: Создать сессию (PENDING)
    Backend->>Backend: Генерировать JWT токен
    Backend->>Backend: Создать API #1 URL
    Backend->>Backend: Создать QR код<br/>mobileSign:{API_URL}
    Backend-->>CoubeApp: {sessionId, qrCode, expiresAt}

    CoubeApp->>CoubeApp: Извлечь API URL из qrCode
    CoubeApp->>CoubeApp: URL encode API URL
    CoubeApp->>CoubeApp: Создать Dynamic Link:<br/>Android: mgovsign.page.link/?link={url}&apn=...<br/>iOS: mgovsign.page.link/?link={url}&isi=...&ibi=...

    CoubeApp->>EgovApp: Открыть Dynamic Link<br/>(Linking.openURL)

    Note over CoubeApp: Coube App уходит в фон
    Note over EgovApp: eGov Mobile открывается

    EgovApp->>Backend: GET /egov-document/api1?sessionId=XXX
    Backend->>DB: Найти сессию
    Backend-->>EgovApp: Метаданные + authToken

    EgovApp->>Backend: GET /egov-document/document<br/>Authorization: Token {authToken}
    Backend-->>EgovApp: Base64 документ

    EgovApp->>User: Показать документ
    User->>EgovApp: Подписывает документ
    EgovApp->>EgovApp: Создать CMS подпись

    EgovApp->>Backend: PUT /egov-document/document<br/>Body: {cms}
    Backend->>Backend: Проверить подпись
    Backend->>DB: Статус → SIGNED
    Backend-->>EgovApp: 200 OK

    EgovApp->>CoubeApp: Deep Link: coube://sign-callback<br/>?sessionId={id}&status=success

    Note over CoubeApp: Coube App возвращается на передний план

    CoubeApp->>CoubeApp: Открыть SignCallbackScreen
    CoubeApp->>Backend: GET /egov-sign/session/{id}
    Backend->>DB: Получить полную информацию
    Backend-->>CoubeApp: {status: "SIGNED", documentId, ...}

    CoubeApp->>CoubeApp: Navigate to SigningSuccessScreen
    CoubeApp->>User: Показать "Документ успешно подписан"
```

## 3. Детальный Flow компонентов (Web)

```mermaid
graph TD
    A[Пользователь открывает<br/>ContractResponsesItem] --> B[Нажимает 'Подписать контракт']
    B --> C[Открывается<br/>SelectSignMethodBody]

    C --> D{Выбор метода}
    D -->|NCLayer| E[Существующий flow<br/>через файл ключа]
    D -->|QR код| F[sendContractViaQR]

    F --> G[API: POST /egov-sign/init]
    G --> H[Backend создает сессию]
    H --> I[Backend генерирует<br/>QR код + JWT токен]
    I --> J[Возврат sessionId,<br/>qrCode, expiresAt]

    J --> K[Показать QRSignModal]
    K --> L[Отобразить QR код]
    K --> M[Запустить polling<br/>каждые 3 секунды]
    K --> N[Показать countdown<br/>30 минут]

    M --> O[GET /session/status]
    O --> P{Статус?}

    P -->|PENDING| M
    P -->|SIGNED| Q[Остановить polling]
    P -->|ERROR| R[Показать ошибку]
    P -->|EXPIRED| S[Показать 'Время истекло']

    Q --> T[Показать 'Успешно подписано']
    T --> U[Автозакрыть через 2 сек]
    U --> V[emit 'success']
    V --> W[Обновить UI контракта]

    R --> X[Кнопка 'Попробовать снова']
    S --> X
    X --> F

    style A fill:#e1f5ff
    style K fill:#fff4e1
    style Q fill:#e8f5e9
    style R fill:#ffebee
```

## 4. Детальный Flow компонентов (Mobile)

```mermaid
graph TD
    A[Пользователь открывает<br/>SigningOrderDetailsScreen] --> B[Нажимает 'Подписать договор']

    B --> C[handleSignContract]
    C --> D[Статус: creating_session]
    D --> E[egovSignService.signWithEgovMobile]

    E --> F[API: POST /egov-sign/init]
    F --> G[Backend создает сессию]
    G --> H[Возврат sessionId, qrCode]

    H --> I[Извлечь API URL из qrCode]
    I --> J[Создать Dynamic Link<br/>для Android или iOS]
    J --> K{eGov Mobile<br/>установлен?}

    K -->|Нет| L[Показать диалог установки]
    L --> M[Открыть App Store/Play Store]

    K -->|Да| N[Статус: opening_egov]
    N --> O[Linking.openURL<br/>с Dynamic Link]

    O --> P[eGov Mobile открывается]
    P --> Q[Coube App в фоне]
    Q --> R[Статус: waiting_signature]
    R --> S[Запустить polling]

    S --> T[GET /session/status<br/>каждые 3 сек]
    T --> U{Статус?}

    U -->|PENDING| T
    U -->|SIGNED| V[Остановить polling]
    U -->|ERROR| W[Показать ошибку]
    U -->|EXPIRED| X[Показать 'Время истекло']

    P --> Y[Пользователь подписывает<br/>в eGov Mobile]
    Y --> Z[eGov отправляет CMS<br/>на backend]
    Z --> AA[Backend обновляет статус]

    AA --> AB[eGov Mobile делает<br/>redirect на coube://]
    AB --> AC[Coube App возвращается<br/>на передний план]

    AC --> AD[SignCallbackScreen]
    AD --> AE[GET /session/{id}]
    AE --> AF{Статус?}

    AF -->|SIGNED| AG[Navigate to<br/>SigningSuccessScreen]
    AF -->|ERROR| AH[Navigate to<br/>SigningErrorScreen]
    AF -->|PENDING| AI[Показать 'Не завершено'<br/>Предложить вернуться]

    AG --> AJ[Показать успех ✅]
    AJ --> AK[Обновить данные заказа]
    AK --> AL[Кнопка 'Вернуться на главную']

    style A fill:#e1f5ff
    style P fill:#fff4e1
    style AG fill:#e8f5e9
    style AH fill:#ffebee
```

## 5. Backend API Flow

```mermaid
graph LR
    A[Frontend/Mobile] --> B[POST /egov-sign/init]
    B --> C[EgovSignController.initSession]
    C --> D[EgovSignSessionService.createSession]
    D --> E[Создать UUID sessionId]
    E --> F[Генерировать JWT authToken]
    F --> G[Создать API #1 URL]
    G --> H[Генерировать QR код]
    H --> I[Сохранить в DB<br/>статус: PENDING]
    I --> J[Вернуть response]

    K[eGov Mobile] --> L[GET /egov-document/api1]
    L --> M[EgovDocumentController.getApi1]
    M --> N[Найти сессию в DB]
    N --> O[Собрать метаданные:<br/>org info, document URI]
    O --> P[Вернуть JSON]

    K --> Q[GET /egov-document/document]
    Q --> R[Проверить authToken<br/>из Header]
    R --> S[Найти сессию]
    S --> T[Получить документ]
    T --> U[Конвертировать в Base64]
    U --> V[Вернуть в eGov формате]

    K --> W[PUT /egov-document/document]
    W --> X[Проверить authToken]
    X --> Y[Получить CMS из body]
    Y --> Z[SignVerifyService.verify]
    Z --> AA{CMS валидна?}
    AA -->|Да| AB[Обновить сессию<br/>статус: SIGNED]
    AA -->|Нет| AC[Вернуть 400<br/>Invalid signature]
    AB --> AD[Сохранить подписанный<br/>документ]
    AD --> AE[Вернуть 200 OK]

    AF[Frontend/Mobile] --> AG[GET /egov-sign/session/{id}/status]
    AG --> AH[Вернуть {status}]

    style B fill:#e3f2fd
    style L fill:#fff3e0
    style Q fill:#fff3e0
    style W fill:#e8f5e9
    style AG fill:#f3e5f5
```

## 6. Состояния сессии

```mermaid
stateDiagram-v2
    [*] --> PENDING: Сессия создана

    PENDING --> SIGNED: Документ подписан<br/>и CMS проверен
    PENDING --> ERROR: Ошибка при подписании
    PENDING --> EXPIRED: Истекло 30 минут

    SIGNED --> [*]: Успешное завершение
    ERROR --> [*]: Завершение с ошибкой
    EXPIRED --> [*]: Сессия истекла

    note right of PENDING
        - Ожидает подписания
        - Polling активен
        - TTL: 30 минут
    end note

    note right of SIGNED
        - Документ подписан
        - CMS сохранена
        - signedAt установлен
    end note

    note right of ERROR
        - Ошибка подписания
        - errorMessage сохранен
    end note

    note right of EXPIRED
        - Время истекло
        - Нужна новая сессия
    end note
```

## 7. Компоненты системы

```mermaid
graph TB
    subgraph "Frontend (Vue.js)"
        A[SelectSignMethodBody]
        B[QRSignModal]
        C[ContractResponsesItem]
    end

    subgraph "Mobile (React Native)"
        D[SigningOrderDetailsScreen]
        E[egovSignService]
        F[SignCallbackScreen]
        G[SigningSuccessScreen]
        H[SigningErrorScreen]
    end

    subgraph "Backend (Spring Boot)"
        I[EgovSignController]
        J[EgovDocumentController]
        K[EgovSignSessionService]
        L[SignVerifyService]
    end

    subgraph "Database"
        M[(egov_sign_sessions)]
    end

    subgraph "External"
        N[eGov Mobile App]
    end

    C --> A
    A --> B
    B --> I

    D --> E
    E --> I
    E --> F
    F --> G
    F --> H

    I --> K
    J --> K
    K --> M
    J --> L

    N --> J
    N --> F

    style A fill:#bbdefb
    style B fill:#bbdefb
    style C fill:#bbdefb
    style D fill:#c8e6c9
    style E fill:#c8e6c9
    style F fill:#c8e6c9
    style G fill:#c8e6c9
    style H fill:#c8e6c9
    style I fill:#ffccbc
    style J fill:#ffccbc
    style K fill:#ffccbc
    style M fill:#f0f0f0
    style N fill:#fff9c4
```

## 8. Timing Diagram (30-минутная сессия)

```mermaid
gantt
    title Timeline сессии подписания
    dateFormat mm:ss
    axisFormat %M:%S

    section Создание сессии
    POST /egov-sign/init           :00:00, 1s
    Генерация QR кода              :00:01, 1s
    Показ QR модалки               :00:02, 2s

    section Сканирование
    Пользователь сканирует QR      :00:10, 10s
    GET /api1 (метаданные)         :00:20, 2s
    GET /document                  :00:22, 3s

    section Подписание
    Пользователь просматривает     :00:25, 30s
    Пользователь подписывает       :00:55, 20s

    section Отправка
    PUT /document (CMS)            :01:15, 3s
    Проверка подписи               :01:18, 2s
    Обновление статуса SIGNED      :01:20, 1s

    section Polling
    Polling status (каждые 3 сек)  :00:04, 01:20
    Получен статус SIGNED          :01:21, 1s

    section Завершение
    Показ успеха                   :01:22, 2s
    Автозакрытие модалки           :01:24, 1s

    section TTL
    Время жизни сессии             :00:00, 30:00
    Автоматическая очистка         :30:00, 1s
```

## 9. Error Handling Flow

```mermaid
graph TD
    A[Процесс подписания] --> B{Возможные ошибки}

    B --> C[Network Error]
    B --> D[Session Not Found]
    B --> E[Session Expired]
    B --> F[Invalid CMS]
    B --> G[eGov Mobile не установлен]
    B --> H[Backend Error 500]

    C --> I[Показать 'Нет соединения']
    I --> J[Retry через 5 сек]

    D --> K[Показать 'Сессия не найдена']
    K --> L[Создать новую сессию]

    E --> M[Показать 'Время истекло']
    M --> L

    F --> N[Показать 'Неверная подпись']
    N --> O[Попробовать снова]

    G --> P[Диалог установки]
    P --> Q[Открыть App Store/Play Store]

    H --> R[Показать 'Ошибка сервера']
    R --> J

    J --> S{Успех?}
    S -->|Да| T[Продолжить]
    S -->|Нет| U[Показать persistent error]

    style C fill:#ffcdd2
    style D fill:#ffcdd2
    style E fill:#ffcdd2
    style F fill:#ffcdd2
    style G fill:#ffcdd2
    style H fill:#ffcdd2
    style T fill:#c8e6c9
```

## Легенда

- **Frontend (Web)** - Vue.js компоненты (голубой)
- **Mobile** - React Native компоненты (зеленый)
- **Backend** - Spring Boot API (оранжевый)
- **Database** - PostgreSQL (серый)
- **External** - eGov Mobile App (желтый)

## Ключевые моменты

1. **QR код содержит**: `mobileSign:{API_1_URL}`
2. **JWT токен** используется для авторизации запросов от eGov Mobile
3. **Polling интервал**: 3 секунды
4. **TTL сессии**: 30 минут
5. **Deep link схема**: `coube://sign-callback?sessionId={id}&status={status}`
6. **Dynamic Link** отличается для Android и iOS
