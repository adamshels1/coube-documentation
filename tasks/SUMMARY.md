# Сводная таблица задач

## Фича 1: НДС в заявках

### Backend (7 задач)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-VAT-BE-1 | Миграция БД: добавить VAT поля в `transportation` | 🔴 | — |
| TASK-VAT-BE-2 | Enum `VatMode` + обновить `Transportation` entity | 🔴 | BE-1 |
| TASK-VAT-BE-3 | Обновить DTO: принимать `vatEnabled, vatMode, inputAmount` | 🔴 | BE-2 |
| TASK-VAT-BE-4 | `VatCalculationService`: логика ADD/EXTRACT + формулы | 🔴 | BE-3 |
| TASK-VAT-BE-5 | `InvoiceService`: суммировать VAT из Transportation | 🔴 | BE-4 |
| TASK-VAT-BE-6 | Обновить генерацию Excel/PDF документов | 🟡 | BE-5 |
| TASK-VAT-BE-7 | Endpoint `POST /vat/calculate` для real-time preview | 🟢 | BE-4 |

### Frontend (5 задач)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-VAT-FE-1 | Компонент `VatCalculator.vue` + composable `useVatCalculation` | 🔴 | — |
| TASK-VAT-FE-2 | Интеграция `VatCalculator` в форму создания заявки | 🔴 | FE-1, BE-3 |
| TASK-VAT-FE-3 | Отображение VAT разбивки в деталях заявки | 🔴 | BE-2 |
| TASK-VAT-FE-4 | Отображение VAT в финансовых документах (Invoice, Act) | 🔴 | BE-5 |
| TASK-VAT-FE-5 | i18n переводы для VAT блока | 🟡 | FE-1 |

### Mobile (3 задачи)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-VAT-MOB-1 | Компонент `VatCalculatorMobile` в форму заявки | 🔴 | BE-3 |
| TASK-VAT-MOB-2 | Отображение VAT разбивки в деталях заявки | 🔴 | BE-2 |
| TASK-VAT-MOB-3 | Отображение VAT в финансовых документах | 🟡 | BE-5 |

---

## Фича 2: Интеграция ИС ЭСФ

> ⚠️ **Предварительно:** зарегистрироваться как интеграционный клиент КГД
> 📧 esfsd@kgd.minfin.gov.kz | ☎ +7 (7172) 72-51-61

### Backend (8 задач)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-ESF-BE-1 | Установить ESF SDK v4.0.0 в gradle | 🔴 | Регистрация в КГД |
| TASK-ESF-BE-2 | Миграция БД: таблица `esf_documents` | 🔴 | VAT-BE-1 |
| TASK-ESF-BE-3 | Entity `EsfDocument` + Repository | 🔴 | ESF-BE-2 |
| TASK-ESF-BE-4 | `EsfSessionService`: открытие/закрытие сессии через Kalkan | 🔴 | ESF-BE-1 |
| TASK-ESF-BE-5 | `InvoiceToEsfMapper`: Invoice → ESF XML | 🔴 | ESF-BE-4, VAT-BE-5 |
| TASK-ESF-BE-6 | `EsfSendingService`: полный цикл отправки | 🔴 | ESF-BE-3,4,5 |
| TASK-ESF-BE-7 | REST endpoints: send/status/cancel | 🔴 | ESF-BE-6 |
| TASK-ESF-BE-8 | Scheduler: фоновая синхронизация статусов | 🟡 | ESF-BE-6 |

### Frontend (5 задач)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-ESF-FE-1 | API методы: `sendEsf, getEsfStatus, cancelEsf` | 🔴 | ESF-BE-7 |
| TASK-ESF-FE-2 | Компонент `EsfStatusBadge.vue` | 🔴 | ESF-FE-1 |
| TASK-ESF-FE-3 | ESF блок в деталях счёта: кнопки + статус | 🔴 | ESF-FE-1,2 |
| TASK-ESF-FE-4 | ESF статус в списке счетов | 🟡 | ESF-FE-2 |
| TASK-ESF-FE-5 | i18n переводы для ESF блока | 🟡 | ESF-FE-2 |

### Mobile (2 задачи)

| ID | Задача | Приоритет | Зависит от |
|----|--------|-----------|-----------|
| TASK-ESF-MOB-1 | Отображение ESF статуса в деталях счёта | 🟡 | ESF-BE-7 |
| TASK-ESF-MOB-2 | Push-уведомления при изменении статуса ЭСФ | 🟢 | ESF-BE-8 |

---

## Порядок реализации (рекомендуемый)

```
Спринт 1 — НДС Backend:
  TASK-VAT-BE-1 → BE-2 → BE-3 → BE-4 → BE-5

Спринт 1 — НДС Frontend + Mobile (параллельно):
  TASK-VAT-FE-1 → FE-2 → FE-3 → FE-4
  TASK-VAT-MOB-1 → MOB-2 → MOB-3

Спринт 2 — ИС ЭСФ Backend:
  TASK-ESF-BE-1 → BE-2 → BE-3 → BE-4 → BE-5 → BE-6 → BE-7

Спринт 2 — ИС ЭСФ Frontend + Mobile (параллельно):
  TASK-ESF-FE-1 → FE-2 → FE-3
  TASK-ESF-MOB-1

Спринт 3 — Доработки:
  VAT-BE-6, VAT-BE-7, ESF-BE-8, ESF-FE-4,5, ESF-MOB-2
```

---

## Итого задач

| Платформа | НДС | ИС ЭСФ | Всего |
|-----------|-----|--------|-------|
| Backend | 7 | 8 | **15** |
| Frontend | 5 | 5 | **10** |
| Mobile | 3 | 2 | **5** |
| **Итого** | **15** | **15** | **30** |
