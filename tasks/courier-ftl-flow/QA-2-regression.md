# QA-2 — Регрессионный тест импортного флоу (TEEZ/Kaspi)

**Статус:** 🟡 Важно  
**Оценка:** 3ч  
**Зависит от:** BE-2 (валидация не сломала импорт)

---

## Описание

После всех изменений убедиться что старый импортный флоу работает как прежде. Изменения в BE-2 и BE-4 могут потенциально затронуть импортный флоу.

---

## Чеклист

### Импорт маршрутного листа

- [ ] `POST /api/v1/integration/waybills` с `sourceSystem = 'TEEZ_PVZ'`
- [ ] ✅ Создаётся Transportation с `status = IMPORTED`
- [ ] ✅ `source_system = 'TEEZ_PVZ'`
- [ ] ✅ `external_waybill_id` заполнен
- [ ] ✅ Точки маршрута (`CargoLoadingHistory`) созданы
- [ ] ✅ Заказы в точках (`CourierRouteOrder`) созданы с `trackNumber`

### Валидация и назначение (логист)

- [ ] `POST /api/v1/courier/waybills/{id}/validate` — `IMPORTED → VALIDATED` ✅
- [ ] `POST /api/v1/courier/waybills/{id}/assign` — назначение курьера логистом ✅
- [ ] ✅ Статус `WAITING_DRIVER_CONFIRMATION`

### Исполнение (мобилка)

- [ ] Курьер видит заказ в `MyOrdersScreen`
- [ ] Принимает → `DRIVER_ACCEPTED`
- [ ] Начинает → `ON_THE_WAY`
- [ ] Обновляет статус заказов (`DELIVERED`, `NOT_DELIVERED`)
- [ ] Маршрут завершается → `FINISHED`

### Проверка данных

```bash
# Убедиться что импортные заявки не затронуты
PGPASSWORD='platform.c0ube.kz' psql -h localhost -p 15432 -U coube-usr -d coube-db -c \
  "SELECT id, status, source_system, external_waybill_id 
   FROM applications.transportation 
   WHERE source_system IS NOT NULL 
   ORDER BY created_at DESC LIMIT 10;"
```

- [ ] `source_system` не обнулился у существующих импортных заявок
- [ ] Статусные переходы импортного флоу не изменились
- [ ] Результаты возвращаются во внешнюю систему (если настроен callback)
