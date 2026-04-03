# Courier FTL Flow — Задачи

Добавление FTL-флоу для курьерской доставки: заказчик создаёт заявку вручную → перевозчик откликается → EDS договор → перевозчик назначает курьера → исполнение.

**Анализ:** [FINAL-ANALYSIS.md](./FINAL-ANALYSIS.md)

---

## Backend

| Файл | ID | Задача | Приоритет | Оценка |
|------|----|--------|-----------|--------|
| [BE-1-notifications.md](./BE-1-notifications.md) | BE-1 | Уведомления для нового флоу | 🔴 | 3ч |
| [BE-2-validation.md](./BE-2-validation.md) | BE-2 | Валидация при ручном создании | 🔴 | 2ч |
| [BE-3-contract-eds.md](./BE-3-contract-eds.md) | BE-3 | Workflow Contract + EDS | 🔴 | 4ч |
| [BE-4-assign-courier.md](./BE-4-assign-courier.md) | BE-4 | Статусные условия assignCourier | 🟡 | 2ч |
| [BE-5-db-indexes.md](./BE-5-db-indexes.md) | BE-5 | Flyway миграция (индексы) | 🟡 | 1ч |
| [BE-6-tests.md](./BE-6-tests.md) | BE-6 | Unit + интеграционные тесты | 🟡 | 4ч |

## Frontend

| Файл | ID | Задача | Приоритет | Оценка |
|------|----|--------|-----------|--------|
| [FE-1-enum.md](./FE-1-enum.md) | FE-1 | COURIER_DELIVERY в enum | 🔴 | 30мин |
| [FE-2-i18n.md](./FE-2-i18n.md) | FE-2 | Словарь + i18n переводы | 🔴 | 1ч |
| [FE-3-create-form.md](./FE-3-create-form.md) | FE-3 | Форма создания (точки маршрута) | 🔴 | 1д |
| [FE-4-list-filter.md](./FE-4-list-filter.md) | FE-4 | Список + фильтр | 🟡 | 3ч |
| [FE-5-details-flow.md](./FE-5-details-flow.md) | FE-5 | Детали: оффер → договор | 🔴 | 4ч |
| [FE-6-courier-assign.md](./FE-6-courier-assign.md) | FE-6 | CourierAssign endpoint | 🔴 | 1ч |

## Mobile

| Файл | ID | Задача | Приоритет | Оценка |
|------|----|--------|-----------|--------|
| [MOB-1-orders-screen.md](./MOB-1-orders-screen.md) | MOB-1 | MyOrdersScreen проверка | 🟡 | 1ч |
| [MOB-2-courier-order-screen.md](./MOB-2-courier-order-screen.md) | MOB-2 | CourierOrderScreen без trackNumber | 🔴 | 2ч |

## QA

| Файл | ID | Задача | Приоритет | Оценка |
|------|----|--------|-----------|--------|
| [QA-1-e2e-test.md](./QA-1-e2e-test.md) | QA-1 | E2E тест нового флоу | 🔴 | 1д |
| [QA-2-regression.md](./QA-2-regression.md) | QA-2 | Регрессия импортного флоу | 🟡 | 3ч |

---

## Порядок выполнения

```
FE-1 → FE-2 ──────────────────────┐
BE-2 → BE-3 → BE-4 ───────────────┤
BE-1, BE-5 (параллельно)           ├──→ FE-3, FE-4, FE-5, FE-6 → MOB-1, MOB-2 → QA-1, QA-2
BE-6 (после BE-2, BE-3, BE-4) ────┘
```
