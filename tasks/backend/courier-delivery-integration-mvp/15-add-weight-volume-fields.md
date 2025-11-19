# Задача 15: Добавить поля "Общий вес" и "Общий объем"

## 🎯 Цель

Добавить поля для веса и объема в API импорта маршрутных листов от TEEZ.

## 📋 Описание

В дизайне Figma присутствуют поля "Общий вес (кг)" и "Общий объем (м³)" на уровне точки маршрута, которых нет в текущей API спецификации.

Нужно добавить эти поля в метод `POST /api/v1/integration/waybills` (импорт маршрутного листа).

---

## 🔧 Изменения

### 1. API Request (добавить 2 поля)

В структуре `deliveries[]` добавить:

```json
{
  "deliveries": [
    {
      "sort": 1,
      "address": "...",
      // ... существующие поля

      // НОВЫЕ ПОЛЯ:
      "total_weight_kg": 15.5,    // Общий вес в килограммах (необязательное)
      "total_volume_m3": 0.25     // Общий объем в кубометрах (необязательное)
    }
  ]
}
```

**Типы данных:**
- `total_weight_kg`: `Double` (может быть null)
- `total_volume_m3`: `Double` (может быть null)

**Обязательность:** НЕ обязательные поля (optional)

---

### 2. Database Migration

**Файл:** `V2025_XX_XX_XX__add_weight_volume_to_cargo_loading.sql`

```sql
-- Добавляем поля веса и объема в точки маршрута
ALTER TABLE gis.cargo_loading_history
ADD COLUMN IF NOT EXISTS total_weight_kg NUMERIC(10, 2),
ADD COLUMN IF NOT EXISTS total_volume_m3 NUMERIC(10, 3);

-- Комментарии
COMMENT ON COLUMN gis.cargo_loading_history.total_weight_kg
  IS 'Общий вес груза в точке (кг) для курьерской доставки';

COMMENT ON COLUMN gis.cargo_loading_history.total_volume_m3
  IS 'Общий объем груза в точке (м³) для курьерской доставки';
```

---

### 3. Backend Entity

**Файл:** `CargoLoadingHistory.java`

```java
@Entity
@Table(name = "cargo_loading_history", schema = "gis")
public class CargoLoadingHistory extends BaseIdEntity {

  // ... существующие поля

  // Новые поля для курьерской доставки
  @Column(name = "total_weight_kg")
  private Double totalWeightKg;

  @Column(name = "total_volume_m3")
  private Double totalVolumeM3;
}
```

---

### 4. DTO для импорта

**Файл:** `DeliveryPointDto.java` (или как называется DTO для точки)

```java
public class DeliveryPointDto {

  // ... существующие поля

  private Double totalWeightKg;  // Общий вес (кг)
  private Double totalVolumeM3;  // Общий объем (м³)
}
```

---

### 5. Маппер

В сервисе `CourierIntegrationService.createRouteFromWaybill()` добавить:

```java
// Добавить при создании CargoLoadingHistory из DeliveryPoint
clh.setTotalWeightKg(point.getTotalWeightKg());
clh.setTotalVolumeM3(point.getTotalVolumeM3());
```

---

### 6. API Response

В `CargoLoadingResponse.java` добавить:

```java
public class CargoLoadingResponse {

  // ... существующие поля

  private Double totalWeightKg;
  private Double totalVolumeM3;
}
```

---

## 📝 Пример API запроса

**До:**
```json
{
  "deliveries": [
    {
      "sort": 1,
      "address": "Алматы, ул. Абая 150",
      "is_sms_required": true,
      "is_photo_required": false
    }
  ]
}
```

**После:**
```json
{
  "deliveries": [
    {
      "sort": 1,
      "address": "Алматы, ул. Абая 150",
      "is_sms_required": true,
      "is_photo_required": false,
      "total_weight_kg": 15.5,
      "total_volume_m3": 0.25
    }
  ]
}
```

---

## ✅ Чеклист реализации

- [ ] Миграция БД: добавить 2 колонки в `cargo_loading_history`
- [ ] Entity: добавить поля в `CargoLoadingHistory.java`
- [ ] DTO: добавить поля в `DeliveryPointDto.java`
- [ ] Service: обновить маппинг в `CourierIntegrationService`
- [ ] Response: добавить поля в `CargoLoadingResponse.java`
- [ ] Тестирование: проверить импорт с заполненными и пустыми значениями

---

## ⏱️ Оценка времени

**30 минут** - простое добавление 2 полей

- Миграция БД: 5 минут
- Backend Entity + DTO: 10 минут
- Маппинг: 5 минут
- Тестирование: 10 минут

---

## 📌 Примечания

- Поля **необязательные** (могут быть null)
- Если TEEZ не передает - поля остаются пустыми
- В будущем можно добавить автоматический расчет суммы весов всех заказов в точке

---

**Дата создания:** 2025-11-19
**Приоритет:** Medium
**Статус:** Ожидает подтверждения от TEEZ
