# Задачи для бэкенда - Отчеты перевозчика

## 📋 Обзор
В этой папке находятся конкретные задачи для бэкенда по реализации отчетов перевозчика. Каждая задача включает полные спецификации API с URL, параметрами и примерами response.

## 🎯 Приоритеты выполнения

### **Фаза 1: Критически важная функциональность**
1. **`05-security-config.md`** - Конфигурация безопасности (ОБЯЗАТЕЛЬНО ПЕРВОЙ)
2. **`06-excel-export-service.md`** - Универсальный сервис экспорта в Excel
3. **`01-avr-insurance-controller.md`** - АВР и страховые полисы

### **Фаза 2: Аналитические отчеты**
4. **`02-vehicle-utilization-service.md`** - Утилизация ТС
5. **`03-routes-period-analysis.md`** - Анализ рейсов за период

### **Фаза 3: Фьючерс-функционал**
6. **`04-disputes-claims-structure.md`** - Структура для споров и претензий

## 📊 **СПЕЦИФИКАЦИИ API (полные как у заказчика):**

### **1. АВР и страховые полисы (`01-avr-insurance-controller.md`)**
- `GET /api/reports/executor/avr-insurance` - Основные данные
- `GET /api/reports/executor/avr-insurance/export` - Экспорт в Excel
- `GET /api/reports/executor/avr-insurance/{routeId}/documents` - Документы по рейсу

### **2. Утилизация ТС (`02-vehicle-utilization-service.md`)**
- `GET /api/reports/executor/vehicle-utilization` - Данные по загрузке ТС
- `GET /api/reports/executor/vehicle-utilization/export` - Экспорт в Excel
- `GET /api/reports/executor/vehicle-utilization/timeline` - Динамика по времени

### **3. Анализ рейсов (`03-routes-period-analysis.md`)**
- `GET /api/reports/executor/routes-period` - Данные по рейсам за период
- `GET /api/reports/executor/routes-period/export` - Экспорт в Excel
- `GET /api/reports/executor/routes-period/analytics` - Аналитика с группировками

### **4. Споры и претензии (`04-disputes-claims-structure.md`)**
- `GET /api/reports/executor/disputes-claims` - Данные по спорам
- `GET /api/reports/executor/disputes-claims/export` - Экспорт в Excel
- `GET /api/reports/executor/disputes-claims/kanban` - Kanban доска

## ✅ Что уже готово (не трогать):
- `ExecutorApplicationRegistryReportService` (адаптация `ApplicationRegistryReportService`)
- `ExecutorFinancialReportService` (адаптация `FinancialPaymentReportService`)
- `ExecutorSLAPerformanceReportService` (адаптация `SLAPerformanceReportService`)
- `ExecutorDriverComparisonReportService` (адаптация `ExecutorComparisonReportService`)
- `ExecutorGeoAnalyticsReportService` (адаптация `GeoAnalyticsReportService`)
- `ExecutorSignatureLogsReportService` (адаптация `SignatureLogsReportService`)
- `ExecutorPlatformCommissionReportService` (адаптация `PlatformCommissionReportService`)
- `ExecutorNotificationLogsReportService` (адаптация `NotificationLogsReportService`)
- `ExecutorContractsAnalysisReportService` (адаптация `RoutesContractsReportService`)
- `ExecutorDebtorReportService` (адаптация `DebtorAnalysisReportService`)

## 🔗 Связанные файлы
- Основные ТЗ: `../../Отчеты для Перевозчика_2.md`
- Архитектура БД: `../../../database-architecture/database-architecture-auto-generated.md`
- Примеры задач заказчика: `../customer/`

## 📊 Статистика разработки
- **Всего задач:** 6
- **Новых сервисов:** 4
- **Конфигурация:** 2
- **Ожидаемый срок:** 2-3 недели

## 🚀 Порядок выполнения:
1. Настроить безопасность
2. Создать универсальный экспорт
3. Реализовать новые отчеты
4. Добавить структуру для будущих функций

---
*Важно: Все задачи должны включать валидацию, кэширование, обработку ошибок и тесты.*