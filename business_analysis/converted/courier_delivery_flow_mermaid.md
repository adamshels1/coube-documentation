# Бизнес-процесс курьерской доставки (Mermaid)

## Sequence Diagram - Основной флоу

```mermaid
sequenceDiagram
    participant T as TEEZ_PVZ
    participant C as COUBE Platform
    participant L as Логист
    participant K as Курьер (Mobile)
    participant S as Склад

    Note over T: 1. Товар поступает на склад
    T->>T: Формирование маршрутного листа
    
    Note over T,C: API Интеграция
    T->>+C: POST /api/v1/courier/waybill/upload<br/>Загрузка маршрутного листа
    C->>C: Создание заявки курьерского типа
    C->>C: Валидация и добавление склада в конец
    C-->>-T: Response: Success/Error
    
    Note over C,L: Управление маршрутом
    L->>C: Редактирование маршрутного листа
    L->>C: Назначение курьера на маршрут
    C->>K: Push уведомление о назначении
    
    Note over C,K: Запуск в работу
    L->>C: Отправка маршрутного листа В РАБОТУ
    C->>+K: Отправка заявки в мобильное приложение
    K->>K: Принять/Отклонить заявку
    K->>-C: Статус принятия
    
    Note over K: Выполнение доставок
    K->>C: "Начать путь"
    loop Каждая точка доставки
        K->>C: Прибытие на точку
        K->>K: Доставка заказа
        alt Успешная доставка
            K->>C: "Отдал заказ" + SMS код + скан
        else Возврат
            K->>C: "Отдал, но возврат"
        else Не отдал
            K->>C: "Не отдал" + причина + дата переноса
        end
    end
    
    Note over K,S: Завершение маршрута
    K->>C: Завершение маршрута
    C->>C: Подсчет итогов по статусам
    C->>C: Пометка проблемных адресов
    
    Note over C,T: Асинхронная отправка результатов
    C->>C: Запись в PUB/SUB таблицу
    C->>+T: POST /api/waybill/results<br/>Отправка итогов
    T-->>-C: Response: Success/Error
    
    Note over K,S: Физическая сверка
    K->>S: Возврат на склад с недоставленными заказами
    S->>S: Сверка данных с системой COUBE
```

## Flowchart - Структура системы

```mermaid
flowchart TD
    A[TEEZ_PVZ Система] -->|API Integration| B[COUBE Platform]
    B --> C[Логист Web Interface]
    B --> D[Курьер Mobile App]
    
    C --> C1[Редактирование МЛ]
    C --> C2[Назначение курьеров]
    C --> C3[Мониторинг доставок]
    
    D --> D1[Принятие заявок]
    D --> D2[GPS навигация]
    D --> D3[Статусы доставки]
    D --> D4[Сканирование документов]
    
    B --> E[Database]
    E --> E1[(Маршрутные листы)]
    E --> E2[(Курьеры)]
    E --> E3[(Заказы)]
    E --> E4[(Геозоны)]
    E --> E5[(Логи интеграций)]
    
    B -->|Async| F[Integration Service]
    F --> F1[PUB/SUB Queue]
    F --> F2[Retry Logic]
    F --> F3[Error Handling]
    
    style A fill:#a5d8ff
    style B fill:#b2f2bb  
    style D fill:#ffec99
    style F fill:#ffe3e3
```

## State Diagram - Статусы заказа

```mermaid
stateDiagram-v2
    [*] --> Создан: Загружен из TEEZ_PVZ
    Создан --> Назначен: Логист назначил курьера
    Назначен --> ВРаботе: Курьер принял заявку
    ВРаботе --> ВПути: "Начать путь"
    
    ВПути --> Доставлен: "Отдал заказ" + SMS + скан
    ВПути --> Возвращен: "Отдал, но покупатель вернул"
    ВПути --> НеДоставлен: "Не отдал заказ"
    ВПути --> НеДоехал: "Курьер не доехал"
    
    НеДоставлен --> [*]: Причина: customer_not_accessed
    НеДоставлен --> [*]: Причина: customer_postponed
    
    Доставлен --> [*]
    Возвращен --> [*]
    НеДоехал --> [*]
```

## Entity Relationship - Структура данных

```mermaid
erDiagram
    WAYBILL ||--o{ ORDER : contains
    WAYBILL {
        int id
        string external_id
        date created_date
        string status
        int courier_id
    }
    
    ORDER ||--|| ADDRESS : "delivered_to"
    ORDER {
        int id
        string external_id
        string barcode
        string company_name
        string status
        datetime delivery_time
        string verification_type
    }
    
    ADDRESS {
        int id
        string full_address
        float latitude
        float longitude
        boolean is_problematic
    }
    
    COURIER ||--o{ WAYBILL : assigned
    COURIER {
        int id
        string external_teez_id
        string full_name
        string phone
        boolean active
        string current_status
    }
    
    GEOZONE ||--o{ COURIER : covers
    GEOZONE {
        int id
        string name
        polygon coordinates
    }
    
    INTEGRATION_LOG ||--|| ORDER : tracks
    INTEGRATION_LOG {
        int id
        string object_type
        int object_id
        string event_type
        datetime created_at
        boolean success
        text error_message
    }
```

## 🔥 Критические API Endpoints

### 1. Входящая интеграция от TEEZ_PVZ:
```
POST /api/v1/integration/teez/waybill/upload
```

### 2. Исходящая интеграция к TEEZ_PVZ:
```  
POST /api/waybill/results (к их системе)
```

### 3. Расширение Driver API:
```
PUT /api/v1/driver/orders/{id}/delivery-confirmation
POST /api/v1/driver/orders/{id}/scan-document  
PUT /api/v1/driver/orders/{id}/return-reason
```

---
*Диаграммы созданы с помощью Mermaid для визуализации в Markdown*