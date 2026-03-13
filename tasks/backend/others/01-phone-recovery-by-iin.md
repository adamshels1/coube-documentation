# 01. Авторизация по ИИН (альтернатива телефону)

**Дата создания**: 2025-12-18
**Статус**: TO DO
**Приоритет**: HIGH
**Автор**: Ali

---

## 📋 Проблема

**Бизнес-кейс:**
Пользователи забывают свой номер телефона и не могут авторизоваться в системе.

**Текущая ситуация:**
- ✅ Авторизация работает через номер телефона + СМС код
- ❌ Если пользователь забыл номер - доступ к системе невозможен
- ❌ Нет альтернативного способа авторизации

**Решение:**
Добавить авторизацию по ИИН как альтернативу телефону:
1. На странице логина: переключатель "Войти по телефону" / "Войти по ИИН"
2. Пользователь вводит ИИН
3. Система находит телефон по ИИН
4. Отправляет СМС код на этот телефон (автоматически)
5. Пользователь вводит СМС код → авторизован

**Важно:** Сам пользователь не видит свой номер телефона, просто вводит ИИН и получает СМС.

---

## 🎯 Решение

### Архитектура

```
┌─────────────────┐
│  Login Page     │
│  [Телефон|ИИН]  │  <-- Переключатель
└────────┬────────┘
         │
         │ Вариант 1: POST /auth/send-otp (phone)
         │ Вариант 2: POST /auth/send-otp-by-iin (iin)
         ↓
┌─────────────────┐         ┌──────────────┐
│  Backend        │────────>│ WhatsApp SMS │
│  (найти phone)  │  код    │  на телефон  │
└────────┬────────┘         └──────────────┘
         │
         │ success (код отправлен)
         ↓
┌─────────────────┐
│  OTP Page       │
│  (ввод СМС)     │
└────────┬────────┘
         │
         │ POST /auth/verify-otp (phone + code)
         ↓
┌─────────────────┐
│  Authorized     │
└─────────────────┘
```

---

## 🗄️ Изменения в БД

**Не требуется** - используем существующую таблицу `organization.employee` с полем `iin`

### Логика поиска пользователя по ИИН

1. Поиск сотрудника в `employee` по полю `iin`
2. Получить его телефон (`phone`)
3. Отправить СМС код на этот телефон

**Просто:** один ИИН = один человек = один телефон = один СМС код

---

## 🔧 Backend изменения

### 1. DTO: Request для авторизации по ИИН

**File:** `coube-backend/src/main/java/kz/coube/backend/auth/dto/SendOtpByIinRequest.java`

```java
package kz.coube.backend.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class SendOtpByIinRequest {

    @NotBlank(message = "ИИН не может быть пустым")
    @Size(min = 12, max = 12, message = "ИИН должен содержать 12 цифр")
    @Pattern(regexp = "^\\d{12}$", message = "ИИН должен содержать только цифры")
    private String iin;
}
```

---

### 2. DTO: Response (простой)

**File:** `coube-backend/src/main/java/kz/coube/backend/auth/dto/SendOtpResponse.java`

```java
package kz.coube.backend.auth.dto;

import lombok.Builder;

@Builder
public record SendOtpResponse(
    boolean success,
    String message  // "СМС код отправлен"
) {}
```

---

### 3. Service: Простая логика отправки OTP по ИИН

**File:** `coube-backend/src/main/java/kz/coube/backend/auth/service/AuthService.java`

Добавить новый метод в существующий `AuthService`:

```java
/**
 * Отправить OTP код по ИИН (найти телефон по ИИН и отправить СМС)
 */
@Transactional
public SendOtpResponse sendOtpByIin(SendOtpByIinRequest request) {
    String iin = request.getIin();
    log.info("Sending OTP by IIN: {}", maskIin(iin));

    // 1. Найти сотрудника по ИИН
    Employee employee = employeeRepository.findByIin(iin)
        .orElseThrow(() -> {
            log.warn("Employee not found for IIN: {}", maskIin(iin));
            return new ResourceNotFoundException(
                "Пользователь с указанным ИИН не найден"
            );
        });

    // 2. Проверить что у сотрудника есть телефон
    String phone = employee.getPhone();
    if (phone == null || phone.isBlank()) {
        log.warn("Employee has no phone. IIN: {}", maskIin(iin));
        throw new BusinessException(
            "У пользователя не указан номер телефона. Обратитесь в поддержку."
        );
    }

    // 3. Генерация и отправка СМС кода (используем существующий механизм)
    String smsCode = otpDelegate.generate(new OtpId(phone));
    log.info("SMS code generated for IIN: {}. Phone: {}", maskIin(iin), maskPhone(phone));

    // Отправка СМС через WhatsApp
    WhatsAppSendRequest whatsAppRequest = WhatsAppSendRequest.builder()
        .phone(phone)
        .template(WhatsAppTemplate.LOGIN_CODE_MSG)
        .language("ru")
        .bodyParams(List.of(smsCode))
        .buttonParam(smsCode)
        .build();

    whatsAppSenderService.sendTemplate(whatsAppRequest);
    log.info("SMS code sent to phone: {}", maskPhone(phone));

    return SendOtpResponse.builder()
        .success(true)
        .message("СМС код отправлен")
        .build();
}

private String maskIin(String iin) {
    if (iin == null || iin.length() != 12) return "***";
    return iin.substring(0, 6) + "***" + iin.substring(9);
}

private String maskPhone(String phone) {
    if (phone == null || phone.length() < 11) return "***";
    return phone.substring(0, 5) + "***" + phone.substring(phone.length() - 2);
}
```

---

### 4. Repository: Добавить метод поиска по ИИН

**File:** `coube-backend/src/main/java/kz/coube/backend/organization/repository/EmployeeRepository.java`

```java
@Repository
public interface EmployeeRepository extends JpaRepository<Employee, Long> {

    // ... existing methods

    /**
     * Найти сотрудника по ИИН
     */
    Optional<Employee> findByIin(String iin);
}
```

---

### 5. Controller: Добавить endpoint в AuthController

**File:** `coube-backend/src/main/java/kz/coube/backend/auth/api/AuthController.java`

Добавить новый endpoint в существующий `AuthController`:

```java
@PostMapping("/send-otp-by-iin")
@Operation(
    summary = "Отправить OTP код по ИИН",
    description = "Публичный endpoint. Находит телефон по ИИН и отправляет СМС код."
)
public ResponseEntity<SendOtpResponse> sendOtpByIin(
    @Valid @RequestBody SendOtpByIinRequest request
) {
    log.info("Send OTP by IIN request");
    SendOtpResponse response = authService.sendOtpByIin(request);
    return ResponseEntity.ok(response);
}
```

---

### 6. Security: Rate Limiting для защиты от брутфорса

**Важно**: Добавить ограничение на количество попыток с одного IP.

**File:** `coube-backend/src/main/java/kz/coube/backend/config/WebMvcConfig.java`

```java
@Override
public void addInterceptors(InterceptorRegistry registry) {
    registry.addInterceptor(rateLimitInterceptor)
        .addPathPatterns("/api/v1/public/**")
        .addPathPatterns("/api/v1/auth/send-otp-by-iin");  // ⭐ NEW
}
```

**Rate Limit**: 5 попыток в 15 минут на IP адрес

---

## 📊 API Examples

### Request: Отправить OTP по ИИН

```http
POST /api/v1/auth/send-otp-by-iin
Content-Type: application/json

{
  "iin": "123456789012"
}
```

### Response: Успешно (200)

```json
{
  "success": true,
  "message": "СМС код отправлен"
}
```

### Response: Пользователь не найден (404)

```json
{
  "error": "ResourceNotFoundException",
  "message": "Пользователь с указанным ИИН не найден",
  "timestamp": "2025-12-18T10:30:00Z"
}
```

### Response: Нет телефона (400)

```json
{
  "error": "BusinessException",
  "message": "У пользователя не указан номер телефона. Обратитесь в поддержку.",
  "timestamp": "2025-12-18T10:30:00Z"
}
```

### Response: Rate Limit (429)

```json
{
  "error": "TooManyRequests",
  "message": "Слишком много попыток. Попробуйте через 15 минут.",
  "timestamp": "2025-12-18T10:30:00Z"
}
```

---

## 🔄 Флоу авторизации

### После отправки OTP

Дальше пользователь использует **существующий** endpoint для проверки кода:

```http
POST /api/v1/auth/verify-otp
Content-Type: application/json

{
  "phone": "phone_from_iin",  // Frontend НЕ знает phone
  "code": "123456"
}
```

**Проблема**: Frontend не знает phone после ввода ИИН.

**Решение 1** (простое): Backend возвращает phone в response `send-otp-by-iin`:
```json
{
  "success": true,
  "message": "СМС код отправлен",
  "phone": "+77012345678"  // ⭐ добавить
}
```

**Решение 2** (безопаснее): Сохранить ИИН → phone маппинг в сессии/кеше на 5 минут,
создать endpoint `/auth/verify-otp-by-iin`:
```http
POST /api/v1/auth/verify-otp-by-iin
{
  "iin": "123456789012",
  "code": "123456"
}
```
Backend сам найдет phone по ИИН и проверит код.

---

## 🔒 Безопасность

### 1. Rate Limiting
- **Лимит**: 5 попыток в 15 минут на IP адрес
- **Цель**: Защита от брутфорса ИИН

### 2. Маскирование в логах
- **ИИН в логах**: `123456***012` (скрыты 3 цифры посередине)
- **Телефон в логах**: `+7701***67` (скрыты средние цифры)

### 3. Валидация
- ИИН должен содержать ровно 12 цифр
- Проверка формата (только цифры)

---

## 🧪 Testing Checklist

### Unit Tests
- [ ] `AuthService.sendOtpByIin()` - успешная отправка
- [ ] Сотрудник не найден → `ResourceNotFoundException`
- [ ] Сотрудник без телефона → `BusinessException`
- [ ] Валидация ИИН (12 цифр, только цифры)
- [ ] Маскирование в логах работает

### Integration Tests
- [ ] POST `/api/v1/auth/send-otp-by-iin` - успешный запрос
- [ ] POST с невалидным ИИН → 400 Bad Request
- [ ] POST с несуществующим ИИН → 404 Not Found
- [ ] Rate limiting работает (6-й запрос → 429)

### E2E Tests
- [ ] Пользователь вводит ИИН → получает СМС → вводит код → авторизован

---

## 📝 Что нужно сделать

### Backend (5 изменений)

1. ❌ `SendOtpByIinRequest.java` - DTO для запроса
2. ❌ `SendOtpResponse.java` - DTO для ответа (если нет)
3. ❌ `AuthService.sendOtpByIin()` - метод в существующем сервисе
4. ❌ `EmployeeRepository.findByIin()` - метод в репозитории
5. ❌ `AuthController` - добавить endpoint `send-otp-by-iin`
6. ❌ `WebMvcConfig.java` - rate limiting для endpoint

### Решить вопрос с verify-otp

7. ❌ Выбрать решение: возвращать phone или создать `/verify-otp-by-iin`

### Testing

8. ❌ Unit tests для `AuthService.sendOtpByIin()`
9. ❌ Integration tests для endpoint
10. ❌ E2E тестирование полного флоу

---

## ⏱️ Estimated

**Backend**: 3 часа
- DTO и валидация: 30 мин
- Service метод: 1 час
- Controller endpoint: 30 мин
- Rate limiting: 30 мин
- Решение с verify-otp: 30 мин

**Testing**: 1.5 часа

**Итого**: 4.5 часа (полдня)

---

## 📌 Приоритет

**Приоритет**: HIGH - частая проблема пользователей

**Риски**:
- 🔴 **Высокий**: Безопасность (брутфорс ИИН) → обязателен rate limiting
- 🟢 **Низкий**: Технический риск → простая реализация

---

## 🔗 Related Tasks

- **Frontend**: Добавить переключатель "Телефон/ИИН" на странице логина
- **Mobile**: Добавить экран авторизации по ИИН
- **Docs**: Обновить документацию API
