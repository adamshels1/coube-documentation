# Backend Task 4: EgovSignSession Entity и Repository

## 📋 Описание

Создать JPA entity для хранения сессий подписания eGov Mobile и соответствующий repository для работы с БД.

## 📍 Расположение

**Entity:** `coube-backend/src/main/java/kz/coube/backend/egov/entity/EgovSignSession.java`
**Repository:** `coube-backend/src/main/java/kz/coube/backend/egov/repository/EgovSignSessionRepository.java`
**Enum:** `coube-backend/src/main/java/kz/coube/backend/egov/entity/enums/SessionStatus.java`

## 🎯 Функциональность

Entity хранит информацию о сессии подписания:
- Уникальный идентификатор сессии (UUID)
- Связь с документом (ID и тип)
- Связь с пользователем
- Статус сессии
- JWT токен для авторизации
- Временные метки

## ✅ Чеклист реализации

### 1. Создание Enum для статусов

- [ ] Создать `SessionStatus.java`:
  ```java
  package kz.coube.backend.egov.entity.enums;

  public enum SessionStatus {
      PENDING,    // Ожидает подписания
      SIGNED,     // Успешно подписана
      EXPIRED,    // Истек срок действия
      ERROR       // Ошибка при подписании
  }
  ```

### 2. Создание Entity класса

- [ ] Создать `EgovSignSession.java`:
  ```java
  package kz.coube.backend.egov.entity;

  import jakarta.persistence.*;
  import kz.coube.backend.egov.entity.enums.SessionStatus;
  import lombok.*;
  import org.hibernate.annotations.CreationTimestamp;

  import java.time.LocalDateTime;

  @Entity
  @Table(
      name = "egov_sign_sessions",
      indexes = {
          @Index(name = "idx_session_id", columnList = "session_id", unique = true),
          @Index(name = "idx_status", columnList = "status"),
          @Index(name = "idx_expires_at", columnList = "expires_at"),
          @Index(name = "idx_document", columnList = "document_type, document_id")
      }
  )
  @Data
  @Builder
  @NoArgsConstructor
  @AllArgsConstructor
  public class EgovSignSession {

      @Id
      @GeneratedValue(strategy = GenerationType.IDENTITY)
      private Long id;

      @Column(name = "session_id", nullable = false, unique = true, length = 36)
      private String sessionId; // UUID

      @Column(name = "document_id", nullable = false, length = 50)
      private String documentId;

      @Column(name = "document_type", nullable = false, length = 50)
      private String documentType; // agreement, invoice, act, registry

      @Column(name = "user_id", nullable = false)
      private Long userId;

      @Enumerated(EnumType.STRING)
      @Column(name = "status", nullable = false, length = 20)
      private SessionStatus status;

      @Column(name = "auth_token", nullable = false, length = 500)
      private String authToken; // JWT токен

      @Column(name = "created_at", nullable = false, updatable = false)
      @CreationTimestamp
      private LocalDateTime createdAt;

      @Column(name = "expires_at", nullable = false)
      private LocalDateTime expiresAt;

      @Column(name = "signed_at")
      private LocalDateTime signedAt;

      @Column(name = "error_message", length = 500)
      private String errorMessage;

      // Вспомогательные методы
      public boolean isExpired() {
          return LocalDateTime.now().isAfter(expiresAt);
      }

      public boolean isPending() {
          return status == SessionStatus.PENDING;
      }

      public boolean isSigned() {
          return status == SessionStatus.SIGNED;
      }
  }
  ```

### 3. Создание Repository

- [ ] Создать `EgovSignSessionRepository.java`:
  ```java
  package kz.coube.backend.egov.repository;

  import kz.coube.backend.egov.entity.EgovSignSession;
  import kz.coube.backend.egov.entity.enums.SessionStatus;
  import org.springframework.data.jpa.repository.JpaRepository;
  import org.springframework.data.jpa.repository.Query;
  import org.springframework.data.repository.query.Param;
  import org.springframework.stereotype.Repository;

  import java.time.LocalDateTime;
  import java.util.List;
  import java.util.Optional;

  @Repository
  public interface EgovSignSessionRepository extends JpaRepository<EgovSignSession, Long> {

      /**
       * Найти сессию по sessionId (UUID)
       */
      Optional<EgovSignSession> findBySessionId(String sessionId);

      /**
       * Найти все сессии по статусу
       */
      List<EgovSignSession> findByStatus(SessionStatus status);

      /**
       * Подсчет сессий по статусу
       */
      long countByStatus(SessionStatus status);

      /**
       * Найти истекшие сессии с определенными статусами
       */
      List<EgovSignSession> findByExpiresAtBeforeAndStatusIn(
          LocalDateTime expiresAt,
          List<SessionStatus> statuses
      );

      /**
       * Найти все сессии пользователя
       */
      List<EgovSignSession> findByUserIdOrderByCreatedAtDesc(Long userId);

      /**
       * Найти сессии для документа
       */
      List<EgovSignSession> findByDocumentTypeAndDocumentIdOrderByCreatedAtDesc(
          String documentType,
          String documentId
      );

      /**
       * Проверить существование активной сессии для документа
       */
      @Query("SELECT COUNT(s) > 0 FROM EgovSignSession s " +
             "WHERE s.documentType = :documentType " +
             "AND s.documentId = :documentId " +
             "AND s.status = :status " +
             "AND s.expiresAt > :now")
      boolean existsActiveSession(
          @Param("documentType") String documentType,
          @Param("documentId") String documentId,
          @Param("status") SessionStatus status,
          @Param("now") LocalDateTime now
      );

      /**
       * Удалить старые сессии (старше N дней)
       */
      void deleteByCreatedAtBefore(LocalDateTime createdAt);

      /**
       * Получить последнюю сессию для документа
       */
      @Query("SELECT s FROM EgovSignSession s " +
             "WHERE s.documentType = :documentType " +
             "AND s.documentId = :documentId " +
             "ORDER BY s.createdAt DESC")
      Optional<EgovSignSession> findLatestSessionForDocument(
          @Param("documentType") String documentType,
          @Param("documentId") String documentId
      );
  }
  ```

### 4. Flyway миграция

- [ ] Создать файл миграции `V{version}__Create_egov_sign_sessions_table.sql`:
  ```sql
  -- Создание таблицы сессий подписания eGov Mobile
  CREATE TABLE egov_sign_sessions (
      id BIGSERIAL PRIMARY KEY,
      session_id VARCHAR(36) NOT NULL UNIQUE,
      document_id VARCHAR(50) NOT NULL,
      document_type VARCHAR(50) NOT NULL,
      user_id BIGINT NOT NULL,
      status VARCHAR(20) NOT NULL,
      auth_token VARCHAR(500) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NOT NULL,
      signed_at TIMESTAMP,
      error_message VARCHAR(500),

      -- Внешние ключи
      CONSTRAINT fk_egov_sessions_user
          FOREIGN KEY (user_id)
          REFERENCES users(id)
          ON DELETE CASCADE,

      -- Проверки
      CONSTRAINT chk_session_id_uuid
          CHECK (session_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),

      CONSTRAINT chk_document_type
          CHECK (document_type IN ('agreement', 'invoice', 'act', 'registry')),

      CONSTRAINT chk_status
          CHECK (status IN ('PENDING', 'SIGNED', 'EXPIRED', 'ERROR')),

      CONSTRAINT chk_expires_after_created
          CHECK (expires_at > created_at)
  );

  -- Индексы для производительности
  CREATE UNIQUE INDEX idx_egov_sessions_session_id
      ON egov_sign_sessions(session_id);

  CREATE INDEX idx_egov_sessions_status
      ON egov_sign_sessions(status);

  CREATE INDEX idx_egov_sessions_expires_at
      ON egov_sign_sessions(expires_at);

  CREATE INDEX idx_egov_sessions_document
      ON egov_sign_sessions(document_type, document_id);

  CREATE INDEX idx_egov_sessions_user_created
      ON egov_sign_sessions(user_id, created_at DESC);

  -- Комментарии
  COMMENT ON TABLE egov_sign_sessions IS 'Сессии подписания документов через eGov Mobile';
  COMMENT ON COLUMN egov_sign_sessions.session_id IS 'Уникальный идентификатор сессии (UUID)';
  COMMENT ON COLUMN egov_sign_sessions.document_id IS 'ID документа для подписания';
  COMMENT ON COLUMN egov_sign_sessions.document_type IS 'Тип документа: agreement, invoice, act, registry';
  COMMENT ON COLUMN egov_sign_sessions.status IS 'Статус: PENDING, SIGNED, EXPIRED, ERROR';
  COMMENT ON COLUMN egov_sign_sessions.auth_token IS 'JWT токен для авторизации запросов от eGov Mobile';
  COMMENT ON COLUMN egov_sign_sessions.expires_at IS 'Время истечения сессии (TTL 30 минут)';
  COMMENT ON COLUMN egov_sign_sessions.signed_at IS 'Время успешного подписания';
  ```

### 5. Scheduled cleanup задача (опционально в отдельной миграции)

- [ ] Создать функцию для автоочистки:
  ```sql
  -- Функция для удаления старых сессий (старше 30 дней)
  CREATE OR REPLACE FUNCTION cleanup_old_egov_sessions()
  RETURNS INTEGER AS $$
  DECLARE
      deleted_count INTEGER;
  BEGIN
      DELETE FROM egov_sign_sessions
      WHERE created_at < NOW() - INTERVAL '30 days';

      GET DIAGNOSTICS deleted_count = ROW_COUNT;

      RETURN deleted_count;
  END;
  $$ LANGUAGE plpgsql;

  COMMENT ON FUNCTION cleanup_old_egov_sessions() IS 'Удаляет сессии подписания старше 30 дней';
  ```

### 6. Документация БД

- [ ] Обновить `database-architecture-complete.md`:
  - Добавить описание таблицы `egov_sign_sessions`
  - Добавить связи с таблицей `users`
  - Описать индексы и проверки

### 7. Тестирование

- [ ] Написать unit-тесты для Entity:
  - Методы `isExpired()`, `isPending()`, `isSigned()`
  - Builder pattern

- [ ] Написать интеграционные тесты для Repository:
  - `findBySessionId`
  - `findByStatus`
  - `findByExpiresAtBeforeAndStatusIn`
  - `existsActiveSession`
  - `findLatestSessionForDocument`

- [ ] Тест миграции Flyway:
  - Проверить создание таблицы
  - Проверить создание индексов
  - Проверить constraints

### 8. Валидация данных

- [ ] Добавить Jakarta Bean Validation аннотации в Entity (опционально):
  ```java
  @NotBlank(message = "Session ID cannot be blank")
  @Pattern(regexp = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
           message = "Session ID must be valid UUID")
  private String sessionId;

  @NotBlank(message = "Document ID cannot be blank")
  @Size(max = 50)
  private String documentId;

  @NotNull
  @Enumerated(EnumType.STRING)
  private SessionStatus status;
  ```

### 9. Логирование (JPA Audit)

- [ ] Добавить `@EntityListeners(AuditingEntityListener.class)` (опционально)
- [ ] Использовать `@CreatedDate` для `createdAt`
- [ ] Добавить `@LastModifiedDate` для отслеживания изменений

## 📚 Требования

### Индексы
- ✅ Уникальный индекс на `session_id`
- ✅ Индекс на `status` (для поиска по статусу)
- ✅ Индекс на `expires_at` (для cleanup задачи)
- ✅ Композитный индекс на `document_type, document_id` (для поиска сессий документа)
- ✅ Композитный индекс на `user_id, created_at` (для истории пользователя)

### Constraints
- ✅ UUID формат для `session_id`
- ✅ Allowed values для `document_type`
- ✅ Allowed values для `status`
- ✅ `expires_at` > `created_at`
- ✅ Foreign key на `users` таблицу

### Время жизни данных
- **Active sessions**: Автоочистка через 30 минут (Task 3)
- **Historical data**: Хранить 30 дней для аудита/статистики

## 🔗 Зависимости

**Зависит от:**
- Существующая таблица `users`

**Необходимо для:**
- Task 3: `EgovSignSessionService`
- Task 1: `EgovSignController`
- Task 2: `EgovDocumentController`

## ⚠️ Важные замечания

1. **UUID формат**: session_id должен быть валидным UUID v4
2. **Каскадное удаление**: При удалении пользователя удаляются его сессии
3. **Timezone**: Все timestamp в UTC
4. **Performance**: Индексы обязательны для быстрого поиска
5. **Data retention**: Старые сессии (>30 дней) должны удаляться

## 📊 Критерии приемки

- [ ] Entity `EgovSignSession` создан с всеми полями
- [ ] Enum `SessionStatus` создан
- [ ] Repository `EgovSignSessionRepository` создан со всеми методами
- [ ] Flyway миграция создана и выполнена успешно
- [ ] Таблица создается с индексами и constraints
- [ ] Все методы repository работают корректно
- [ ] Unit и integration тесты проходят
- [ ] Документация БД обновлена

---

**Приоритет:** 🔴 Высокий (блокирует Task 3)
**Оценка:** 2-3 часа
**Assignee:** Backend Developer
**Должно быть выполнено первым в бэкенде**
