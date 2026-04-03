# MOB-2 — Проверить CourierOrderScreen при source_system=null

**Статус:** 🔴 Критично  
**Оценка:** 2ч  
**Файл:** `coube-mobile/src/screens/CourierOrderScreen/CourierOrderScreen.tsx`

---

## Описание

В импортном флоу у каждого заказа в точке есть `trackNumber` и `externalId` из внешней системы (TEEZ, Kaspi). В новом FTL-флоу заказчик создаёт точки вручную — `trackNumber` и `externalId` будут `null` или отсутствовать.

Нужно убедиться что экран не ломается и корректно работает без этих полей.

---

## Чеклист

### Анализ типов данных

- [ ] Найти в `api/types.ts` интерфейс `CourierOrder`
- [ ] Поля `trackNumber` и `externalId` — сделать опциональными (`trackNumber?: string`)
- [ ] Аналогично в других интерфейсах где эти поля используются

### Проверка рендера CourierOrderScreen

- [ ] Отображение трек-номера — если `null`, показывать прочерк или скрыть поле
- [ ] Список заказов в точке — корректно рендерится без `externalId`
- [ ] Кнопки действий (delivered, not_delivered) работают без `trackNumber`

### Статусные действия

- [ ] `PUT /api/v1/courier/orders/{transportationId}/courier-orders/{orderId}/status` — работает без `externalId` в payload
- [ ] SMS подтверждение (`sendCourierDeliverySms`) — не зависит от `trackNumber`
- [ ] Загрузка фото (`uploadCourierPhoto`) — не зависит от `externalId`

### Позиции заказа (positions JSONB)

- [ ] В новом флоу `positions` может быть пустым массивом или `null`
- [ ] Экран не ломается при пустых positions
- [ ] Если positions пустые — показывать заглушку или скрывать блок

### Проверка

- [ ] Открыть `CourierOrderScreen` с тестовым заказом у которого `trackNumber=null`
- [ ] Все действия (arrival, departure, delivered) работают
- [ ] Нет краша и нет ошибок в консоли React Native
