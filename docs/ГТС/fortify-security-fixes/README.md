# Fortify Security Audit - План исправления уязвимостей

**Дата аудита:** 16 февраля 2026
**Инструмент:** Fortify SCA v25.4.0.0135
**Проект:** 1scan_coube
**Файлов:** 4,104 | **Строк кода:** 331,201

## Сводка

| Приоритет | Всего | Можно фиксить безопасно | Требует осторожности | False positive / Не трогать |
|-----------|-------|------------------------|---------------------|---------------------------|
| Critical  | 18    | 11                     | 5                   | 2                         |
| High      | 20    | 8                      | 7                   | 5                         |
| Medium    | 1     | 1                      | 0                   | 0                         |
| Low       | 142   | 140                    | 0                   | 2                         |
| **Итого** | **181** | **160**              | **12**              | **9**                     |

## Структура задач

| # | Задача | Приоритет | Риск поломки | Компонент |
|---|--------|-----------|-------------|-----------|
| 1 | [Убрать console.log с приватными данными](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/01-remove-console-logs.md) | Critical | Нулевой | Mobile |
| 2 | [Dockerfile — добавить non-root USER](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/02-dockerfile-user.md) | High | Минимальный | Backend |
| 3 | [Убрать пароль из комментария](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/03-password-in-comment.md) | Low | Нулевой | Backend |
| 4 | [HTTP ссылка -> HTTPS в шаблоне](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/04-http-to-https-link.md) | Medium | Нулевой | Backend |
| 5 | [Bearer токены в документации -> плейсхолдеры](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/05-docs-bearer-placeholder.md) | High | Нулевой | Backend |
| 6 | [Telegram токены -> env переменные](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/06-telegram-tokens-env.md) | Critical | Средний | Mobile |
| 7 | [Firebase приватный ключ -> secrets](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/07-firebase-private-key.md) | Critical | Средний | Backend |
| 8 | [Keystore пароли -> secure config](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/08-keystore-passwords.md) | High | Средний | Mobile |
| 9 | [Firebase API ключи фронта -> env](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/09-firebase-frontend-env.md) | Critical | Низкий | Frontend |
| 10 | [Hardcoded пароль в Keycloak -> генерация](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/10-keycloak-password.md) | Critical | Высокий | Backend |
| 11 | [Android Network Security Config](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/11-android-network-security.md) | High | Средний | Mobile |
| 12 | [False positives — обоснование](https://github.com/adamshels1/coube-documentation/blob/main/docs/ГТС/fortify-security-fixes/12-false-positives.md) | — | — | Все |

## Порядок выполнения

```
Фаза 1 — Безопасные фиксы (нулевой риск):
  [1] console.log -> [3] пароль в комментарии -> [4] HTTP->HTTPS -> [5] docs Bearer

Фаза 2 — Средний риск (требуют тестирования):
  [2] Dockerfile USER -> [6] Telegram env -> [8] Keystore -> [9] Firebase frontend

Фаза 3 — Высокий риск (требуют координации с DevOps/CI/CD):
  [7] Firebase private key -> [10] Keycloak password -> [11] Android Network Security

Фаза 4 — Документация:
  [12] False positives обоснование для отчёта
```
