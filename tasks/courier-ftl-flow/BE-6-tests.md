# BE-6 — Unit и интеграционные тесты

**Статус:** 🟡 Важно  
**Оценка:** 4ч  
**Зависит от:** BE-2, BE-3, BE-4

---

## Описание

Написать тесты для нового FTL-флоу курьерской доставки.

---

## Чеклист

### Unit тесты: ExecutorService

- [ ] `assignCourier` — тип не `COURIER_DELIVERY` → `ValidationException`
- [ ] `assignCourier` — статус `SIGNED_CUSTOMER` → переход в `WAITING_DRIVER_CONFIRMATION`
- [ ] `assignCourier` — курьер сохраняется в `transportation.executorEmployee`
- [ ] `assignCourier` — курьер не из организации перевозчика → ошибка
- [ ] `assignCourier` — курьер не активен → ошибка

### Unit тесты: CustomerTransportationService

- [ ] `createCompleteTransportation` с `COURIER_DELIVERY` → `source_system = null`
- [ ] `createCompleteTransportation` с `COURIER_DELIVERY` → начальный статус `FORMING`
- [ ] `createCompleteTransportation` с `COURIER_DELIVERY` → `external_waybill_id = null`
- [ ] Публикация заявки `FORMING → CREATED`

### Unit тесты: OrderNotificationService (BE-1)

- [ ] `notifyCourierTransportationPublished` → отправляет уведомления перевозчикам
- [ ] `notifyCourierAssigned` → отправляет push + SMS курьеру
- [ ] `notifyCourierContractSigned` → отправляет обеим сторонам

### Интеграционный тест: полный флоу

- [ ] Шаг 1: Заказчик создаёт заявку `COURIER_DELIVERY` → статус `CREATED`
- [ ] Шаг 2: Перевозчик видит заявку в `GET /api/v1/executor/transportations`
- [ ] Шаг 3: Перевозчик отправляет counter-offer → статус `WAITING_CUSTOMER_DECISION`
- [ ] Шаг 4: Заказчик принимает цену → создаётся Contract
- [ ] Шаг 5: EDS подпись обеих сторон → статус `SIGNED_CUSTOMER`
- [ ] Шаг 6: Перевозчик назначает курьера → статус `WAITING_DRIVER_CONFIRMATION`
- [ ] Шаг 7: Курьер принимает → статус `DRIVER_ACCEPTED`
- [ ] Шаг 8: Курьер начинает → статус `ON_THE_WAY`
- [ ] Шаг 9: Маршрут завершён → статус `FINISHED`
- [ ] Шаг 10: Invoice + Act созданы

### Регрессионный тест: импортный флоу не сломан

- [ ] Импорт маршрута с `source_system = 'TEEZ_PVZ'` → статус `IMPORTED`
- [ ] `IMPORTED → VALIDATED` работает
- [ ] `assignCourier` для импортного маршрута (статус `VALIDATED`) → `WAITING_DRIVER_CONFIRMATION`
