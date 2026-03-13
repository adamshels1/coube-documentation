# Задача 3: Убрать пароль из комментария

**Приоритет:** Low
**Риск поломки:** Нулевой
**Компонент:** coube-backend

## Проблема

В `KeycloakUserService.java` строка 34 содержит захардкоженный пароль `"password"` с TODO-комментарием.

## Затронутый файл

### `coube-backend/src/main/java/kz/coube/backend/auth/keycloak/service/KeycloakUserService.java`

**Строка 34:**
```java
// БЫЛО:
.credentials(List.of(Credential.fromPassword("password"))) // TODO: mock otp password
```

**СТАЛО:**
```java
.credentials(List.of(Credential.fromPassword(generateTemporaryPassword())))
```

**Добавить метод в класс:**
```java
private String generateTemporaryPassword() {
    return java.util.UUID.randomUUID().toString();
}
```

## Пояснение

- Текущий код создаёт ВСЕХ пользователей с паролем `"password"` — это уязвимость
- UUID-пароль будет уникальным и случайным для каждого пользователя
- Пользователь в любом случае аутентифицируется через OTP (SMS), поэтому пароль Keycloak — формальность
- Комментарий `// TODO: mock otp password` тоже удаляется

## Проверка

- `./gradlew test` — тесты проходят
- Регистрация нового пользователя через приложение работает
- Вход через OTP работает
