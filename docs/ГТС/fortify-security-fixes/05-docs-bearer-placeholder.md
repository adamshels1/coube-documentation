# Задача 5: Bearer токены в документации -> плейсхолдеры

**Приоритет:** High
**Риск поломки:** Нулевой
**Компонент:** coube-backend

## Проблема

В документации API указаны Bearer-токены (даже усечённые `eyJhbGci...`), что Fortify считает захардкоженными учётными данными.

## Затронутый файл

### `coube-backend/docs/routes-contracts-api.md`

**4 места (строки ~39, 115, 183, 245):**

```bash
# БЫЛО:
curl -X GET "http://localhost:8080/api/reports/routes-contracts/analysis?..." \
  -H "Authorization: Bearer eyJhbGci..." \
  -H "X-Organization-Id: 140" \
  -H "Accept: application/json"
```

```bash
# СТАЛО:
curl -X GET "https://platform.coube.kz/api/reports/routes-contracts/analysis?..." \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-Organization-Id: $ORG_ID" \
  -H "Accept: application/json"
```

## Что изменено во всех 4 curl-примерах

1. `eyJhbGci...` -> `$TOKEN` — переменная окружения вместо реального токена
2. `140` -> `$ORG_ID` — параметризация Organization ID
3. `http://localhost:8080` -> `https://platform.coube.kz` — production URL с HTTPS

## Дополнительно

Добавить в начало файла секцию:

```markdown
## Подготовка

Получите токен авторизации:
\`\`\`bash
export TOKEN="ваш_jwt_токен"
export ORG_ID="ваш_organization_id"
\`\`\`
```

## Проверка

- Документация читается корректно
- Примеры curl работают при подстановке реальных значений
