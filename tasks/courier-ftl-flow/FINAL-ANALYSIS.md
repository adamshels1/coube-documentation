# Courier FTL Flow — Финальный анализ
**Дата:** 3 апреля 2026  
**Статус:** Готов к подтверждению

---

## 1. СУТЬ ЗАДАЧИ

Добавить для курьерской доставки (`COURIER_DELIVERY`) полноценный FTL-флоу:

| | Сейчас (импорт) | Цель (FTL-флоу) |
|--|--|--|
| Создание | Автоматически из TEEZ/Kaspi/etc | Заказчик вручную |
| Исполнитель | Заказчик сам назначает своего курьера | Сторонний перевозчик |
| Договор | Нет | EDS, один документ на маршрут |
| Факторинг | Нет | Да |
| Флоу | IMPORTED → VALIDATED → курьер | FORMING → CREATED → отклики → SIGNED → курьер |

Оба флоу работают параллельно. Различаются по `source_system`:  
- Импорт: `source_system = 'TEEZ_PVZ'` / `'KASPI'` / etc  
- Ручное создание: `source_system = null`

---

## 2. ЧТО УЖЕ ГОТОВО (не трогаем)

### Backend
| Компонент | Файл | Статус |
|-----------|------|--------|
| `TransportationType.COURIER_DELIVERY` | `dictionaries/enumeration/TransportationType.java` | ✅ Есть |
| Создание заявки любого типа | `CustomerApplicationController.java:265` — `POST /api/v1/customer/transportation/complete` | ✅ Готов |
| Список заявок для перевозчика + фильтр по типу | `ExecutorController.java:230` — `POST /api/v1/executor/transportations` | ✅ Готов |
| Встречное предложение цены | `ExecutorController.java:88` — `POST /api/v1/executor/counter-offer/{id}` | ✅ Готов |
| Принятие цены перевозчиком | `ExecutorController.java:112` — `POST /api/v1/executor/accept-price/{id}` | ✅ Готов |
| Назначение курьера перевозчиком | `ExecutorController.java:119` — `POST /api/v1/executor/{id}/assign-courier` | ✅ Готов |
| Замена курьера | `ExecutorController.java:133` — `POST /api/v1/executor/{id}/replace-courier` | ✅ Готов |
| Валидация: assignCourier только для COURIER_DELIVERY | `ExecutorService.java:771` | ✅ Готов |
| Фильтр по `transportationType` в спецификации | `ExecutorService.java:874` | ✅ Готов |
| Видимость заявок для перевозчика | `ExecutorService.java:1146` — `visibilityForExecutor()` | ✅ Готов |
| Ценообразование (TransportationCost) | `TransportationCostService.java` | ✅ Работает для любого типа |
| Agreement (договор) — нет ограничений по типу | `Agreement.java:transportationType` | ✅ Поддерживает COURIER_DELIVERY |
| Факторинг через TransportationCost | `FactoringService.java` | ✅ Работает для любого типа |
| Contract entity (один на заявку) | `Contract.java` | ✅ Готов |
| Импортный флоу (TEEZ/Kaspi) | `CourierIntegrationService.java` | ✅ Не трогаем |

### Frontend
| Компонент | Файл | Статус |
|-----------|------|--------|
| Подписание EDS (QR + NCALayer) | `ContractSigningFlow.vue` | ✅ Готов |
| Модальное окно назначения курьера | `CourierAssignBody.vue` | ✅ Готов |
| Просмотр маршрутного листа (для логиста) | `CourierDeliveryPage2.vue` | ✅ Готов |
| API клиент для курьерских операций | `src/api/courier.ts` | ✅ Готов |

### Mobile
| Компонент | Файл | Статус |
|-----------|------|--------|
| Список заказов водителя | `MyOrdersScreen.tsx` | ✅ Готов |
| Детали курьерского маршрута | `CourierOrderScreen.tsx` | ✅ Готов |
| Статусные действия (arrival, departure, finish) | `api/index.ts:314` | ✅ Готов |
| Обновление статуса заказа в точке | `updateCourierOrderStatus()` | ✅ Готов |
| SMS подтверждение, загрузка фото | `sendCourierDeliverySms()`, `uploadCourierPhoto()` | ✅ Готов |

---

## 3. ЧТО НУЖНО СДЕЛАТЬ

### 3.1 Backend

#### [BE-1] Уведомления для нового флоу — КРИТИЧНО
**Файл:** `notifications/service/OrderNotificationService.java`  
**Что добавить:** события специфичные для нового флоу курьерки:
- Публикация курьерской заявки → все перевозчики
- Перевозчик откликнулся → заказчику
- Договор подписан → обеим сторонам
- Курьер назначен → курьеру (push + SMS)
- Курьер принял → заказчику и перевозчику

#### [BE-2] Валидация при создании COURIER_DELIVERY вручную — ВАЖНО
**Файл:** `customer/CustomerTransportationService.java` (метод `createCompleteTransportation`)  
**Что добавить:**
```java
// Если transportationType == COURIER_DELIVERY && sourceSystem == null (ручное создание):
// 1. source_system = null (не IMPORTED)
// 2. external_waybill_id = null
// 3. Запрет статусов IMPORTED/VALIDATED для ручного флоу
```

#### [BE-3] Workflow создания и подписания договора — КРИТИЧНО
**Проблема:** Для FTL через `agreementBased=false` создаётся `Contract`. Нужно убедиться, что этот же путь работает для `COURIER_DELIVERY`.  
**Файлы:**
- `agreement/service/AgreementService.java`
- `applications/entity/Contract.java`

**Нужно проверить и при необходимости добавить:**
1. Endpoint для принятия цены заказчиком и создания договора
2. Отправку договора перевозчику на подпись (EDS)
3. Финальное подписание заказчиком → статус `SIGNED_CUSTOMER`

#### [BE-4] Статусные переходы для assignCourier — ВАЖНО
**Файл:** `executor/service/ExecutorService.java:768`  
**Проверить:** при каком статусе работает `assignCourier` для нового флоу?  
Ожидаемое: при `SIGNED_CUSTOMER` → `WAITING_DRIVER_RESPONSE` → после назначения `WAITING_DRIVER_CONFIRMATION`

#### [BE-5] Индексы БД — ПРОИЗВОДИТЕЛЬНОСТЬ
```sql
CREATE INDEX IF NOT EXISTS idx_transportation_type_status 
  ON applications.transportation(transportation_type, status);
CREATE INDEX IF NOT EXISTS idx_cargo_loading_route_action 
  ON gis.cargo_loading_history(route_history_id, action);
CREATE INDEX IF NOT EXISTS idx_cargo_loading_order_num 
  ON gis.cargo_loading_history(route_history_id, order_num);
```

---

### 3.2 Frontend

#### [FE-1] Добавить COURIER_DELIVERY в enum и словарь — КРИТИЧНО
**Файл 1:** `src/types/enums/transportationType.ts`
```typescript
export const enum ETransportationType {
  // ... существующие
  COURIER_DELIVERY = 'COURIER_DELIVERY', // ДОБАВИТЬ
}
```

**Файл 2:** `src/vars/application.ts`
```typescript
[ETransportationType.COURIER_DELIVERY]: {
  title: 'application.type.COURIER_DELIVERY.title',
  subtitle: 'application.type.COURIER_DELIVERY.subtitle',
  disabled: false,
}
```

#### [FE-2] i18n переводы — КРИТИЧНО
**Файлы:** `src/i18n/ru.json`, `en.json`, `kk.json`, `zh.json`  
Добавить ключи для `COURIER_DELIVERY` типа.

#### [FE-3] Форма создания COURIER_DELIVERY заявки — КРИТИЧНО
**Файл:** `src/views/Transportations/TransportationCreate/TransportationsCreatePage.vue`  
**Что добавить:**
- Блок ввода точек доставки (можно переиспользовать компоненты из CargoLoadings)
- Поля: адрес, координаты, контактное лицо, телефон, требования (SMS/фото)
- Валидация: минимум 1 точка погрузки + 1 точка разгрузки

#### [FE-4] Список перевозок заказчика — фильтр COURIER_DELIVERY
**Файл:** `src/views/Applications/ApplicationsPage.vue`  
**Что добавить:**
- Фильтр по типу `COURIER_DELIVERY` в списке заявок
- Визуальное отличие карточки курьерской заявки от FTL

#### [FE-5] Страница деталей заявки для заказчика — ВАЖНО
**Нужно убедиться**, что после создания `COURIER_DELIVERY` заявки заказчик видит:
- Список откликов перевозчиков
- Возможность принять оффер и подписать договор через `ContractSigningFlow.vue`

#### [FE-6] UI для перевозчика: отклик на курьерскую заявку — ВАЖНО
**Файл:** `src/views/Applications/` (страница перевозчика)  
**Что добавить:**
- Заявки типа `COURIER_DELIVERY` должны отображаться в списке перевозчика
- Форма отклика (встречное предложение цены) — вероятно переиспользуется из FTL

#### [FE-7] Назначение курьера перевозчиком — ВАЖНО
**Файл:** `src/components/ModalContent/CourierAssign/CourierAssignBody.vue`  
**Уточнить:** этот компонент используется логистом (импортный флоу). Для нового флоу перевозчик назначает из **своих** сотрудников.  
**Действие:** Проверить какой endpoint вызывается. Для нового флоу должен использоваться:
```
POST /api/v1/executor/{transportationId}/assign-courier
```
а не `/api/v1/courier/waybills/{id}/assign`

---

### 3.3 Mobile

#### [MOB-1] Проверить фильтрацию в MyOrdersScreen — ПРОВЕРКА
**Файл:** `src/screens/MyOrdersScreen/MyOrdersScreen.tsx`  
**Убедиться:** заказы `COURIER_DELIVERY` (из нового флоу) попадают в список курьера так же, как из импорта.  
Различие: в новом флоу у заказа не будет `externalId` / `trackNumber` из внешней системы — нужно проверить нет ли жёсткой привязки к этим полям в `CourierOrderScreen.tsx`.

#### [MOB-2] Проверить CourierOrderScreen при source_system=null — ПРОВЕРКА
**Файл:** `src/screens/CourierOrderScreen/CourierOrderScreen.tsx`  
В текущем импортном флоу у каждого заказа есть `trackNumber` и `externalId`. В новом флоу эти поля будут `null` или заполнены заказчиком вручную.  
**Убедиться:** экран не ломается при отсутствии этих полей.

---

## 4. ПОЛНЫЙ ФЛОУ (ЦЕЛЕВОЙ)

```
┌─────────────────────────────────────────────────────────────────────┐
│  1. ЗАКАЗЧИК создаёт курьерскую заявку                              │
│     Frontend: TransportationsCreatePage.vue                          │
│     → POST /api/v1/customer/transportation/complete                  │
│       { transportationType: "COURIER_DELIVERY",                      │
│         cargoLoadings: [...точки], costInfo: {...} }                 │
│     → Transportation создаётся: status=FORMING → CREATED             │
│     → source_system = null (отличие от импорта)                     │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  2. ПЕРЕВОЗЧИК видит заявку и откликается                           │
│     Frontend: ApplicationsPage.vue (фильтр COURIER_DELIVERY)        │
│     → GET /api/v1/executor/transportations                           │
│       { transportationType: "COURIER_DELIVERY", status: "CREATED" } │
│     → POST /api/v1/executor/counter-offer/{id}                       │
│     → Transportation: status=WAITING_CUSTOMER_DECISION              │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  3. ЗАКАЗЧИК выбирает перевозчика и подписывает договор             │
│     Frontend: ContractSigningFlow.vue                                │
│     → POST /api/v1/customer/accept-price/{costId}                   │
│     → Создаётся Contract, отправляется перевозчику на EDS подпись   │
│     → Перевозчик подписывает                                         │
│     → Заказчик подписывает → status=SIGNED_CUSTOMER                 │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  4. ПЕРЕВОЗЧИК назначает курьера                                     │
│     Frontend: CourierAssign modal (executor side)                    │
│     → POST /api/v1/executor/{id}/assign-courier                      │
│       { courierId: ..., transportId: ... (опционально) }            │
│     → Transportation: executor_employee_id = courierId              │
│     → status = WAITING_DRIVER_CONFIRMATION                           │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  5. КУРЬЕР принимает на мобилке                                      │
│     Mobile: MyOrdersScreen → CourierOrderScreen                     │
│     → PUT /api/v1/driver/orders/{id}/accept                          │
│     → status = DRIVER_ACCEPTED                                       │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  6. КУРЬЕР исполняет маршрут                                         │
│     → PUT /api/v1/driver/orders/{id}/start → ON_THE_WAY             │
│     → PUT /api/v1/driver/orders/{id}/arrival (на точке)             │
│     → PUT /api/v1/courier/orders/{id}/courier-orders/{orderId}/status│
│       (DELIVERED / NOT_DELIVERED / RETURNED)                         │
│     → PUT /api/v1/driver/orders/{id}/departure                       │
│     → ... повторяет для каждой точки ...                             │
│     → Все точки пройдены → status = FINISHED                        │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│  7. ФИНАНСОВЫЕ ДОКУМЕНТЫ                                             │
│     → Создаётся Invoice + Act                                        │
│     → При is_factoring_used=true → FactoringPayoutRequest            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 5. СТАТУСНЫЕ ПЕРЕХОДЫ

```
FORMING                        ← Ручное создание (source_system=null)
  ↓ createCompleteTransportation()
CREATED                        ← Опубликована, видна перевозчикам
  ↓ saveCounterOfferPrice() (перевозчик)
WAITING_CUSTOMER_DECISION      ← Есть отклики
  ↓ acceptPrice() + EDS подпись обеих сторон
SIGNED_CUSTOMER                ← Договор подписан
  ↓ assignCourier() (перевозчик)
WAITING_DRIVER_RESPONSE        ← (промежуточный, если нет курьера)
  ↓ driverAssigned
WAITING_DRIVER_CONFIRMATION    ← Курьер назначен, ждёт подтверждения
  ↓ driverAccept() (мобилка)
DRIVER_ACCEPTED
  ↓ startDelivery() (мобилка)
ON_THE_WAY
  ↓ все точки пройдены
FINISHED

CANCELED ← в любой момент до DRIVER_ACCEPTED
```

**Импортный флоу (параллельный, не трогаем):**
```
IMPORTED → VALIDATED → WAITING_DRIVER_CONFIRMATION → ON_THE_WAY → FINISHED
```

---

## 6. ПОДВОДНЫЕ КАМНИ

### 6.1 Критичные

| # | Проблема | Решение |
|---|---------|---------|
| 1 | Назначение курьера в `CourierAssign` модале на фронте — нужно проверить какой endpoint вызывается. Для нового флоу должен вызываться `/executor/{id}/assign-courier`, а не `/courier/waybills/{id}/assign` | Проверить и исправить endpoint в компоненте |
| 2 | `CourierOrderScreen` на мобилке может ожидать `trackNumber` / `externalId` из внешней системы. В ручном флоу этих данных нет | Проверить и сделать эти поля опциональными |
| 3 | Workflow подписания договора (Contract + EDS) для `COURIER_DELIVERY` — нужно убедиться что он идёт по той же ветке, что FTL (`agreementBased=false`), а не через AgreementExecutor | Сквозная проверка в backend |
| 4 | Статус `assignCourier` — метод в `ExecutorService` работает при `COURIER_DELIVERY` типе, но нужно убедиться при каком статусе Transportation он разрешён (`SIGNED_CUSTOMER` vs `WAITING_DRIVER_RESPONSE`) | Проверить условие в `ExecutorService.java:768` |

### 6.2 Важные

| # | Проблема | Решение |
|---|---------|---------|
| 5 | `ETransportationType` на фронте не содержит `COURIER_DELIVERY` — заявку такого типа нельзя создать через UI | [FE-1] добавить в enum |
| 6 | Уведомления: текущие события не охватывают новый флоу курьерки | [BE-1] добавить события |
| 7 | Производительность при 50+ точках маршрута | [BE-5] добавить индексы |
| 8 | Факторинг требует разрешения у организации (`organization.isFactoringAllowed()`) — нужно убедиться что проверка проходит для COURIER_DELIVERY | Тест в рамках тестирования факторинга |

### 6.3 На будущее (не делаем сейчас)
- Ценообразование по точкам (сейчас — стоимость маршрута целиком)
- Страховка
- Импорт точек из файла (CSV/Excel)

---

## 7. ЗАДАЧИ (СПИСОК)

### Backend

| ID | Задача | Приоритет | Оценка |
|----|--------|-----------|--------|
| BE-1 | Добавить уведомления для нового курьерского флоу в `OrderNotificationService` | 🔴 Критично | 3ч |
| BE-2 | Валидация при создании COURIER_DELIVERY вручную (`source_system=null`, блокировка IMPORTED/VALIDATED) | 🔴 Критично | 2ч |
| BE-3 | Проверить и при необходимости доработать workflow создания/подписания Contract для COURIER_DELIVERY | 🔴 Критично | 4ч |
| BE-4 | Проверить статусные условия в `ExecutorService.assignCourier` для нового флоу | 🟡 Важно | 2ч |
| BE-5 | Добавить индексы БД (Flyway migration) | 🟡 Важно | 1ч |
| BE-6 | Unit тесты для нового флоу | 🟡 Важно | 4ч |

### Frontend

| ID | Задача | Приоритет | Оценка |
|----|--------|-----------|--------|
| FE-1 | Добавить `COURIER_DELIVERY` в `ETransportationType` enum | 🔴 Критично | 30мин |
| FE-2 | Добавить `COURIER_DELIVERY` в `transportationTypesDictionary` + i18n переводы (ru/en/kk/zh) | 🔴 Критично | 1ч |
| FE-3 | Форма создания — блок ввода точек доставки для COURIER_DELIVERY | 🔴 Критично | 1д |
| FE-4 | Список заявок заказчика — фильтр и отображение COURIER_DELIVERY | 🟡 Важно | 3ч |
| FE-5 | Страница деталей заявки — цепочка приёма оффера → подпись договора для COURIER_DELIVERY | 🔴 Критично | 4ч |
| FE-6 | Список заявок перевозчика — COURIER_DELIVERY отображается и фильтруется | 🟡 Важно | 2ч |
| FE-7 | Проверить и исправить endpoint в `CourierAssignBody.vue` для перевозчика (`/executor/{id}/assign-courier`) | 🔴 Критично | 1ч |

### Mobile

| ID | Задача | Приоритет | Оценка |
|----|--------|-----------|--------|
| MOB-1 | Проверить `MyOrdersScreen` — заказы нового флоу попадают в список | 🟡 Важно | 1ч |
| MOB-2 | Проверить `CourierOrderScreen` — работает без `trackNumber`/`externalId` (поля опциональны) | 🔴 Критично | 2ч |

### QA

| ID | Задача | Приоритет | Оценка |
|----|--------|-----------|--------|
| QA-1 | End-to-end тест полного флоу на stage | 🔴 Критично | 1д |
| QA-2 | Тест импортного флоу — убедиться что не сломан | 🟡 Важно | 3ч |
| QA-3 | Тест факторинга для COURIER_DELIVERY | 🟡 Важно | 2ч |

---

## 8. КЛЮЧЕВЫЕ ФАЙЛЫ

### Backend (по приоритету)
```
coube-backend/src/main/java/kz/coube/backend/
├── executor/service/ExecutorService.java               # assignCourier (768), visibilityForExecutor (1146)
├── customer/CustomerTransportationService.java         # createCompleteTransportation
├── notifications/service/OrderNotificationService.java # НУЖНО расширить
├── agreement/service/AgreementService.java             # Договор
├── applications/entity/Transportation.java             # Entity
├── applications/entity/Contract.java                  # Контракт
├── dictionaries/enumeration/TransportationType.java    # Enum (готов)
└── courier/service/CourierIntegrationService.java      # Импортный флоу (не трогаем)
```

### Frontend (по приоритету)
```
coube-frontend/src/
├── types/enums/transportationType.ts                   # ДОБАВИТЬ COURIER_DELIVERY
├── vars/application.ts                                 # ДОБАВИТЬ в словарь
├── i18n/*.json                                         # ДОБАВИТЬ переводы
├── views/Transportations/TransportationCreate/         # Форма создания
├── views/Applications/ApplicationsPage.vue             # Список
├── components/ModalContent/CourierAssign/              # Назначение курьера
└── components/ContractSigningFlow/                     # EDS (готов)
```

### Mobile (проверка)
```
coube-mobile/src/
├── screens/MyOrdersScreen/MyOrdersScreen.tsx           # Проверить фильтрацию
├── screens/CourierOrderScreen/CourierOrderScreen.tsx   # Проверить без externalId
└── api/index.ts                                        # API вызовы (готовы)
```

---

## 9. УТОЧНЁННЫЕ ТРЕБОВАНИЯ

| # | Вопрос | Ответ |
|---|--------|-------|
| 1 | Договор | Один на весь маршрут — между заказчиком и перевозчиком |
| 2 | Ценообразование | Стоимость маршрута целиком (по точкам — в будущем) |
| 3 | EDS при изменении маршрута | Да, один документ, переподпись обеими сторонами |
| 4 | Роль перевозчика-курьера | EXECUTOR |
| 5 | Факторинг | Нужен в первой версии |
| 6 | Старый импортный флоу | Остаётся параллельно |
| 7 | Создание точек маршрута | Ручной ввод (импорт из файла — в будущем) |
| 8 | Страховка | Не делаем (в будущем) |
| 9 | EDS маршрута | Подпись одного документа целиком |
| 10 | Видимость заявки | Все перевозчики, фильтр по типу `COURIER_DELIVERY` |
