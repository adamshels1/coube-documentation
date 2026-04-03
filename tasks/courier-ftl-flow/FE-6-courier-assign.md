# FE-6 — Исправить endpoint в CourierAssignBody для перевозчика

**Статус:** 🔴 Критично  
**Оценка:** 1ч  
**Зависит от:** FE-5  
**Файл:** `coube-frontend/src/components/ModalContent/CourierAssign/CourierAssignBody/CourierAssignBody.vue`

---

## Описание

Существует два endpoint'а для назначения курьера:
- `/api/v1/courier/waybills/{id}/assign` — для **логиста** (импортный флоу, LOGISTICIAN роль)
- `/api/v1/executor/{id}/assign-courier` — для **перевозчика** (FTL-флоу, EXECUTOR роль)

В новом флоу перевозчик должен использовать второй endpoint и назначать **своего** курьера (из сотрудников своей организации).

---

## Чеклист

### Анализ текущего кода

- [ ] Прочитать `CourierAssignBody.vue` — какой endpoint вызывается при сабмите
- [ ] Определить: используется ли один компонент для обоих флоу или разные

### Если один компонент — добавить prop для различия флоу

```typescript
// Добавить prop
const props = defineProps<{
  transportationId: number
  mode: 'executor' | 'logistician' // новый prop
}>()

// Выбор endpoint
const endpoint = computed(() =>
  props.mode === 'executor'
    ? `/api/v1/executor/${props.transportationId}/assign-courier`
    : `/api/v1/courier/waybills/${props.transportationId}/assign`
)
```

### Список курьеров

- [ ] Для режима `executor` — показывать сотрудников организации перевозчика (их собственные водители)
- [ ] Для режима `logistician` — текущее поведение (сотрудники логиста)
- [ ] Убедиться что API для получения списка водителей возвращает нужных сотрудников

### Вызов модала из FE-5

- [ ] В странице деталей перевозчика (статус `SIGNED_CUSTOMER`) кнопка "Назначить курьера" открывает модал с `mode="executor"`

### Проверка

- [ ] Назначение курьера через executor-режим → вызывается `/api/v1/executor/{id}/assign-courier`
- [ ] Назначение курьера через logistician-режим (импортный флоу) → не изменилось, вызывается `/api/v1/courier/waybills/{id}/assign`
- [ ] После назначения транспортировка переходит в `WAITING_DRIVER_CONFIRMATION`
