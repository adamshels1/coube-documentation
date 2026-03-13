# Задача 11: Android Network Security Configuration

**Приоритет:** High (Android Bad Practices — 5 проблем)
**Риск поломки:** Средний
**Компонент:** coube-mobile

## Проблемы

1. **Missing Network Security Configuration** — нет файла `network_security_config.xml`
2. **Missing Google Play Services Updated Security Provider** — не обновляется Security Provider
3. **Missing Component Permission** — MainActivity без явного permission
4. **Cleartext traffic** в debug manifest — `usesCleartextTraffic="true"`

## Решение

### 1. Создать Network Security Config

**Новый файл `coube-mobile/android/app/src/main/res/xml/network_security_config.xml`:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- Запрещаем cleartext (HTTP) трафик по умолчанию -->
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>

    <!-- Исключение только для локальной разработки (Metro bundler) -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
    </domain-config>
</network-security-config>
```

### 2. Подключить в AndroidManifest.xml

**`coube-mobile/android/app/src/main/AndroidManifest.xml`:**
```xml
<!-- БЫЛО: -->
<application
    android:name=".MainApplication"
    android:label="@string/app_name"
    ...
    android:supportsRtl="true">

<!-- СТАЛО: -->
<application
    android:name=".MainApplication"
    android:label="@string/app_name"
    ...
    android:supportsRtl="true"
    android:networkSecurityConfig="@xml/network_security_config">
```

### 3. Обновить debug manifest

**`coube-mobile/android/app/src/debug/AndroidManifest.xml`:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <application
        tools:targetApi="28"
        tools:ignore="GoogleAppIndexingWarning"/>
</manifest>
```

Убираем `android:usesCleartextTraffic="true"` — теперь Network Security Config управляет этим.

### 4. Google Play Services Security Provider (опционально)

Добавить в `MainApplication.java` или `MainActivity.java`:
```java
import com.google.android.gms.security.ProviderInstaller;

@Override
public void onCreate() {
    super.onCreate();
    // Обновляем Security Provider
    try {
        ProviderInstaller.installIfNeeded(this);
    } catch (Exception e) {
        // Не критично если не удалось
        Log.w("SecurityProvider", "Failed to install security provider", e);
    }
}
```

> **Примечание:** Для этого нужна зависимость `com.google.android.gms:play-services-base` — проверить что она уже есть через Firebase.

### 5. MainActivity permission (НЕ РЕКОМЕНДУЕТСЯ менять)

Fortify ругается на `android:exported="true"` без явного `android:permission`. Но это **LAUNCHER Activity** — ей положено быть exported. Добавление permission сломает запуск приложения. **Это false positive для launcher activity.**

## Проверка

```bash
cd coube-mobile

# Пересобрать Android
npm run android

# Проверить:
# 1. Приложение запускается
# 2. API вызовы работают (HTTPS)
# 3. Metro bundler подключается (localhost cleartext разрешён)
# 4. Yandex Maps загружаются
```

## Риски

- Если API backend использует HTTP (не HTTPS) — запросы будут блокироваться
- Yandex Maps SDK может использовать HTTP для тайлов — если карты перестанут работать, добавить исключение:
  ```xml
  <domain-config cleartextTrafficPermitted="true">
      <domain includeSubdomains="true">maps.yandex.net</domain>
  </domain-config>
  ```
- ProviderInstaller может не работать на устройствах без Google Play Services (Huawei)
