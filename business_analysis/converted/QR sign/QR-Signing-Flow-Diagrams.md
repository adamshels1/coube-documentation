# Flow диаграммы QR подписания eGov Mobile

## Содержание

1. [QR подписание через сканирование QR-кода](#1-qr-подписание-через-сканирование-qr-кода)
2. [Кросс подписание через динамическую ссылку](#2-кросс-подписание-через-динамическую-ссылку)
3. [Процесс получения документов (API №2)](#3-процесс-получения-документов-api-2)
4. [Процесс подписания документов](#4-процесс-подписания-документов)
5. [Процесс отправки подписанных документов](#5-процесс-отправки-подписанных-документов)
6. [Аутентификация по типам](#6-аутентификация-по-типам)

---

## 1. QR подписание через сканирование QR-кода

### 1.1 Общий поток QR подписания

```mermaid
sequenceDiagram
    participant User as Пользователь
    participant Web as Веб-приложение<br/>(coube-frontend)
    participant Backend as Бэкенд<br/>(coube-backend)
    participant eGov as eGov Mobile<br/>Приложение
    participant API1 as API №1<br/>(Инфо о подписании)
    participant API2 as API №2<br/>(Документы)
    participant НУЦ as НУЦ РК<br/>(Валидация ЭЦП)

    User->>Web: 1. Открыть документ для подписания
    Web->>Backend: 2. Запрос генерации QR-кода

    Note over Backend: Генерация API №1 URL<br/>для документа

    Backend->>Backend: 3. Создать URL API №1<br/>с параметрами документа
    Backend->>Web: 4. Вернуть QR-код данные

    Note over Web: Формирование QR-кода<br/>с префиксом префиксом mobileSign

    Web->>Web: 5. Сгенерировать QR-код<br/>mobileSign:https://backend.coube.kz/api/sign/ID
    Web->>User: 6. Отобразить QR-код на экране

    User->>eGov: 7. Открыть eGov Mobile<br/>и сканировать QR-код
    eGov->>eGov: 8. Распознать префикс префиксом mobileSign
    eGov->>API1: 9. GET запрос на API №1<br/>(из QR-кода)

    API1->>Backend: 10. Получить метаданные документа
    Backend->>API1: 11. Вернуть данные документа

    API1->>eGov: 12. Ответ с метаданными:<br/>- description<br/>- expiry_date<br/>- organisation<br/>- document.uri (API №2)<br/>- document.auth_type<br/>- document.auth_token

    Note over eGov: Отображение информации<br/>о подписании пользователю

    eGov->>User: 13. Показать инфо об организации,<br/>описание документа
    User->>eGov: 14. Подтвердить продолжение

    Note over eGov,API2: Переход к получению<br/>документов для подписания

    rect rgb(220, 240, 255)
        Note over eGov,API2: Блок получения документов (см. диаграмму 3)
        eGov->>API2: 15. Запрос документов<br/>(метод зависит от auth_type)
        API2->>eGov: 16. Возврат документов для подписания
    end

    rect rgb(255, 240, 220)
        Note over User,eGov: Блок подписания (см. диаграмму 4)
        eGov->>User: 17. Показать документы
        User->>eGov: 18. Выбрать ЭЦП ключ
        User->>eGov: 19. Ввести пароль ключа
        eGov->>eGov: 20. Подписать документы<br/>(согласно signMethod)
        eGov->>НУЦ: 21. Добавить timestamp НУЦ РК
    end

    rect rgb(240, 255, 240)
        Note over eGov,API2: Блок отправки подписанных документов
        eGov->>API2: 22. PUT запрос с подписанными<br/>документами
        API2->>Backend: 23. Валидация подписи
        Backend->>НУЦ: 24. Проверка ЭЦП через OCSP
        НУЦ->>Backend: 25. Результат валидации
        Backend->>API2: 26. Результат сохранения
        API2->>eGov: 27. Статус 200 success<br/>или 403 (ошибка валидации)
    end

    eGov->>User: 28. Уведомление об успехе/<br/>ошибке подписания

    alt Успешное подписание
        Backend->>Web: 29. WebSocket/Polling:<br/>Документ подписан
        Web->>User: 30. Обновить статус документа
    else Ошибка подписания
        eGov->>User: 31. Показать сообщение об ошибке
    end
```

### 1.2 Детализация генерации QR-кода

```mermaid
flowchart TD
    Start([Начало: Пользователь<br/>открывает документ]) --> CheckDoc{Документ требует<br/>ЭЦП подписания?}

    CheckDoc -->|Нет| EndNoSign([Документ не требует подписи])
    CheckDoc -->|Да| GenerateAPI1[Сгенерировать URL API №1]

    GenerateAPI1 --> BuildURL[Построить URL API endpoint]

    BuildURL --> AddPrefix[Добавить префикс mobileSign]

    AddPrefix --> FormatQR[Форматировать строку для QR-кода]

    FormatQR --> RemoveSpaces[Удалить все пробелы из строки]

    RemoveSpaces --> GenerateQR[Сгенерировать QR-код изображение]

    GenerateQR --> DisplayQR[Отобразить QR-код на веб-странице]

    DisplayQR --> WaitScan[Ожидать сканирования пользователем]

    WaitScan --> CheckExpiry{Проверить expiry_date<br/>не истек?}

    CheckExpiry -->|Истек| ShowExpired[Показать сообщение:<br/>Срок действия истек]
    ShowExpired --> End([Конец])

    CheckExpiry -->|Активен| WaitResult[Ожидать результата подписания]

    WaitResult --> CheckResult{Результат подписания}

    CheckResult -->|Успех| UpdateStatus[Обновить статус документа:<br/>Подписан]
    CheckResult -->|Ошибка| ShowError[Показать ошибку подписания]
    CheckResult -->|Таймаут| ShowTimeout[Показать таймаут]

    UpdateStatus --> End
    ShowError --> End
    ShowTimeout --> End
```

---

## 2. Кросс подписание через динамическую ссылку

### 2.1 Общий поток кросс подписания

```mermaid
sequenceDiagram
    participant User as Пользователь
    participant Mobile as Мобильное приложение<br/>(coube-mobile)
    participant Backend as Бэкенд<br/>(coube-backend)
    participant DeepLink as Dynamic Link Handler<br/>(mgovsign.page.link)
    participant eGov as eGov Mobile<br/>Приложение
    participant API1 as API №1
    participant API2 as API №2

    User->>Mobile: 1. Открыть документ для подписания
    Mobile->>Backend: 2. Запрос подписания через eGov

    Note over Backend: Генерация API №1 URL

    Backend->>Backend: 3. Создать URL API №1:<br/>https://backend.coube.kz/api/egov-sign/info/ID?token=xxx

    Backend->>Backend: 4. URL-кодировать параметры:<br/>? → %3F<br/>= → %3D<br/>& → %26

    Note over Backend: Формирование динамической ссылки<br/>для iOS/Android

    alt iOS устройство
        Backend->>Backend: 5a. Построить iOS deep link:<br/>https://mgovsign.page.link/?link=закодированный API1<br/>&isi=1476128386<br/>&ibi=kz.egov.mobile
        Backend->>Mobile: 6a. Вернуть iOS deep link
    else Android устройство
        Backend->>Backend: 5b. Построить Android deep link:<br/>https://mgovsign.page.link/?link=закодированный API1<br/>&apn=kz.mobile.mgov
        Backend->>Mobile: 6b. Вернуть Android deep link
    end

    Mobile->>User: 7. Показать кнопку<br/>Подписать через eGov Mobile

    User->>Mobile: 8. Нажать кнопку подписания

    Mobile->>DeepLink: 9. Открыть dynamic link

    DeepLink->>DeepLink: 10. Определить платформу и наличие приложения

    alt eGov Mobile установлен
        DeepLink->>eGov: 11a. Открыть eGov Mobile<br/>с параметром link
        eGov->>eGov: 12a. Декодировать URL из параметра link
    else eGov Mobile не установлен (iOS)
        DeepLink->>User: 11b. Перенаправить в App Store<br/>(isi=1476128386)
    else eGov Mobile не установлен (Android)
        DeepLink->>User: 11c. Перенаправить в Google Play<br/>(apn=kz.mobile.mgov)
    end

    eGov->>API1: 13. GET запрос на декодированный API №1

    API1->>Backend: 14. Получить метаданные документа
    Backend->>API1: 15. Вернуть данные

    API1->>eGov: 16. Ответ с метаданными:<br/>- description<br/>- expiry_date<br/>- organisation<br/>- document (uri, auth_type, auth_token)

    rect rgb(220, 240, 255)
        Note over eGov,API2: Блок получения документов
        eGov->>API2: 17. Запрос документов
        API2->>eGov: 18. Документы для подписания
    end

    rect rgb(255, 240, 220)
        Note over User,eGov: Блок подписания
        eGov->>User: 19. Показать документы
        User->>eGov: 20. Подтвердить и подписать
        eGov->>eGov: 21. Выполнить подписание
    end

    rect rgb(240, 255, 240)
        Note over eGov,Backend: Блок отправки результата
        eGov->>API2: 22. PUT подписанные документы
        API2->>Backend: 23. Сохранить и валидировать
        Backend->>API2: 24. Результат
        API2->>eGov: 25. Статус 200/403
    end

    eGov->>User: 26. Показать результат

    Note over Mobile: Приложение coube-mobile должно<br/>отслеживать результат через polling/webhook

    Backend->>Mobile: 27. Callback/Webhook:<br/>Документ подписан
    Mobile->>User: 28. Обновить UI:<br/>Документ подписан успешно
```

### 2.2 Построение динамической ссылки

```mermaid
flowchart TD
    Start([Начало: Запрос подписания<br/>из мобильного приложения]) --> DetectOS{Определить ОС<br/>пользователя}

    DetectOS -->|iOS| BuildiOS[Начать построение iOS ссылки]
    DetectOS -->|Android| BuildAndroid[Начать построение Android ссылки]

    BuildiOS --> CreateAPI1_iOS[1. Создать API №1 URL<br/>с параметрами документа]
    BuildAndroid --> CreateAPI1_Android[1. Создать API №1 URL<br/>с параметрами документа]

    CreateAPI1_iOS --> EncodeURL_iOS[2. URL-кодировать параметры<br/>? → %3F, = → %3D, & → %26]
    CreateAPI1_Android --> EncodeURL_Android[2. URL-кодировать параметры<br/>? → %3F, = → %3D, & → %26]

    EncodeURL_iOS --> BuildDeepLink_iOS[3. Построить iOS deep link<br/>mgovsign.page.link с параметрами<br/>isi и ibi]
    EncodeURL_Android --> BuildDeepLink_Android[3. Построить Android deep link<br/>mgovsign.page.link с параметром apn]

    BuildDeepLink_iOS --> FinalURL_iOS[Финальный iOS URL готов]
    BuildDeepLink_Android --> FinalURL_Android[Финальный Android URL готов]

    FinalURL_iOS --> ReturnToApp[Вернуть URL в приложение]
    FinalURL_Android --> ReturnToApp

    ReturnToApp --> DisplayButton[Отобразить кнопку:<br/>Подписать через eGov Mobile]

    DisplayButton --> UserClick{Пользователь<br/>нажал кнопку?}

    UserClick -->|Нет| Wait[Ожидание действия пользователя]
    Wait --> UserClick

    UserClick -->|Да| OpenDeepLink[Открыть deep link в браузере]

    OpenDeepLink --> DeepLinkHandler{mgovsign.page.link<br/>обработчик}

    DeepLinkHandler -->|eGov установлен| LaunchEgov[Запустить eGov Mobile<br/>с параметром link]
    DeepLinkHandler -->|eGov не установлен iOS| RedirectAppStore[Перенаправить в App Store]
    DeepLinkHandler -->|eGov не установлен Android| RedirectGooglePlay[Перенаправить в Google Play]

    LaunchEgov --> End([eGov Mobile открыт<br/>и начинает процесс подписания])
    RedirectAppStore --> End
    RedirectGooglePlay --> End
```

---

## 3. Процесс получения документов (API №2)

### 3.1 Получение документов в зависимости от типа аутентификации

```mermaid
flowchart TD
    Start([eGov Mobile получил<br/>метаданные из API №1]) --> ParseAuth{Определить<br/>auth_type}

    ParseAuth -->|None| GetNone[Метод: GET<br/>Без аутентификации]
    ParseAuth -->|Token| GetToken[Метод: GET<br/>С Bearer Token]
    ParseAuth -->|Eds| PostEds[Метод: POST<br/>С подписанным XML]

    GetNone --> BuildRequest_None[Построить GET запрос:<br/>URL: document.uri из API №1<br/>Headers: Accept-Language: ru/kk/en]

    GetToken --> ExtractToken[Извлечь auth_token из API №1]
    ExtractToken --> BuildRequest_Token[Построить GET запрос:<br/>URL: document.uri<br/>Headers:<br/>- Authorization: Bearer токен<br/>- Accept-Language: ru/kk/en]

    PostEds --> GenerateXML[Сгенерировать XML для подписания<br/>с URL и timestamp]
    GenerateXML --> SignXML[Подписать XML с помощью<br/>AUTH_*.p12 ключа пользователя]
    SignXML --> BuildRequest_Eds[Построить POST запрос:<br/>URL: document.uri<br/>Headers: <br/>- Content-Type: application/json<br/>- Accept-Language: ru/kk/en<br/>Body: с подписанным XML]

    BuildRequest_None --> SendRequest[Отправить запрос на API №2]
    BuildRequest_Token --> SendRequest
    BuildRequest_Eds --> SendRequest

    SendRequest --> CheckResponse{Проверить<br/>HTTP статус}

    CheckResponse -->|200 OK| ParseJSON[Распарсить JSON ответ]
    CheckResponse -->|4xx/5xx| ShowError[Показать ошибку пользователю:<br/>с сообщением об ошибке]

    ShowError --> End([Конец: Ошибка получения документов])

    ParseJSON --> ValidateJSON{Валидация<br/>структуры JSON}

    ValidateJSON -->|Невалидный| ShowError
    ValidateJSON -->|Валидный| ExtractFields[Извлечь поля:<br/>- signMethod<br/>- version<br/>- documentsToSign массив]

    ExtractFields --> CheckMethod{Проверить<br/>signMethod}

    CheckMethod -->|XML| ProcessXML[Обработать XML документы]
    CheckMethod -->|CMS_WITH_DATA| ProcessCMS_Data[Обработать CMS с данными]
    CheckMethod -->|CMS_SIGN_ONLY| ProcessCMS_Sign[Обработать CMS только подпись]
    CheckMethod -->|SIGN_BYTES_ARRAY| ProcessBytes[Обработать массив байтов]
    CheckMethod -->|MIX_SIGN| ProcessMix[Обработать смешанное подписание]

    ProcessXML --> LoopDocs_XML[Для каждого документа:<br/>- Извлечь documentXml<br/>- Отобразить XML пользователю]
    ProcessCMS_Data --> LoopDocs_CMS_Data[Для каждого документа:<br/>- Декодировать document.file.data из base64<br/>- Отобразить по MIME типу]
    ProcessCMS_Sign --> LoopDocs_CMS_Sign[Для каждого документа:<br/>- Декодировать document.file.data из base64<br/>- Отобразить по MIME типу]
    ProcessBytes --> LoopDocs_Bytes[Для каждого документа:<br/>- Декодировать document.file.data<br/>- Отобразить по MIME типу:<br/>  text/plain, application/pdf, application/xml]
    ProcessMix --> LoopDocs_Mix[Для каждого документа:<br/>- Проверить индивидуальный signMethod<br/>- Обработать согласно методу]

    LoopDocs_XML --> DisplayDocs[Отобразить документы пользователю:<br/>- nameRu/nameKz/nameEn<br/>- meta данные<br/>- Содержимое документа]
    LoopDocs_CMS_Data --> DisplayDocs
    LoopDocs_CMS_Sign --> DisplayDocs
    LoopDocs_Bytes --> DisplayDocs
    LoopDocs_Mix --> DisplayDocs

    DisplayDocs --> End_Success([Конец: Документы готовы<br/>к подписанию])
```

### 3.2 Обработка MIME типов при отображении

```mermaid
flowchart TD
    Start([Документ получен из API №2]) --> ExtractMime[Извлечь document.file.mime]

    ExtractMime --> DecodeBas64[Декодировать document.file.data<br/>из base64]

    DecodeBas64 --> CheckMime{Определить<br/>MIME тип}

    CheckMime -->|text/plain| DisplayText[Отобразить текст в UI:<br/>- Показать в текстовом поле<br/>- Разрешить прокрутку]

    CheckMime -->|application/pdf| DisplayPDF[Отобразить PDF:<br/>- Использовать PDF viewer<br/>- Показать кнопки:<br/>  * Скачать<br/>  * Поделиться]

    CheckMime -->|application/xml| DisplayXML[Отобразить XML:<br/>- Форматированный вывод<br/>- Подсветка синтаксиса<br/>ТОЛЬКО для SIGN_BYTES_ARRAY]

    CheckMime -->|Другой MIME| NoDisplay[НЕ отображать содержимое:<br/>- Показать иконку типа файла<br/>- Показать имя документа<br/>- Показать размер]

    DisplayText --> ShowMeta[Показать метаданные:<br/>- nameRu/nameKz/nameEn<br/>- meta массив массив]
    DisplayPDF --> ShowMeta
    DisplayXML --> ShowMeta
    NoDisplay --> ShowMeta

    ShowMeta --> End([Документ отображен<br/>и готов к подписанию])
```

---

## 4. Процесс подписания документов

### 4.1 Общий процесс подписания

```mermaid
flowchart TD
    Start([Пользователь просмотрел<br/>документы и готов подписать]) --> SelectKey[Пользователь выбирает<br/>ЭЦП ключ для подписания]

    SelectKey --> EnterPassword[Пользователь вводит<br/>пароль ключа]

    EnterPassword --> ValidatePassword{Проверка<br/>пароля ключа}

    ValidatePassword -->|Неверный| ShowPassError[Показать ошибку:<br/>Неверный пароль]
    ShowPassError --> EnterPassword

    ValidatePassword -->|Верный| LoadCert[Загрузить сертификат<br/>из ключа *.p12]

    LoadCert --> CheckCertValid{Проверить<br/>сертификат}

    CheckCertValid -->|Срок истек| ShowCertError[Показать ошибку:<br/>Срок действия сертификата истек]
    ShowCertError --> End([Конец: Подписание невозможно])

    CheckCertValid -->|Отозван| ShowRevokeError[Показать ошибку:<br/>Сертификат отозван]
    ShowRevokeError --> End

    CheckCertValid -->|Валидный| CheckSignMethod{Определить<br/>signMethod}

    CheckSignMethod -->|XML| SignXML[Подписание XML]
    CheckSignMethod -->|CMS_WITH_DATA| SignCMS_Data[Подписание CMS с данными]
    CheckSignMethod -->|CMS_SIGN_ONLY| SignCMS_Only[Подписание CMS только подпись]
    CheckSignMethod -->|SIGN_BYTES_ARRAY| SignBytes[Подписание массива байтов]
    CheckSignMethod -->|MIX_SIGN| SignMix[Смешанное подписание]

    SignXML --> ProcessXML_Sign[Для каждого документа:<br/>1. Получить documentXml<br/>2. Подписать по стандарту XML dsig<br/>3. Добавить timestamp НУЦ РК<br/>4. Заменить documentXml подписанным]

    SignCMS_Data --> ProcessCMS_Data_Sign[Для каждого документа:<br/>1. Декодировать document.file.data из base64<br/>2. Создать CMS структуру с данными<br/>3. Добавить timestamp НУЦ РК<br/>4. Кодировать в base64<br/>5. Заменить document.file.data]

    SignCMS_Only --> ProcessCMS_Only_Sign[Для каждого документа:<br/>1. Создать хэш документа<br/>2. Подписать только хэш в CMS<br/>3. Добавить timestamp НУЦ РК<br/>4. Кодировать в base64<br/>5. Заменить document.file.data]

    SignBytes --> ProcessBytes_Sign[Для каждого документа:<br/>1. Преобразовать данные в байты<br/>2. Подписать байты<br/>3. Получить signature и certificate<br/>4. Сформировать JSON строку<br/>5. Заменить document.file.data]

    SignMix --> ProcessMix_Sign[Для каждого документа:<br/>1. Определить индивидуальный signMethod<br/>2. Применить соответствующий метод<br/>3. Обработать как XML/CMS/Bytes]

    ProcessXML_Sign --> AddTimestamp[Для всех методов:<br/>Добавить timestamp НУЦ РК<br/>в подпись]
    ProcessCMS_Data_Sign --> AddTimestamp
    ProcessCMS_Only_Sign --> AddTimestamp
    ProcessBytes_Sign --> AddTimestamp
    ProcessMix_Sign --> AddTimestamp

    AddTimestamp --> GetTimestamp[Запрос timestamp к НУЦ РК]

    GetTimestamp --> CheckTimestamp{НУЦ РК<br/>ответил?}

    CheckTimestamp -->|Нет| ShowTimestampError[Показать ошибку:<br/>Не удалось получить timestamp]
    ShowTimestampError --> End

    CheckTimestamp -->|Да| EmbedTimestamp[Встроить timestamp в подпись]

    EmbedTimestamp --> BuildSignedJSON[Построить подписанный JSON:<br/>- Сохранить оригинальную структуру<br/>- Заменить documentXml или data<br/>  подписанными значениями<br/>- Оставить остальные поля без изменений]

    BuildSignedJSON --> ValidateSignedJSON{Валидация<br/>подписанного JSON}

    ValidateSignedJSON -->|Ошибка| ShowValidationError[Показать ошибку валидации]
    ShowValidationError --> End

    ValidateSignedJSON -->|Успех| ShowSuccess[Показать пользователю:<br/>Документы подписаны успешно]

    ShowSuccess --> PrepareUpload[Подготовить к отправке на API №2]

    PrepareUpload --> End_Success([Готово к отправке на сервер])
```

### 4.2 Детализация SIGN_BYTES_ARRAY

```mermaid
flowchart TD
    Start([Метод: SIGN_BYTES_ARRAY]) --> LoopDocs[Для каждого документа<br/>в documentsToSign]

    LoopDocs --> GetData[Получить document.file.data<br/>и document.file.mime]

    GetData --> ConvertBytes[Преобразовать data в массив байтов]

    ConvertBytes --> SignBytes[Подписать массив байтов<br/>используя ЭЦП ключ]

    SignBytes --> GetSignature[Получить:<br/>- signature <br/>- certificate ]

    GetSignature --> EncodeBase64[Кодировать в base64:<br/>- signature_base64<br/>- certificate_base64]

    EncodeBase64 --> BuildJSON[Построить JSON строку<br/>с signature и certificate]

    BuildJSON --> ReplaceData[Заменить document.file.data<br/>на JSON строку]

    ReplaceData --> CheckMime{Проверить<br/>MIME тип}

    CheckMime -->|text/plain| NextDoc[Следующий документ]
    CheckMime -->|application/pdf| NextDoc
    CheckMime -->|application/xml| NextDoc
    CheckMime -->|Другой| NextDoc

    NextDoc --> MoreDocs{Есть еще<br/>документы?}

    MoreDocs -->|Да| LoopDocs
    MoreDocs -->|Нет| Complete[Все документы подписаны]

    Complete --> ExampleOutput[Результат: JSON с signature и certificate]

    ExampleOutput --> End([Готово к отправке])
```

---

## 5. Процесс отправки подписанных документов

### 5.1 Отправка и валидация подписанных документов

```mermaid
sequenceDiagram
    participant eGov as eGov Mobile
    participant API2 as API №2
    participant Backend as Backend<br/>(coube-backend)
    participant НУЦ as НУЦ РК<br/>(OCSP сервис)
    participant DB as База данных

    Note over eGov: Документы подписаны<br/>локально

    eGov->>eGov: 1. Подготовить JSON с подписанными<br/>документами (замененные поля)

    eGov->>API2: 2. PUT запрос<br/>URL: document.uri (из API №1)<br/>Headers:<br/>- Content-Type: application/json<br/>- Authorization: Bearer токен (если auth_type=Token)<br/>- Accept-Language: ru/kk/en<br/>Body: подписанный JSON

    API2->>Backend: 3. Получить подписанные документы

    Backend->>Backend: 4. Проверить структуру JSON

    alt Структура невалидна
        Backend->>API2: 5a. Ошибка 400 Bad Request
        API2->>eGov: 6a. с сообщением об ошибке
        eGov->>eGov: 7a. Показать ошибку пользователю
    else Структура валидна
        Backend->>Backend: 5b. Извлечь подписи из документов

        loop Для каждого подписанного документа
            Backend->>Backend: 6b. Извлечь ЭЦП из documentXml или data

            Note over Backend: Валидация ЭЦП согласно<br/>Правилам НУЦ РК

            Backend->>Backend: 7. Проверить структуру ЭЦП<br/>(XML dsig / CMS format)

            Backend->>Backend: 8. Извлечь сертификат из подписи

            Backend->>Backend: 9. Проверить регистрационное<br/>свидетельство :<br/>- Выдано НУЦ РК<br/>- ИИН/БИН соответствует отправителю

            Backend->>Backend: 10. Проверить срок действия:<br/>- NotBefore <= текущее время<br/>- NotAfter >= текущее время<br/>(время Астаны)

            Backend->>Backend: 11. Проверить цепочку сертификатов<br/>до корневого НУЦ РК

            Backend->>НУЦ: 12. OCSP запрос для проверки<br/>статуса сертификата

            alt OCSP сервис доступен
                НУЦ->>Backend: 13a. OCSP квитанция:<br/>- good (не отозван)<br/>- revoked (отозван)<br/>- unknown

                alt Сертификат отозван
                    Backend->>Backend: 14a. Пометить документ<br/>как невалидный
                else Сертификат валидный (good)
                    Backend->>Backend: 14b. Продолжить валидацию
                end

            else OCSP недоступен
                НУЦ->>Backend: 13b. Timeout / Error
                Backend->>Backend: 14c. Проверить по CRL списку:<br/>- Base CRL<br/>- Delta CRL

                Backend->>Backend: 15. Проверить наличие серийного<br/>номера в CRL
            end

            Backend->>Backend: 16. Проверить KeyUsage:<br/>- Цифровая подпись<br/>- Неотрекаемость

            Backend->>Backend: 17. Проверить алгоритм:<br/>ГОСТ 34.311-95 <br/>ГОСТ 34.310-2004 

            Backend->>Backend: 18. Проверить timestamp НУЦ РК<br/>в подписи

            Backend->>Backend: 19. Вычислить хэш документа<br/>и сравнить с подписью

            alt Подпись невалидна
                Backend->>Backend: 20a. Зафиксировать ошибку валидации
            else Подпись валидна
                Backend->>Backend: 20b. Пометить документ<br/>как успешно подписанный
            end
        end

        Backend->>Backend: 21. Собрать результаты валидации<br/>всех документов

        alt Все подписи валидны
            Backend->>DB: 22a. Сохранить подписанные документы
            Backend->>DB: 23a. Обновить статус документа:<br/>status = "SIGNED"
            Backend->>Backend: 24a. Журналировать событие:<br/>- Дата/время<br/>- Пользователь (ИИН/БИН)<br/>- Документ<br/>- Статус: SUCCESS

            Backend->>API2: 25a. Ответ: 200 OK<br/>сообщение success
            API2->>eGov: 26a. Статус 200
            eGov->>eGov: 27a. Показать пользователю:<br/>Документы успешно подписаны

        else Хотя бы одна подпись невалидна
            Backend->>Backend: 22b. Журналировать ошибку:<br/>- Дата/время<br/>- Пользователь<br/>- Документ<br/>- Причина ошибки<br/>- Статус: FAILED

            Backend->>API2: 23b. Ответ: 403 Forbidden<br/>с сообщением об ошибке валидации
            API2->>eGov: 24b. Статус 403
            eGov->>eGov: 25b. Показать пользователю:<br/>Ошибка валидации подписи
        end
    end

    Note over Backend,DB: Все события журналируются<br/>в SIEM систему (syslog RFC 5424)
```

### 5.2 Процесс валидации ЭЦП (детализация)

```mermaid
flowchart TD
    Start([Получен подписанный документ]) --> ExtractSign[Извлечь ЭЦП из документа]

    ExtractSign --> CheckFormat{Проверить<br/>формат подписи}

    CheckFormat -->|XML| ValidateXMLFormat[Проверить соответствие<br/>XML dsig W3C спецификации]
    CheckFormat -->|CMS| ValidateCMSFormat[Проверить CMS структуру<br/>CAdES/XAdES]
    CheckFormat -->|BYTES| ValidateBytes[Проверить формат подписи байтов]

    ValidateXMLFormat --> ExtractCert[Извлечь X.509 сертификат]
    ValidateCMSFormat --> ExtractCert
    ValidateBytes --> ExtractCert

    ExtractCert --> CheckIssuer{Сертификат<br/>выдан НУЦ РК?}

    CheckIssuer -->|Нет| Error_Issuer[Ошибка:<br/>Сертификат не от НУЦ РК]
    Error_Issuer --> LogError[Журналировать ошибку]
    LogError --> Return403[Вернуть 403 Forbidden]

    CheckIssuer -->|Да| CheckIIN[Проверить ИИН/БИН в сертификате<br/>совпадает с отправителем]

    CheckIIN --> IINMatch{ИИН/БИН<br/>совпадает?}

    IINMatch -->|Нет| Error_IIN[Ошибка:<br/>Несоответствие ИИН/БИН]
    Error_IIN --> LogError

    IINMatch -->|Да| CheckDates[Проверить NotBefore и NotAfter<br/>по времени Астаны]

    CheckDates --> DatesValid{Срок действия<br/>валиден?}

    DatesValid -->|Нет| Error_Expired[Ошибка:<br/>Срок действия истек]
    Error_Expired --> LogError

    DatesValid -->|Да| CheckChain[Построить цепочку сертификатов<br/>до корневого НУЦ РК]

    CheckChain --> ChainValid{Цепочка<br/>корректна?}

    ChainValid -->|Нет| Error_Chain[Ошибка:<br/>Некорректная цепочка]
    Error_Chain --> LogError

    ChainValid -->|Да| CheckOCSP[Отправить OCSP запрос к НУЦ РК]

    CheckOCSP --> OCSPResponse{OCSP<br/>ответ?}

    OCSPResponse -->|Timeout| FallbackCRL[Fallback: Проверка по CRL<br/>Base CRL + Delta CRL]
    OCSPResponse -->|Revoked| Error_Revoked[Ошибка:<br/>Сертификат отозван]
    Error_Revoked --> LogError

    OCSPResponse -->|Good| CheckKeyUsage[Проверить KeyUsage]

    FallbackCRL --> InCRL{Серийный номер<br/>в CRL?}

    InCRL -->|Да| Error_Revoked
    InCRL -->|Нет| CheckKeyUsage

    CheckKeyUsage --> KeyUsageValid{KeyUsage содержит:<br/>Цифровая подпись<br/>Неотрекаемость?}

    KeyUsageValid -->|Нет| Error_KeyUsage[Ошибка:<br/>Неверный KeyUsage]
    Error_KeyUsage --> LogError

    KeyUsageValid -->|Да| CheckAlgo[Проверить алгоритмы:<br/>Хэш: ГОСТ 34.311-95<br/>Подпись: ГОСТ 34.310-2004]

    CheckAlgo --> AlgoValid{Алгоритмы<br/>корректны?}

    AlgoValid -->|Нет| Error_Algo[Ошибка:<br/>Некорректный алгоритм]
    Error_Algo --> LogError

    AlgoValid -->|Да| CheckTimestamp[Проверить timestamp НУЦ РК<br/>в подписи]

    CheckTimestamp --> TimestampValid{Timestamp<br/>валиден?}

    TimestampValid -->|Нет| Error_Timestamp[Ошибка:<br/>Некорректный timestamp]
    Error_Timestamp --> LogError

    TimestampValid -->|Да| ComputeHash[Вычислить хэш документа]

    ComputeHash --> VerifySign[Проверить подпись с помощью<br/>открытого ключа из сертификата]

    VerifySign --> SignValid{Подпись<br/>корректна?}

    SignValid -->|Нет| Error_Sign[Ошибка:<br/>Подпись не соответствует документу]
    Error_Sign --> LogError

    SignValid -->|Да| LogSuccess[Журналировать успех:<br/>- Дата/время<br/>- ИИН/БИН подписанта<br/>- Документ ID<br/>- Серийный номер сертификата]

    LogSuccess --> SaveDoc[Сохранить подписанный документ<br/>в базу данных]

    SaveDoc --> Return200[Вернуть 200 OK<br/>сообщение success]

    Return200 --> End([Конец: Успешная валидация])
    Return403 --> End
```

---

## 6. Аутентификация по типам

### 6.1 Выбор метода аутентификации для API №2

```mermaid
flowchart TD
    Start([eGov Mobile получил API №1 response]) --> ParseAuthType[Извлечь document.auth_type<br/>из JSON ответа]

    ParseAuthType --> CheckType{Определить<br/>auth_type}

    CheckType -->|None| FlowNone[Аутентификация: None]
    CheckType -->|Token| FlowToken[Аутентификация: Token]
    CheckType -->|Eds| FlowEds[Аутентификация: Eds]

    FlowNone --> BuildNone[Построить запрос:<br/>Метод: GET<br/>URL: document.uri<br/>Headers:<br/>- Accept-Language: ru/kk/en]

    FlowToken --> ExtractToken[Извлечь document.auth_token<br/>из JSON]
    ExtractToken --> ValidateToken{Токен<br/>присутствует?}
    ValidateToken -->|Нет| ErrorNoToken[Ошибка:<br/>auth_token обязателен для Token]
    ErrorNoToken --> End([Показать ошибку])

    ValidateToken -->|Да| BuildToken[Построить запрос:<br/>Метод: GET<br/>URL: document.uri<br/>Headers:<br/>- Authorization: Bearer токен<br/>- Accept-Language: ru/kk/en]

    FlowEds --> GenerateEdsXML[Сгенерировать XML<br/>с URL и timestamp]

    GenerateEdsXML --> SelectAuthKey[Выбрать AUTH_*.p12 ключ<br/>пользователя]

    SelectAuthKey --> SignEdsXML[Подписать XML используя<br/>AUTH ключ]

    SignEdsXML --> BuildEds[Построить запрос:<br/>Метод: POST<br/>URL: document.uri<br/>Headers:<br/>- Content-Type: application/json<br/>- Accept-Language: ru/kk/en<br/>Body: XML с подписью]

    BuildNone --> SendRequest[Отправить запрос к API №2]
    BuildToken --> SendRequest
    BuildEds --> SendRequest

    SendRequest --> CheckResponse{HTTP<br/>статус?}

    CheckResponse -->|200 OK| ParseResponse[Получить JSON с документами]
    CheckResponse -->|401 Unauthorized| ErrorAuth[Ошибка аутентификации]
    ErrorAuth --> ShowAuthError[Показать:<br/>Ошибка аутентификации]
    ShowAuthError --> End

    CheckResponse -->|403 Forbidden| ErrorForbidden[Ошибка доступа]
    ErrorForbidden --> ShowForbiddenError[Показать:<br/>Доступ запрещен]
    ShowForbiddenError --> End

    CheckResponse -->|500| ErrorServer[Ошибка сервера]
    ErrorServer --> ParseErrorMsg[Извлечь сообщение об ошибке]
    ParseErrorMsg --> ShowServerError[Показать сообщение от сервера]
    ShowServerError --> End

    ParseResponse --> Success([Успех:<br/>Документы получены])
```

### 6.2 Примеры запросов для каждого типа аутентификации

```mermaid
flowchart LR
    subgraph None["Аутентификация: None"]
        direction TB
        N1[GET /api/egov-sign/documents/123]
        N2[Headers:<br/>Accept-Language: ru]
        N3[Body: пусто]
        N1 --> N2 --> N3
    end

    subgraph Token["Аутентификация: Token"]
        direction TB
        T1[GET /api/egov-sign/documents/123]
        T2[Headers:<br/>Authorization: Bearer abc123xyz<br/>Accept-Language: kk]
        T3[Body: пусто]
        T1 --> T2 --> T3
    end

    subgraph Eds["Аутентификация: Eds"]
        direction TB
        E1[POST /api/egov-sign/documents/123]
        E2[Headers:<br/>Content-Type: application/json<br/>Accept-Language: en]
        E3["Body:<br/>{<br/>  'xml': '<login><url>...</url>...<Signature>...</Signature></login>'<br/>}"]
        E1 --> E2 --> E3
    end
```

---

## 7. Архитектура интеграции Coube с eGov Mobile

### 7.1 Компоненты системы

```mermaid
graph TB
    subgraph "Coube Frontend (Vue.js)"
        WebUI[Веб интерфейс]
        QRGen[Генератор QR-кодов]
        WebSocket[WebSocket клиент]
    end

    subgraph "Coube Mobile (React Native)"
        MobileUI[Мобильный интерфейс]
        DeepLinkHandler[Deep Link обработчик]
        Polling[Polling сервис]
    end

    subgraph "Coube Backend (Spring Boot)"
        API1Controller[API №1 Controller<br/>/api/egov-sign/info/:id]
        API2Controller[API №2 Controller<br/>/api/egov-sign/documents/:id]
        SignService[Signing Service]
        ValidationService[Validation Service]
        KalkanService[Kalkan Integration<br/>(НУЦ РК)]
        WebhookService[Webhook Service]
    end

    subgraph "База данных"
        Documents[Документы]
        Signatures[Подписи]
        AuditLog[Журнал аудита]
    end

    subgraph "Внешние сервисы"
        eGovMobile[eGov Mobile App]
        НУЦ[НУЦ РК OCSP]
        SIEM[SIEM система]
    end

    WebUI -->|Запрос QR| QRGen
    QRGen -->|GET /api/egov-sign/info/:id| API1Controller

    MobileUI -->|Открыть deep link| DeepLinkHandler
    DeepLinkHandler -->|GET /api/egov-sign/info/:id| API1Controller

    API1Controller -->|Получить метаданные| SignService
    SignService -->|Читать| Documents

    eGovMobile -->|GET/POST API №2| API2Controller
    API2Controller -->|Получить документы| SignService

    eGovMobile -->|PUT подписанные| API2Controller
    API2Controller -->|Валидировать| ValidationService
    ValidationService -->|OCSP запрос| НУЦ

    ValidationService -->|Сохранить| Signatures
    ValidationService -->|Журналировать| AuditLog

    API2Controller -->|Webhook| WebhookService
    WebhookService -->|Уведомить| WebSocket
    WebSocket -->|Обновить UI| WebUI

    WebhookService -->|Уведомить| Polling
    Polling -->|Обновить UI| MobileUI

    AuditLog -->|Отправить логи| SIEM

    style eGovMobile fill:#e1f5ff
    style НУЦ fill:#ffe1e1
    style SIEM fill:#fff4e1
```

### 7.2 Последовательность обработки в Backend

```mermaid
sequenceDiagram
    participant Controller as Controller<br/>(API №1/№2)
    participant Service as Signing Service
    participant Validator as Validation Service
    participant Kalkan as Kalkan Service<br/>(НУЦ РК)
    participant DB as Database
    participant Audit as Audit Logger
    participant SIEM as SIEM System

    Note over Controller: API №1: GET /info/:id

    Controller->>Service: getSigningInfo(documentId)
    Service->>DB: findDocumentById(documentId)
    DB->>Service: Document entity
    Service->>Service: Построить response:<br/>- description<br/>- expiry_date<br/>- organisation<br/>- document (uri, auth_type, auth_token)
    Service->>Controller: SigningInfoDTO
    Controller->>Controller: Return JSON response

    Note over Controller: API №2: GET/POST /documents/:id

    Controller->>Service: getDocumentsToSign(documentId, authData)
    Service->>DB: findDocumentFiles(documentId)
    DB->>Service: List<DocumentFile>
    Service->>Service: Построить documentsToSign массив:<br/>- id, signMethod<br/>- nameRu/Kz/En<br/>- meta массив, documentXml/document
    Service->>Controller: DocumentsToSignDTO
    Controller->>Controller: Return JSON response

    Note over Controller: API №2: PUT /documents/:id (подписанные)

    Controller->>Validator: validateSignedDocuments(signedData)

    loop Для каждого подписанного документа
        Validator->>Validator: Извлечь ЭЦП
        Validator->>Validator: Проверить формат (XML/CMS)
        Validator->>Validator: Извлечь X.509 сертификат

        Validator->>Kalkan: checkCertificateIssuer(cert)
        Kalkan->>Validator: НУЦ РК issuer OK

        Validator->>Kalkan: checkCertificateDates(cert)
        Kalkan->>Validator: Даты валидны

        Validator->>Kalkan: verifyCertificateChain(cert)
        Kalkan->>Validator: Цепочка корректна

        Validator->>Kalkan: checkOCSP(cert)
        Kalkan->>Kalkan: OCSP запрос к НУЦ РК

        alt OCSP успешен
            Kalkan->>Validator: OCSP: good
        else OCSP недоступен
            Kalkan->>Validator: Fallback to CRL
            Validator->>Kalkan: checkCRL(cert)
            Kalkan->>Validator: Не в CRL списке
        end

        Validator->>Kalkan: verifySignature(document, signature, cert)
        Kalkan->>Validator: Подпись валидна
    end

    Validator->>Controller: ValidationResult (success/failure)

    alt Все подписи валидны
        Controller->>Service: saveSignedDocuments(signedData)
        Service->>DB: UPDATE documents SET status='SIGNED'
        Service->>DB: INSERT signatures (signature, certificate, timestamp)
        DB->>Service: Saved

        Service->>Audit: logSigningEvent(SUCCESS, documentId, userIIN, timestamp)
        Audit->>SIEM: Send syslog event (RFC 5424)

        Service->>Controller: Success
        Controller->>Controller: Return 200 OK сообщение success

    else Ошибка валидации
        Controller->>Audit: logSigningEvent(FAILED, documentId, error)
        Audit->>SIEM: Send syslog event (RFC 5424)

        Controller->>Controller: Return 403 Forbidden
    end
```

---

## 8. Обработка ошибок и edge cases

### 8.1 Обработка ошибок

```mermaid
flowchart TD
    Start([Начало процесса подписания]) --> Step1{Этап}

    Step1 -->|QR сканирование| CheckQR{QR корректен?}
    CheckQR -->|Нет| ErrorQR[Ошибка:<br/>Некорректный QR-код]
    ErrorQR --> End([Показать ошибку пользователю])

    CheckQR -->|Да| Step2

    Step1 -->|API №1| CallAPI1[Вызов GET API №1]
    CallAPI1 --> CheckAPI1{HTTP статус?}

    CheckAPI1 -->|200| Step2
    CheckAPI1 -->|404| Error404_1[Ошибка:<br/>Документ не найден]
    Error404_1 --> End
    CheckAPI1 -->|500| Error500_1[Ошибка:<br/>Ошибка сервера]
    Error500_1 --> End
    CheckAPI1 -->|Timeout| ErrorTimeout1[Ошибка:<br/>Превышено время ожидания]
    ErrorTimeout1 --> End

    Step2[Получен API №1 response] --> CheckExpiry{expiry_date<br/>не истек?}

    CheckExpiry -->|Истек| ErrorExpired[Ошибка:<br/>Срок действия документа истек]
    ErrorExpired --> End

    CheckExpiry -->|Активен| Step3[Вызов API №2]

    Step3 --> CheckAuth{auth_type<br/>корректен?}

    CheckAuth -->|Token без auth_token| ErrorNoToken[Ошибка:<br/>Токен не предоставлен]
    ErrorNoToken --> End

    CheckAuth -->|Eds, ошибка подписи XML| ErrorEdsSign[Ошибка:<br/>Не удалось подписать XML для аутентификации]
    ErrorEdsSign --> End

    CheckAuth -->|Корректен| CallAPI2[Запрос к API №2]

    CallAPI2 --> CheckAPI2{HTTP статус?}

    CheckAPI2 -->|200| Step4
    CheckAPI2 -->|401| Error401[Ошибка:<br/>Неверная аутентификация]
    Error401 --> End
    CheckAPI2 -->|403| Error403[Ошибка:<br/>Доступ запрещен]
    Error403 --> End
    CheckAPI2 -->|500| Error500_2[Показать message из JSON]
    Error500_2 --> End

    Step4[Получены документы] --> ValidateJSON{JSON<br/>валиден?}

    ValidateJSON -->|Нет| ErrorJSON[Ошибка:<br/>Некорректный формат данных]
    ErrorJSON --> End

    ValidateJSON -->|Да| Step5[Показать документы пользователю]

    Step5 --> UserSign{Пользователь<br/>подписывает?}

    UserSign -->|Отмена| Cancelled[Пользователь отменил]
    Cancelled --> End

    UserSign -->|Подписать| CheckKey{Ключ ЭЦП<br/>валиден?}

    CheckKey -->|Пароль неверный| ErrorPassword[Ошибка:<br/>Неверный пароль]
    ErrorPassword --> Step5

    CheckKey -->|Сертификат истек| ErrorCertExpired[Ошибка:<br/>Срок действия сертификата истек]
    ErrorCertExpired --> End

    CheckKey -->|Сертификат отозван| ErrorCertRevoked[Ошибка:<br/>Сертификат отозван]
    ErrorCertRevoked --> End

    CheckKey -->|Валиден| SignDocs[Подписать документы]

    SignDocs --> CheckTimestamp{НУЦ РК<br/>timestamp получен?}

    CheckTimestamp -->|Нет| ErrorTimestamp[Ошибка:<br/>Не удалось получить timestamp]
    ErrorTimestamp --> End

    CheckTimestamp -->|Да| SendSigned[PUT подписанные документы]

    SendSigned --> CheckPUT{HTTP статус?}

    CheckPUT -->|200| Success[Успех:<br/>Документы подписаны]
    Success --> End

    CheckPUT -->|403| ErrorValidation[Ошибка:<br/>Подпись не прошла валидацию]
    ErrorValidation --> End

    CheckPUT -->|500| ErrorServerPUT[Ошибка сервера при сохранении]
    ErrorServerPUT --> End
```

### 8.2 Edge Cases

```mermaid
flowchart TD
    Start([Edge Cases]) --> Case1{Случай}

    Case1 -->|Документ удален| Handle1[Поведение:<br/>API №1 возвращает 404<br/>eGov показывает: Документ не найден]

    Case1 -->|Документ уже подписан| Handle2[Поведение:<br/>API №1 возвращает информацию<br/>с флагом already_signed<br/>eGov показывает предупреждение]

    Case1 -->|Множественная подпись| Handle3[Поведение:<br/>Разрешить подписание несколькими лицами<br/>Сохранить все подписи<br/>Валидировать каждую отдельно]

    Case1 -->|Сеть пропала во время подписания| Handle4[Поведение:<br/>eGov сохраняет подписанные данные локально<br/>Повторяет PUT запрос при восстановлении сети<br/>Показывает индикатор повтора]

    Case1 -->|expiry_date истекает во время процесса| Handle5[Поведение:<br/>Backend проверяет при каждом запросе<br/>Если истек - возвращает ошибку<br/>eGov показывает: Срок действия истек]

    Case1 -->|OCSP и CRL недоступны| Handle6[Поведение:<br/>Backend возвращает 503 Service Unavailable<br/>eGov показывает: Сервис временно недоступен<br/>Предложить повторить позже]

    Case1 -->|Пользователь закрыл eGov до завершения| Handle7[Поведение:<br/>Подписание не завершено<br/>Статус документа не меняется<br/>Пользователь может повторить]

    Case1 -->|MIX_SIGN с разными методами| Handle8[Поведение:<br/>Обработать каждый документ<br/>согласно его signMethod<br/>Валидировать каждый отдельно]

    Case1 -->|Слишком большой документ| Handle9[Поведение:<br/>Backend проверяет размер<br/>Если > лимита - вернуть 413 Payload Too Large<br/>eGov показывает: Документ слишком большой]

    Case1 -->|Несколько документов, один невалиден| Handle10[Поведение:<br/>Отклонить все документы<br/>Вернуть 403 с информацией<br/>о конкретном невалидном документе]

    Handle1 --> End([Обработано])
    Handle2 --> End
    Handle3 --> End
    Handle4 --> End
    Handle5 --> End
    Handle6 --> End
    Handle7 --> End
    Handle8 --> End
    Handle9 --> End
    Handle10 --> End
```

---

## 9. Журналирование и аудит

### 9.1 Структура журнала событий

```mermaid
flowchart LR
    subgraph "Событие подписания"
        Event[Событие]
        Event --> Timestamp[Дата/время:<br/>ДД:ММ:ГГГГ ЧЧ:ММ:СС]
        Event --> Source[Источник:<br/>egov-sign-service]
        Event --> User[Пользователь:<br/>ИИН/БИН]
        Event --> IP[IP адрес клиента]
        Event --> StartTime[Время начала операции]
        Event --> EndTime[Время окончания операции]
        Event --> Level[Уровень:<br/>INFO/WARN/ERROR]
        Event --> Category[Категория:<br/>SIGN_DOCUMENT]
        Event --> Description[Описание события]
        Event --> Result[Результат:<br/>SUCCESS/FAILED]
        Event --> Details[Детали:<br/>Document ID, Cert Serial, etc]
    end

    Event --> SIEM[Отправка в SIEM<br/>по протоколу syslog RFC 5424]

    style SIEM fill:#fff4e1
```

### 9.2 Примеры журнальных записей

**Пример 1: Успешное подписание**
```
2025-10-19 14:23:45 egov-sign-service user=123456789012 ip=192.168.1.100 start=14:23:30 end=14:23:45 level=INFO category=SIGN_DOCUMENT description="Document signed successfully" result=SUCCESS details="doc_id=456, cert_serial=ABC123, method=CMS_WITH_DATA"
```

**Пример 2: Ошибка валидации**
```
2025-10-19 14:25:10 egov-sign-service user=987654321098 ip=10.0.0.50 start=14:25:00 end=14:25:10 level=ERROR category=SIGN_VALIDATION description="Signature validation failed" result=FAILED details="doc_id=789, reason=Certificate revoked"
```

**Пример 3: OCSP запрос**
```
2025-10-19 14:23:42 egov-sign-service user=123456789012 ip=192.168.1.100 start=14:23:41 end=14:23:42 level=INFO category=OCSP_REQUEST description="OCSP validation successful" result=SUCCESS details="cert_serial=ABC123, status=good"
```

---

## 10. Технические требования к реализации

### 10.1 Backend (coube-backend)

**Контроллеры:**
- `EgovSignController` - обработка API №1 и API №2

**Эндпоинты:**
```java
// API №1 - Получение информации о подписании
GET /api/egov-sign/info/ID документа
Response: {
  description: string,
  expiry_date: ISO8601,
  organisation: {...},
  document: {
    uri: string,  // URL для API №2
    auth_type: None | Token | Eds,
    auth_token?: string
  }
}

// API №2 - Получение документов для подписания
GET /api/egov-sign/documents/ID документа  // для auth_type=None или Token
POST /api/egov-sign/documents/ID документа  // для auth_type=Eds
Request (POST): { xml: string }
Response: {
  signMethod: string,
  version: number,
  documentsToSign: [...]
}

// API №2 - Отправка подписанных документов
PUT /api/egov-sign/documents/ID документа
Request: { подписанный JSON }
Response: 200 OK сообщение success или 403 Forbidden
```

**Сервисы:**
- `EgovSigningService` - бизнес-логика подписания
- `DocumentValidationService` - валидация ЭЦП
- `KalkanIntegrationService` - интеграция с НУЦ РК (OCSP, CRL)
- `AuditLoggingService` - журналирование в SIEM

**Модели:**
```java
// DTO для API №1
class SigningInfoDTO {
  String description;
  String expiryDate;
  OrganisationDTO organisation;
  DocumentAuthDTO document;
}

// DTO для API №2
class DocumentsToSignDTO {
  String signMethod;
  Integer version;
  List<DocumentToSignDTO> documentsToSign;
}

// Entity для хранения подписей
@Entity
class DigitalSignature {
  Long id;
  Long documentId;
  String iin;
  String certificateSerial;
  String signatureData;  // base64
  String certificateData;  // base64
  Instant signedAt;
  Boolean validated;
}
```

### 10.2 Frontend (coube-frontend)

**Компоненты:**
- `QrSignatureModal.vue` - модальное окно с QR-кодом
- `SignatureStatus.vue` - отображение статуса подписания

**Функционал:**
```javascript
// Генерация QR-кода
async function generateQrCode(documentId) {
  const apiUrl = `${API_BASE}/api/egov-sign/info/$ID документа`;
  const qrContent = `mobileSign:${apiUrl}`.replace(/\s/g, '');
  return QRCode.toDataURL(qrContent);
}

// Подписка на обновления через WebSocket
socket.on('document-signed', (data) => {
  if (data.documentId === currentDocumentId) {
    updateDocumentStatus('SIGNED');
    showNotification('Документ успешно подписан');
  }
});
```

### 10.3 Mobile (coube-mobile)

**Компоненты:**
- `DeepLinkHandler.tsx` - обработка deep links
- `SignatureButton.tsx` - кнопка запуска подписания

**Функционал:**
```typescript
// Построение deep link
function buildEgovDeepLink(documentId: string, token: string): string {
  const api1Url = `${API_BASE}/api/egov-sign/info/$ID документа?token=$токен`;
  const encodedUrl = encodeURIComponent(api1Url);

  if (Platform.OS === 'ios') {
    return `https://mgovsign.page.link/?link=${encodedUrl}&isi=1476128386&ibi=kz.egov.mobile`;
  } else {
    return `https://mgovsign.page.link/?link=${encodedUrl}&apn=kz.mobile.mgov`;
  }
}

// Открытие deep link
async function openEgovSigning(documentId: string) {
  const deepLink = buildEgovDeepLink(documentId, authToken);
  await Linking.openURL(deepLink);

  // Начать polling статуса
  startPollingSignatureStatus(documentId);
}
```

---

## Заключение

Данные flow диаграммы покрывают все аспекты интеграции Coube с eGov Mobile для QR и кросс подписания:

✅ **QR подписание** - полный поток от генерации QR-кода до получения подписанного документа

✅ **Кросс подписание** - построение динамических ссылок для iOS/Android и обработка deep links

✅ **API №1 и API №2** - детальная спецификация всех методов и типов аутентификации

✅ **Валидация ЭЦП** - полная проверка согласно требованиям НУЦ РК

✅ **Обработка ошибок** - все возможные ошибки и edge cases

✅ **Журналирование** - структура логов для SIEM системы

✅ **Техническая реализация** - конкретные эндпоинты, модели и компоненты для Coube

Документация готова к использованию разработчиками для реализации функционала подписания через eGov Mobile.
