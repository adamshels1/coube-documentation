# BE-1 — Уведомления для нового курьерского FTL-флоу

**Статус:** 🔴 Критично  
**Оценка:** 3ч  
**Файл:** `coube-backend/src/main/java/kz/coube/backend/notifications/service/OrderNotificationService.java`

---

## Описание

Добавить события уведомлений для ручного FTL-флоу курьерской доставки. Текущая система уведомлений покрывает только FTL перевозки. Для нового флоу нужны свои события.

---

## Чеклист

### Новые методы в OrderNotificationService

- [ ] `notifyCourierTransportationPublished(Transportation t)` — публикация курьерской заявки → push/SMS всем активным перевозчикам
- [ ] `notifyExecutorCourierResponse(Transportation t, Organization executor)` — перевозчик откликнулся → заказчику
- [ ] `notifyCourierContractSigned(Transportation t)` — договор подписан обеими сторонами → обеим сторонам
- [ ] `notifyCourierAssigned(Transportation t, Employee courier)` — курьер назначен → курьеру (push + SMS)
- [ ] `notifyCourierAcceptedOrder(Transportation t, Employee courier)` — курьер принял → заказчику и перевозчику

### Тригеры событий

- [ ] В `CustomerTransportationService` при переходе в статус `CREATED` → вызвать `notifyCourierTransportationPublished`
- [ ] В `ExecutorService.saveCounterOfferPrice` при `COURIER_DELIVERY` → вызвать `notifyExecutorCourierResponse`
- [ ] В `AgreementService` / `ContractService` при финальной подписи → вызвать `notifyCourierContractSigned`
- [ ] В `ExecutorService.assignCourier` → вызвать `notifyCourierAssigned`
- [ ] В `DriverService.acceptOrder` при `COURIER_DELIVERY` → вызвать `notifyCourierAcceptedOrder`

### Каналы доставки

- [ ] Push-уведомление (Firebase) — для мобильных пользователей
- [ ] SMS — для ключевых событий (назначение курьера, подписание договора)
- [ ] In-app уведомление — для всех событий

### Тесты

- [ ] Unit тест для каждого нового метода
- [ ] Проверить что старые уведомления FTL не затронуты
