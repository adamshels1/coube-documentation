# Задача 23: Добавить поле "Квартира / Офис"

## 🎯 Цель

Добавить необязательное поле "Квартира / Офис" в API импорта маршрутных листов от TEEZ для более точной адресации доставки.

## 📋 Описание

При курьерской доставке важно указывать не только основной адрес, но и конкретную квартиру или офис. Это поле будет дополнением к основному адресу и поможет курьеру более точно определить место доставки.

**Примеры использования:**
- "Квартира 12"
- "Офис 301"
- "Подъезд 2, квартира 45"
- "3 этаж, офис А"

Нужно добавить это поле в:
1. API импорта маршрутного листа `POST /api/v1/integration/waybills`
2. API редактирования маршрута логистом `PUT /api/v1/courier/waybills/{id}`
3. API для курьера (чтобы он видел эту информацию)

---

## 🔧 Изменения

### 1. API Request (добавить 1 поле)

В структуре `deliveries[]` добавить:

```json
{
  "deliveries": [
    {
      "sort": 2,
      "address": "Алматы, мкр. Самал-2, дом 58",
      "apartment": "кв. 12",  // НОВОЕ ПОЛЕ
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      },
      // ... остальные поля
    }
  ]
}
```

**Тип данных:**
- `apartment`: `String` (может быть null или пустой строкой)

**Обязательность:** НЕ обязательное поле (optional)

**Длина:** До 255 символов

---

### 2. Database Migration

**Файл:** `V2025_12_22_XX__add_apartment_to_cargo_loading.sql`

```sql
-- Добавляем поле квартиры/офиса в точки маршрута
ALTER TABLE gis.cargo_loading_history
ADD COLUMN IF NOT EXISTS apartment VARCHAR(255);

-- Комментарий
COMMENT ON COLUMN gis.cargo_loading_history.apartment
  IS 'Квартира / Офис для курьерской доставки (дополнение к основному адресу)';

-- Индекс не требуется, так как поле используется только для отображения
```

---

### 3. Backend Entity

**Файл:** `coube-backend/src/main/java/kz/coube/backend/route/entity/CargoLoadingHistory.java`

```java
@Entity
@Table(name = "cargo_loading_history", schema = "gis")
public class CargoLoadingHistory extends BaseIdEntity {

  // ... существующие поля

  @Column(name = "address")
  private String address;

  // Новое поле для курьерской доставки
  @Column(name = "apartment", length = 255)
  private String apartment;

  @Column(name = "contact_person_name")
  private String contactPersonName;

  // ... остальные поля и методы
}
```

---

### 4. DTO для импорта

**Файл:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/DeliveryPointDto.java`

```java
@Data
@NoArgsConstructor
@AllArgsConstructor
public class DeliveryPointDto {

  // ... существующие поля

  @JsonProperty("address")
  private String address;

  @JsonProperty("apartment")
  @Size(max = 255, message = "Apartment must not exceed 255 characters")
  private String apartment;  // Квартира / Офис

  @JsonProperty("receiver")
  private ReceiverDto receiver;

  // ... остальные поля
}
```

---

### 5. Маппер в сервисе

В сервисе `CourierIntegrationService.createRouteFromWaybill()` добавить:

```java
// Добавить при создании CargoLoadingHistory из DeliveryPoint
CargoLoadingHistory clh = new CargoLoadingHistory();
clh.setAddress(point.getAddress());
clh.setApartment(point.getApartment());  // НОВОЕ
clh.setContactPersonName(point.getReceiver() != null ? point.getReceiver().getName() : null);
// ... остальные поля
```

---

### 6. API Response (для курьера)

**Файл:** `coube-backend/src/main/java/kz/coube/backend/driver/dto/CargoLoadingResponse.java`

```java
@Data
public class CargoLoadingResponse {

  // ... существующие поля

  private String address;

  @JsonProperty("apartment")
  private String apartment;  // Квартира / Офис

  private String contactPersonName;

  // ... остальные поля
}
```

---

### 7. DTO для редактирования логистом

**Файл:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/DeliveryPointEditDto.java`

```java
@Data
public class DeliveryPointEditDto {

  // ... существующие поля

  @JsonProperty("address")
  private String address;

  @JsonProperty("apartment")
  @Size(max = 255)
  private String apartment;  // Квартира / Офис

  // ... остальные поля
}
```

---

## 📝 Примеры API запросов

### Импорт от TEEZ

**До:**
```json
{
  "deliveries": [
    {
      "sort": 2,
      "address": "Алматы, мкр. Самал-2, дом 58, кв. 12",
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      }
    }
  ]
}
```

**После:**
```json
{
  "deliveries": [
    {
      "sort": 2,
      "address": "Алматы, мкр. Самал-2, дом 58",
      "apartment": "кв. 12",
      "receiver": {
        "name": "Иванов Иван Иванович",
        "phone": "+77771234567"
      }
    }
  ]
}
```

### Редактирование логистом

**Endpoint:** `PUT /api/v1/courier/waybills/{id}`

```json
{
  "deliveries": [
    {
      "id": 5002,
      "sort": 2,
      "address": "Алматы, пр. Достык 97",
      "apartment": "офис 301",
      "receiver": {
        "name": "Петрова Анна",
        "phone": "+77779876543"
      }
    }
  ]
}
```

### Response для курьера

**Endpoint:** `GET /api/v1/driver/orders/{transportationId}`

```json
{
  "current_route": {
    "points": [
      {
        "id": 5002,
        "order_num": 2,
        "address": "Алматы, мкр. Самал-2, дом 58",
        "apartment": "кв. 12",
        "contact_person_name": "Иванов Иван Иванович",
        "contact_number": "+77771234567"
      }
    ]
  }
}
```

---

## ✅ Чеклист реализации

### Backend (Java)

- [ ] **Миграция БД:** Создать `V2025_12_22_XX__add_apartment_to_cargo_loading.sql`
- [ ] **Entity:** Добавить поле `apartment` в `CargoLoadingHistory.java`
- [ ] **DTO Import:** Добавить поле в `DeliveryPointDto.java` с валидацией
- [ ] **DTO Edit:** Добавить поле в `DeliveryPointEditDto.java`
- [ ] **DTO Response:** Добавить поле в `CargoLoadingResponse.java`
- [ ] **Service Import:** Обновить маппинг в `CourierIntegrationService.createRouteFromWaybill()`
- [ ] **Service Edit:** Обновить маппинг в `CourierWaybillEditService.updateExistingPoint()`
- [ ] **Тестирование:** Проверить импорт с заполненным и пустым значением

### Frontend (Vue.js) - coube-frontend

- [ ] **Типы:** Добавить поле `apartment` в интерфейсы TypeScript
- [ ] **Форма создания:** Добавить поле в форму создания/редактирования точки доставки
- [ ] **Отображение:** Показывать квартиру/офис в деталях маршрута
- [ ] **Валидация:** Ограничение до 255 символов

### Mobile (React Native) - coube-mobile

- [ ] **Типы:** Добавить поле `apartment` в типы TypeScript
- [ ] **Экран деталей:** Отображать квартиру/офис на экране деталей точки доставки
- [ ] **UI:** Выделить это поле визуально (например, иконка 🏢 для офиса, 🏠 для квартиры)

---

## ⏱️ Оценка времени

### Backend: **45 минут**

- Миграция БД: 5 минут
- Backend Entity: 5 минут
- DTO (3 файла): 15 минут
- Маппинг (2 сервиса): 10 минут
- Тестирование: 10 минут

### Frontend: **30 минут**

- Типы TypeScript: 5 минут
- Форма редактирования: 15 минут
- Отображение в списке: 5 минут
- Тестирование: 5 минут

### Mobile: **30 минут**

- Типы TypeScript: 5 минут
- UI компонент: 15 минут
- Отображение: 5 минут
- Тестирование: 5 минут

**Итого: ~1.5 часа** (включая все компоненты системы)

---

## 📌 Примечания

### Отличие от основного адреса

- **address** - основной адрес: "Алматы, мкр. Самал-2, дом 58"
- **apartment** - уточнение: "кв. 12" или "офис 301"

### Зачем отдельное поле?

1. **Структурированность данных:** Легче фильтровать и обрабатывать
2. **Геокодирование:** Основной адрес используется для геокодирования без квартиры
3. **UI/UX:** Можно отображать адрес и квартиру/офис по-разному
4. **Мобильное приложение:** Курьер видит квартиру/офис более заметно

### Примеры значений

✅ **Хорошие примеры:**
- "кв. 12"
- "офис 301"
- "подъезд 2, кв. 45"
- "3 этаж, офис А"
- "домофон 12"

❌ **Не нужно дублировать в основном адресе:**
- ~~"Алматы, мкр. Самал-2, дом 58, кв. 12"~~ → Разделить на address + apartment_office

### Валидация

- Максимальная длина: 255 символов
- Поле необязательное (может быть null или пустой строкой)
- Нет специальной валидации формата (любой текст)

---

## 🔄 Интеграция с существующими API

### 1. POST /api/v1/integration/waybills
- ✅ TEEZ может передавать `apartment` в каждой точке доставки
- ✅ Если поле не передано - сохраняется как null
- ✅ Обратная совместимость: старые запросы без поля продолжат работать

### 2. PUT /api/v1/courier/waybills/{id}
- ✅ Логист может редактировать `apartment` для каждой точки
- ✅ Валидация: максимум 255 символов

### 3. GET /api/v1/driver/orders/{transportationId}
- ✅ Курьер видит `apartment` в деталях каждой точки маршрута
- ✅ Мобильное приложение отображает это поле отдельно от адреса

### 4. GET /api/v1/integration/courier/orders/status
- ⚠️ **Не требуется** - TEEZ не нужно знать квартиру/офис в ответе статусов
- Основной адрес (`delivery_address`) остается как есть

---

## 🧪 Тестовые сценарии

### Сценарий 1: Импорт с квартирой
```bash
POST /api/v1/integration/waybills
{
  "deliveries": [{
    "address": "Алматы, ул. Абая 150",
    "apartment": "кв. 25"
  }]
}
```
**Ожидается:** Сохранено успешно, курьер видит адрес и квартиру отдельно

### Сценарий 2: Импорт с офисом
```bash
POST /api/v1/integration/waybills
{
  "deliveries": [{
    "address": "Алматы, пр. Достык 97",
    "apartment": "офис 301, 3 этаж"
  }]
}
```
**Ожидается:** Сохранено успешно

### Сценарий 3: Импорт без квартиры/офиса
```bash
POST /api/v1/integration/waybills
{
  "deliveries": [{
    "address": "Алматы, ул. Розыбакиева 247"
  }]
}
```
**Ожидается:** Сохранено успешно, `apartment` = null

### Сценарий 4: Редактирование логистом
```bash
PUT /api/v1/courier/waybills/12345
{
  "deliveries": [{
    "id": 5002,
    "address": "Алматы, мкр. Самал-2, дом 58",
    "apartment": "кв. 12, домофон 1234"
  }]
}
```
**Ожидается:** Обновлено успешно

### Сценарий 5: Валидация длины
```bash
PUT /api/v1/courier/waybills/12345
{
  "deliveries": [{
    "apartment": "очень длинная строка..." // > 255 символов
  }]
}
```
**Ожидается:** 400 Bad Request с сообщением о превышении длины

---

## 📱 UI/UX рекомендации

### Веб (coube-frontend)

**Форма редактирования точки:**
```
┌─────────────────────────────────────┐
│ Адрес *                             │
│ ┌─────────────────────────────────┐ │
│ │ Алматы, мкр. Самал-2, дом 58    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Квартира / Офис                     │
│ ┌─────────────────────────────────┐ │
│ │ кв. 12                          │ │
│ └─────────────────────────────────┘ │
│ Макс. 255 символов                  │
└─────────────────────────────────────┘
```

### Мобильное приложение (coube-mobile)

**Карточка точки доставки:**
```
┌────────────────────────────────────┐
│ 📍 Алматы, мкр. Самал-2, дом 58   │
│ 🏠 Квартира 12                     │
│ 👤 Иванов Иван Иванович            │
│ 📞 +7 777 123 45 67                │
└────────────────────────────────────┘
```

---

## 🔗 Связанные задачи

- **Задача 11:** Добавление полей `isSmsRequired` и `isPhotoRequired`
- **Задача 15:** Добавление полей "Общий вес" и "Общий объем"
- **Задача 09:** API редактирования маршрутного листа логистом

---

## 📚 Ссылки на код

### Backend
- `coube-backend/src/main/java/kz/coube/backend/route/entity/CargoLoadingHistory.java`
- `coube-backend/src/main/java/kz/coube/backend/courier/dto/DeliveryPointDto.java`
- `coube-backend/src/main/java/kz/coube/backend/courier/service/CourierIntegrationService.java`

### Frontend
- `coube-frontend/src/types/courier.ts`
- `coube-frontend/src/components/courier/DeliveryPointForm.vue`

### Mobile
- `coube-mobile/src/types/courier.ts`
- `coube-mobile/src/screens/courier/DeliveryPointDetails.tsx`

---

**Дата создания:** 2025-12-22
**Приоритет:** Medium
**Статус:** Ready for Development
**Оценка:** 1.5 часа (Backend + Frontend + Mobile)
**Автор:** Claude Code
