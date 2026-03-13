# Задача 4: HTTP ссылка -> HTTPS в шаблоне

**Приоритет:** Medium
**Риск поломки:** Нулевой
**Компонент:** coube-backend

## Проблема

В HTML-шаблоне акта используется HTTP-ссылка на внешний сайт, что допускает перехват трафика (MITM).

## Затронутый файл

### `coube-backend/src/main/resources/templates/acts_template.html`

**Строка 175:**
```html
<!-- БЫЛО: -->
<a href="http://online.zakon.kz/Document/?link_id=1004352905" title="...">к приказу Министра финансов</a>

<!-- СТАЛО: -->
<a href="https://online.zakon.kz/Document/?link_id=1004352905" rel="noopener noreferrer" title="...">к приказу Министра финансов</a>
```

## Что изменено

1. `http://` -> `https://` — шифрованное соединение
2. Добавлен `rel="noopener noreferrer"` — защита от tab-nabbing атаки

## Проверка

- Открыть `https://online.zakon.kz/Document/?link_id=1004352905` в браузере — ссылка работает
- Сгенерировать акт через систему — ссылка в PDF кликабельна
