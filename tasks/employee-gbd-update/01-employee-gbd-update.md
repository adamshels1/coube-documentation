# Обновление данных сотрудника через ГБД (GBD Integration)

**Дата создания**: 2026-03-30
**Статус**: TO DO
**Приоритет**: MEDIUM
**Автор**: Ali

---

## Проблема

**Бизнес-кейс:**
Администратор/CEO организации должен иметь возможность обновить данные сотрудника (ФИО, данные удостоверения личности) из Государственной базы данных физических лиц (ГБД ФЛ) — не чаще одного раза в 30 дней.

**Текущая ситуация:**
- ✅ Кнопка "Обновить данные" на странице `/employees/:id` существует
- ✅ Endpoint `POST /api/v1/employee-data/update` создан, rate limiting (30 дней) работает
- ✅ Структура кода для обновления полей сотрудника из ГБД написана, но закомментирована
- ❌ Реального запроса в ГБД нет — метод `updateEmployeeFromGbdData()` является заглушкой
- ❌ ГБД для физлиц требует SMS-согласие (двухшаговый процесс), что не реализовано
- ❌ При нажатии кнопки данные в UI не обновляются реально — только записывается `"dataUpdateAttempted"`
- ❌ Если ГБД недоступен или возвращает ошибку — пользователь видит "успех" (ошибки проглатываются)

---

## Как работает ГБД для физлиц

В отличие от юрлиц (организаций), запрос данных физлица требует **SMS-согласие** от самого человека:

```
Шаг 1: Запрос согласия
  POST /api/v1/gbd/sms-consent  { iin: "..." }
  → ГБД отправляет SMS на телефон физлица
  → Возвращает requestId

Шаг 2: Ввод кода
  Пользователь (сотрудник) получает SMS и сообщает код администратору
  ИЛИ администратор просит сотрудника подтвердить самостоятельно

Шаг 3: Получение данных
  POST /api/v1/gbd/person-data  { iin: "...", requestId: "...", smsCode: "..." }
  → ГБД возвращает ФИО, данные удостоверения
```

**Важно:** SMS-согласие действует ограниченное время (~15 минут). Если пользователь не ввёл код — процесс нужно начинать заново.

---

## Архитектура решения

```
┌─────────────────────────────────────────────────────────────┐
│  Frontend (страница /employees/:id)                          │
│                                                             │
│  1. Нажать "Обновить данные"                                │
│     → POST /employee-data/request-consent { iin }          │
│     → Показать модалку "Введите SMS-код"                    │
│                                                             │
│  2. Ввести SMS-код в модалку → "Подтвердить"                │
│     → POST /employee-data/update { iin, requestId, code }  │
│     → Закрыть модалку                                       │
│     → Перезагрузить данные сотрудника (getById)             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Backend                                                    │
│                                                             │
│  POST /employee-data/request-consent                        │
│    → Проверить принадлежность к организации                 │
│    → gbdService.requestSmsConsent(iin)                      │
│    → Вернуть { requestId }                                  │
│                                                             │
│  POST /employee-data/update                                 │
│    → Проверить rate limit (30 дней)                         │
│    → gbdService.getPersonData(iin, requestId)               │
│    → Обновить поля Employee                                 │
│    → Сохранить lastBmgUpdateDate                            │
│    → Вернуть { updatedFields, message }                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Поля которые обновляются из ГБД

| Поле в `Employee` | Поле в ГБД `PersonDataResponse` | Описание |
|---|---|---|
| `firstName` | `personData.name` | Имя |
| `lastName` | `personData.surname` | Фамилия |
| `middleName` | `personData.patronymic` | Отчество |
| `idDocumentNumber` | `documents.document[type=ID_CARD].number` | Номер удостоверения |
| `idDocumentIssuedAt` | `documents.document[type=ID_CARD].beginDate` | Дата выдачи |
| `idDocumentValidUntil` | `documents.document[type=ID_CARD].endDate` | Дата истечения |

---

## Backend изменения

### 1. Новый DTO: `RequestEmployeeConsentRequest`

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/dto/RequestEmployeeConsentRequest.java`

```java
public record RequestEmployeeConsentRequest(String iin) {}
```

### 2. Новый DTO: `RequestEmployeeConsentResponse`

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/dto/RequestEmployeeConsentResponse.java`

```java
public record RequestEmployeeConsentResponse(
    String requestId,
    String message
) {}
```

### 3. Обновить `UpdateEmployeeDataRequest`

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/dto/UpdateEmployeeDataRequest.java`

Добавить поля `requestId` и `smsCode` — они нужны для второго шага:

```java
public record UpdateEmployeeDataRequest(
    String iin,
    String requestId,  // из шага 1
    String smsCode     // код из SMS (передаётся в ГБД)
) {}
```

### 4. Новый endpoint в `EmployeeDataUpdateController`

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/api/EmployeeDataUpdateController.java`

```java
@PostMapping("/request-consent")
public ResponseEntity<RequestEmployeeConsentResponse> requestConsent(
        @Valid @RequestBody RequestEmployeeConsentRequest request) {
    // Проверить принадлежность сотрудника к организации
    // Вызвать gbdService.requestSmsConsent(request.iin())
    // Вернуть requestId
}
```

### 5. Реализовать `updateEmployeeFromGbdData()` в сервисе

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/service/EmployeeDataUpdateService.java`

Раскомментировать и доработать код. Добавить параметры `requestId` и `smsCode`:

```java
private List<String> updateEmployeeFromGbdData(Employee employee, String requestId) {
    // Убрать try/catch который проглатывает ошибки — пробрасывать исключения наверх
    PersonDataResponse personData = gbdService.getPersonData(employee.getIin(), requestId);

    // Обновить поля (код уже написан в закомментированном блоке)
    // ...

    return updatedFields;
}
```

**Важно:** убрать `catch (Exception e) { log.error(...); }` который проглатывает ошибки. Если ГБД недоступен — исключение должно дойти до контроллера и пользователь увидит ошибку.

### 6. Обновить метод `updateEmployeeData()` в сервисе

Принять `requestId` из запроса и передать в `updateEmployeeFromGbdData()`.

---

## Frontend изменения

### 1. Обновить API

**File:** `coube-frontend/src/api/employee.ts`

Добавить метод для запроса SMS-согласия:
```typescript
requestGbdConsent: (iin: string) =>
  request('post', 'v1/employee-data/request-consent', { body: { iin } }),
```

Обновить `updateFromBmg` — принять `requestId`:
```typescript
updateFromBmg: (iin: string, requestId: string) =>
  request('post', 'v1/employee-data/update', { body: { iin, requestId } }),
```

### 2. Модалка SMS-кода

**File:** `coube-frontend/src/views/Employees/EmployeeEdit/EmployeeEditPage.vue`

Новый флоу кнопки "Обновить данные":

```
Нажать кнопку
  → isRequestingConsent = true
  → POST /employee-data/request-consent { iin }
  → Сохранить requestId
  → Показать модалку с полем ввода SMS-кода

В модалке ввести код → "Подтвердить"
  → isUpdating = true
  → POST /employee-data/update { iin, requestId }
  → Закрыть модалку
  → employeeStore.getById(id)  // перезагрузить данные
  → toast.success(...)

Ошибка (ГБД недоступен, код неверный, таймаут)
  → toast.error(message из сервера)
```

**Компонент модалки:**
- Заголовок: "Подтверждение обновления данных"
- Текст: "На номер телефона сотрудника отправлен SMS-код. Попросите сотрудника сообщить вам код и введите его ниже."
- Поле ввода: 6 символов
- Кнопки: "Отмена" / "Подтвердить"
- Таймер обратного отсчёта 15 мин (время действия согласия)

### 3. Обработка ошибок

Добавить в exclusion list в `utils.ts`:
```typescript
const isEmployeeConsentRequest = error.config?.url?.includes('/employee-data/request-consent');
```

---

## Состояния кнопки

| Состояние | Вид кнопки |
|---|---|
| Обычное | Зелёная, активная |
| Запрос SMS (шаг 1) | Disabled + loading spinner |
| Ожидание ввода кода | Обычная (модалка открыта) |
| Отправка данных (шаг 2) | Disabled + loading spinner |
| Rate limit (30 дней) | Серая, disabled, tooltip с датой |

---

## Сценарии ошибок

| Сценарий | Что показать пользователю |
|---|---|
| ГБД недоступен при запросе согласия | "Сервис временно недоступен. Попробуйте позже" |
| ИИН не найден в ГБД | "Физлицо с данным ИИН не найдено в ГБД" |
| SMS не отправлен | "Не удалось отправить SMS. Проверьте телефон сотрудника" |
| Неверный SMS-код | "Неверный код. Попробуйте ещё раз" |
| SMS-код истёк (>15 мин) | "Срок действия кода истёк. Запросите новый" |
| Rate limit | "Данные можно обновлять раз в 30 дней. Следующее обновление: {дата}" |

---

## Текущее состояние кода

### Что уже сделано (не трогать):
- `POST /api/v1/employee-data/update` — endpoint существует
- Rate limiting (30 дней) через `lastBmgUpdateDate` — работает
- Структура обновления полей из ГБД — закомментирована в `updateEmployeeFromGbdData()`
- `GbdService.requestSmsConsent()` и `GbdService.getPersonData()` — реализованы
- `ConsentCacheStore` — кэш для хранения requestId, уже работает

### Что нужно сделать:
- Добавить endpoint `POST /request-consent`
- Раскомментировать и доработать `updateEmployeeFromGbdData()`
- Убрать проглатывание ошибок в catch-блоке
- Обновить `UpdateEmployeeDataRequest` (добавить `requestId`)
- Добавить модалку SMS-кода на фронтенде

---

## Что нужно сделать

### Backend
1. [ ] Создать `RequestEmployeeConsentRequest` / `RequestEmployeeConsentResponse` DTO
2. [ ] Добавить `requestId` в `UpdateEmployeeDataRequest`
3. [ ] Добавить endpoint `POST /api/v1/employee-data/request-consent` в контроллер
4. [ ] Раскомментировать код обновления полей в `updateEmployeeFromGbdData()`
5. [ ] Убрать проглатывание ошибок — пробрасывать исключения наверх
6. [ ] Передавать `requestId` из запроса в `updateEmployeeFromGbdData()`

### Frontend
7. [ ] Добавить `requestGbdConsent` в `api/employee.ts`
8. [ ] Создать модалку ввода SMS-кода
9. [ ] Переписать `updateData()` на двухшаговый флоу
10. [ ] Добавить таймер 15 мин в модалке
11. [ ] Обработать все сценарии ошибок
12. [ ] Добавить `/employee-data/request-consent` в exclusion list `utils.ts`

### Testing
13. [ ] Проверить успешный флоу (шаг 1 → SMS → шаг 2 → данные обновились в UI)
14. [ ] Проверить ошибку при недоступном ГБД
15. [ ] Проверить неверный SMS-код
16. [ ] Проверить истечение кода (>15 мин)
17. [ ] Проверить rate limit (второе нажатие в течение 30 дней)
18. [ ] Проверить что обновлённые поля отображаются в UI сразу после обновления
