# BE-5 — Flyway миграция: индексы БД

**Статус:** 🟡 Важно  
**Оценка:** 1ч  
**Путь:** `coube-documentation/migration-db/`

---

## Описание

Добавить индексы для оптимизации запросов при работе с курьерскими маршрутами. Особенно важно для маршрутов с 50+ точками.

---

## Чеклист

### Создать файл миграции

- [ ] Имя файла: `V{timestamp}__add_courier_ftl_indexes.sql`
- [ ] Timestamp берём в формате `YYYYMMDDHHMMSS`

### SQL индексы

```sql
-- Фильтрация по типу и статусу (основной запрос executor журнала)
CREATE INDEX IF NOT EXISTS idx_transportation_type_status
  ON applications.transportation(transportation_type, status);

-- Фильтрация точек маршрута (исключение удалённых точек action=DELETED)
CREATE INDEX IF NOT EXISTS idx_cargo_loading_route_action
  ON gis.cargo_loading_history(route_history_id, action);

-- Сортировка точек по порядку в маршруте
CREATE INDEX IF NOT EXISTS idx_cargo_loading_order_num
  ON gis.cargo_loading_history(route_history_id, order_num);
```

- [ ] Написать SQL с `IF NOT EXISTS` (идемпотентно)
- [ ] Проверить что схемы (`applications`, `gis`) указаны верно
- [ ] Запустить `./gradlew flywayMigrate` и убедиться что миграция применяется без ошибок

### Дополнительно (если нет)

- [ ] Проверить наличие индекса на `transportation.organization_id` (для фильтрации заявок заказчика)
- [ ] Проверить наличие индекса на `courier_route_order.cargo_loading_history_id`
