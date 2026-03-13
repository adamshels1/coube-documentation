# Задача 17: Внутренний эндпоинт обновления маршрутного листа

## Проблема

Сейчас `POST /api/v1/integration/waybills` защищен `CourierApiKeyFilter` и требует заголовок `X-API-Key`. Этот эндпоинт предназначен для внешних систем (TIS/TEEZ).

Когда пользователь редактирует заявку в нашей системе (после того как TIS её импортировал), нам нужно обновить данные. Но вызвать `/api/v1/integration/waybills` с обычным Bearer токеном невозможно.

## Решение

Разрешить вызов того же эндпоинта `/api/v1/integration/waybills` с внутренним токеном авторизации (Bearer).

### Вариант 1: Модифицировать CourierApiKeyFilter

Изменить `CourierApiKeyFilter` чтобы он пропускал запросы с валидным Bearer токеном:

```java
@Override
protected void doFilterInternal(...) {
    String path = request.getRequestURI();
    if (!path.startsWith(INTEGRATION_PATH_PREFIX)) {
        filterChain.doFilter(request, response);
        return;
    }

    String apiKey = request.getHeader(API_KEY_HEADER);
    String authHeader = request.getHeader("Authorization");

    // Если есть Bearer токен - пропускаем, пусть обрабатывает OAuth2
    if (authHeader != null && authHeader.startsWith("Bearer ")) {
        filterChain.doFilter(request, response);
        return;
    }

    // Иначе проверяем API-ключ как раньше
    if (apiKey == null || apiKey.isBlank()) {
        response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "API key is required");
        return;
    }
    // ... остальной код
}
```

### Вариант 2: Создать отдельный эндпоинт (альтернатива)

Создать `PUT /api/v1/courier/waybills/{transportationId}` в `CourierWaybillController` который вызывает тот же `courierIntegrationService.importWaybill()`.

## Рекомендация

**Вариант 1 предпочтительнее** - переиспользует существующую логику upsert в `importWaybill()`.

## Файлы для изменения

- `coube-backend/src/main/java/kz/coube/backend/auth/configuration/CourierApiKeyFilter.java`

## Тестирование

1. Вызвать `POST /api/v1/integration/waybills` с Bearer токеном - должен работать
2. Вызвать с `X-API-Key` - должен работать как раньше
3. Вызвать без авторизации - должен вернуть 401
