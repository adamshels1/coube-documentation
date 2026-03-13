# Задача 2: Dockerfile — добавить non-root USER

**Приоритет:** High
**Риск поломки:** Минимальный
**Компонент:** coube-backend

## Проблема

Контейнер запускается от root-пользователя. При компрометации контейнера атакующий получает root-доступ.

## Затронутый файл

### `coube-backend/Dockerfile`

**БЫЛО:**
```dockerfile
# Этап финального образа
FROM eclipse-temurin:23
WORKDIR /app

# Копируем итоговый JAR из этапа сборки
COPY --from=builder /app/build/libs/*.jar app.jar

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

**СТАЛО:**
```dockerfile
# Этап финального образа
FROM eclipse-temurin:23-jre
WORKDIR /app

# Создаём непривилегированного пользователя
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

# Копируем итоговый JAR из этапа сборки
COPY --from=builder /app/build/libs/*.jar app.jar

# Устанавливаем владельца файлов
RUN chown -R appuser:appgroup /app

# Переключаемся на непривилегированного пользователя
USER appuser

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

## Что изменено

1. **`FROM eclipse-temurin:23-jre`** — используем JRE вместо JDK (меньше attack surface, меньше размер образа)
2. **`RUN groupadd/useradd`** — создаём системного пользователя `appuser`
3. **`RUN chown`** — даём права на директорию приложения
4. **`USER appuser`** — переключаемся на non-root

## Проверка

```bash
# Собрать образ
cd coube-backend && docker build -t coube-backend-test .

# Проверить что процесс запущен не от root
docker run --rm coube-backend-test whoami
# Ожидаемый результат: appuser

# Проверить что приложение стартует
docker run --rm -p 8080:8080 coube-backend-test
```

## Риски

- Если приложение пишет файлы на диск (логи, temp) — нужно убедиться, что у `appuser` есть доступ к этим директориям
- Если используется привязка к портам < 1024 — non-root не сможет (но 8080 > 1024, так что ОК)
