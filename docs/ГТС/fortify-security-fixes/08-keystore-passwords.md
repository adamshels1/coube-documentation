# Задача 8: Keystore пароли -> secure config

**Приоритет:** High (Password Management — 2 проблемы)
**Риск поломки:** Средний
**Компонент:** coube-mobile

## Проблема

Пароли keystore для подписи APK (`L578s#`) захардкожены в `gradle.properties`, который лежит в репозитории.

## Затронутый файл

### `coube-mobile/android/gradle.properties`

**Строки 46-49:**
```properties
MYAPP_UPLOAD_STORE_FILE=my-upload-key.keystore
MYAPP_UPLOAD_KEY_ALIAS=my-key-alias
MYAPP_UPLOAD_STORE_PASSWORD=L578s#
MYAPP_UPLOAD_KEY_PASSWORD=L578s#
```

## Решение

### Шаг 1 — Убрать пароли из `gradle.properties`:

```properties
MYAPP_UPLOAD_STORE_FILE=my-upload-key.keystore
MYAPP_UPLOAD_KEY_ALIAS=my-key-alias
# Passwords moved to environment variables or ~/.gradle/gradle.properties
```

### Шаг 2 — Обновить `coube-mobile/android/app/build.gradle`:

```groovy
// В секции signingConfigs:
signingConfigs {
    release {
        storeFile file(MYAPP_UPLOAD_STORE_FILE)
        storePassword System.getenv("MYAPP_UPLOAD_STORE_PASSWORD") ?: findProperty("MYAPP_UPLOAD_STORE_PASSWORD") ?: ""
        keyAlias MYAPP_UPLOAD_KEY_ALIAS
        keyPassword System.getenv("MYAPP_UPLOAD_KEY_PASSWORD") ?: findProperty("MYAPP_UPLOAD_KEY_PASSWORD") ?: ""
    }
}
```

### Шаг 3 — Для локальной разработки:

Создать `~/.gradle/gradle.properties` (глобальный, НЕ в репозитории):
```properties
MYAPP_UPLOAD_STORE_PASSWORD=L578s#
MYAPP_UPLOAD_KEY_PASSWORD=L578s#
```

### Шаг 4 — Для CI/CD:

```yaml
# GitHub Actions
env:
  MYAPP_UPLOAD_STORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
  MYAPP_UPLOAD_KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
```

## После исправления

1. Рассмотреть генерацию нового keystore с более сильным паролем (текущий `L578s#` слабый)
2. Если генерируется новый keystore — нужно обновить его в Google Play Console (App Signing)

## Проверка

```bash
# Проверить сборку APK
cd coube-mobile
MYAPP_UPLOAD_STORE_PASSWORD='L578s#' MYAPP_UPLOAD_KEY_PASSWORD='L578s#' npm run build:apk

# APK должна быть подписана
jarsigner -verify android/app/build/outputs/apk/release/app-release.apk
```

## Риски

- Если пароли не установлены ни через env ни через ~/.gradle — сборка release APK упадёт
- Keystore файл (`my-upload-key.keystore`) всё ещё в репо — рассмотреть его вынос тоже
