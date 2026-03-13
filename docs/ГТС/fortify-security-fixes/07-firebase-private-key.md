# Задача 7: Firebase приватный ключ -> secrets management

**Приоритет:** Critical (Key Management — 1 проблема)
**Риск поломки:** Средний
**Компонент:** coube-backend

## Проблема

Приватный ключ Firebase Admin SDK лежит в открытом виде в репозитории. Любой с доступом к репо может отправлять push-уведомления от имени системы.

## Затронутый файл

### `coube-backend/src/main/resources/notification-config/coube-notifications-account-key.json`

Содержит полный service account JSON с приватным ключом:
- `private_key`: RSA приватный ключ (-----BEGIN PRIVATE KEY-----)
- `client_email`: YOUR_FIREBASE_CLIENT_EMAIL
- `private_key_id`: YOUR_FIREBASE_PRIVATE_KEY_ID

## Решение

### Вариант A: Через переменную окружения (рекомендуемый)

Шаг 1 — Найти где файл используется в коде:
```bash
grep -r "coube-notifications-account-key" coube-backend/src/
# или
grep -r "notification-config" coube-backend/src/
```

Шаг 2 — Изменить загрузку конфига:
```java
// БЫЛО (предположительно):
FileInputStream serviceAccount = new FileInputStream("src/main/resources/notification-config/coube-notifications-account-key.json");

// СТАЛО:
String firebaseJson = System.getenv("FIREBASE_SERVICE_ACCOUNT_JSON");
InputStream serviceAccount;
if (firebaseJson != null && !firebaseJson.isEmpty()) {
    serviceAccount = new ByteArrayInputStream(firebaseJson.getBytes(StandardCharsets.UTF_8));
} else {
    // Fallback для локальной разработки
    serviceAccount = getClass().getClassLoader().getResourceAsStream("notification-config/coube-notifications-account-key.json");
}
```

Шаг 3 — Добавить в `.gitignore`:
```
coube-backend/src/main/resources/notification-config/coube-notifications-account-key.json
```

Шаг 4 — В CI/CD (Docker Compose / K8s):
```yaml
# docker-compose.yml
environment:
  FIREBASE_SERVICE_ACCOUNT_JSON: ${FIREBASE_SERVICE_ACCOUNT_JSON}

# или Kubernetes Secret
apiVersion: v1
kind: Secret
metadata:
  name: firebase-credentials
stringData:
  service-account.json: |
    { ... }
```

### Вариант B: Через Spring Boot properties

```yaml
# application.yml
firebase:
  credentials-path: ${FIREBASE_CREDENTIALS_PATH:classpath:notification-config/coube-notifications-account-key.json}
```

## После исправления (ОБЯЗАТЕЛЬНО)

1. **Ротация ключа**: зайти в Google Cloud Console -> IAM -> Service Accounts -> создать новый ключ, удалить старый
2. **Git history**: ключ остаётся в истории git. Рассмотреть `git filter-branch` или `BFG Repo Cleaner`
3. **Мониторинг**: проверить в Google Cloud Console что старый ключ не используется

## Проверка

```bash
# Установить переменную окружения
export FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'

# Запустить backend
./gradlew bootRun

# Отправить тестовое push-уведомление через API
# Убедиться что уведомление доставлено
```

## Риски

- Если переменная окружения не установлена на сервере — push-уведомления перестанут работать
- Нужна координация с DevOps для настройки secrets в production
- Fallback на файл позволяет разработчикам работать локально без перенастройки
