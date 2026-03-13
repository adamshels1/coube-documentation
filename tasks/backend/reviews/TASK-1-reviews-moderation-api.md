# TASK-1: API для модерации отзывов суперадмином (MVP)

## Описание
Разработать REST API endpoints для модерации отзывов суперадмином. Функционал отзывов уже имеет готовую структуру БД (схема `reviews`), необходимо создать минимальный API для управления модерацией отзывов.

## Контекст
В системе уже реализована структура БД для отзывов (миграции `V20260107145000__create_reviews_tables.sql`):
- Таблица `reviews.reviews` с полями модерации (status, moderated_at, moderator_id, moderation_reason)
- Таблица `reviews.review_flags` для жалоб на отзывы
- Таблица `reviews.user_reputation` для кэша репутации организаций
- Статусы отзывов: `pending`, `approved`, `rejected`

## Приоритет
High

## Story Points
5

---

## Необходимые Endpoints (MVP)

### 1. Получение списка отзывов для модерации
**GET** `/api/v1/admin/reviews/moderation`

**Назначение**: Получить список всех отзывов с возможностью фильтрации и пагинации

**Query параметры**:
```
?status=pending|approved|rejected          (опционально, можно несколько через запятую)
?transportationId={id}                     (опционально)
?organizationId={id}                       (опционально, поиск отзывов от/к организации)
?fromDate=2026-01-01                       (опционально, фильтр по created_at)
?toDate=2026-01-31                         (опционально, фильтр по created_at)
?page=0
?size=20
?sort=createdAt,desc
```

**Response**:
```json
{
  "content": [
    {
      "id": 123,
      "transportationId": 456,
      "transportation": {
        "id": 456,
        "number": "TR-2026-001"
      },
      "fromOrganization": {
        "id": 100,
        "name": "ТОО Перевозчик",
        "bin": "123456789012"
      },
      "toOrganization": {
        "id": 200,
        "name": "ТОО Заказчик",
        "bin": "987654321098"
      },
      "roleFrom": "executor",
      "overallRating": 4,
      "criteria": {
        "punctuality": 5,
        "communication": 4,
        "quality": 4,
        "professionalism": 3
      },
      "comment": "Хороший заказчик, оплата вовремя",
      "isPublic": true,
      "status": "pending",
      "createdAt": "2026-01-09T10:00:00Z",
      "updatedAt": "2026-01-09T10:00:00Z",
      "moderatedAt": null,
      "moderatorId": null,
      "moderationReason": null
    }
  ],
  "pageable": {...},
  "totalElements": 150,
  "totalPages": 8,
  "size": 20,
  "number": 0
}
```

**Права доступа**: SUPER_ADMIN

---

### 2. Получение деталей конкретного отзыва
**GET** `/api/v1/admin/reviews/{reviewId}`

**Назначение**: Получить полную информацию об отзыве, включая историю жалоб и репутацию организаций

**Response**:
```json
{
  "id": 123,
  "transportationId": 456,
  "transportation": {
    "id": 456,
    "number": "TR-2026-001",
    "status": "COMPLETED",
    "route": "Алматы - Астана"
  },
  "fromOrganization": {
    "id": 100,
    "name": "ТОО Перевозчик",
    "bin": "123456789012",
    "reputation": {
      "avgRating": 4.5,
      "reviewsCount": 45
    }
  },
  "toOrganization": {
    "id": 200,
    "name": "ТОО Заказчик",
    "bin": "987654321098",
    "reputation": {
      "avgRating": 3.8,
      "reviewsCount": 22
    }
  },
  "roleFrom": "executor",
  "overallRating": 4,
  "criteria": {
    "punctuality": 5,
    "communication": 4,
    "quality": 4,
    "professionalism": 3
  },
  "comment": "Хороший заказчик, оплата вовремя",
  "isPublic": true,
  "status": "pending",
  "reviewFlags": [
    {
      "id": 1,
      "flaggedByOrganization": {
        "id": 200,
        "name": "ТОО Заказчик"
      },
      "reason": "Некорректная информация",
      "createdAt": "2026-01-09T11:00:00Z"
    }
  ],
  "createdAt": "2026-01-09T10:00:00Z",
  "updatedAt": "2026-01-09T10:00:00Z",
  "moderatedAt": null,
  "moderator": null,
  "moderationReason": null
}
```

**Права доступа**: SUPER_ADMIN

---

### 3. Одобрение отзыва
**PUT** `/api/v1/admin/reviews/{reviewId}/approve`

**Назначение**: Одобрить отзыв (изменить статус на `approved`)

**Request Body**:
```json
{
  "makePublic": true  // опционально, сделать отзыв публичным (по умолчанию true)
}
```

**Response**:
```json
{
  "id": 123,
  "status": "approved",
  "isPublic": true,
  "moderatedAt": "2026-01-09T12:00:00Z",
  "moderator": {
    "id": 1,
    "firstName": "Иван",
    "lastName": "Иванов"
  },
  "moderationReason": null
}
```

**Бизнес-логика**:
- Изменить `status` на `approved`
- Установить `moderated_at = NOW()`
- Установить `moderator_id = текущий пользователь`
- Если `makePublic = true` (по умолчанию), установить `is_public = true`
- Пересчитать репутацию организации в `reviews.user_reputation`

**Права доступа**: SUPER_ADMIN

---

### 4. Отклонение отзыва
**PUT** `/api/v1/admin/reviews/{reviewId}/reject`

**Назначение**: Отклонить отзыв (изменить статус на `rejected`)

**Request Body**:
```json
{
  "reason": "Содержит ненормативную лексику"  // ОБЯЗАТЕЛЬНО
}
```

**Response**:
```json
{
  "id": 123,
  "status": "rejected",
  "isPublic": false,
  "moderatedAt": "2026-01-09T12:00:00Z",
  "moderator": {
    "id": 1,
    "firstName": "Иван",
    "lastName": "Иванов"
  },
  "moderationReason": "Содержит ненормативную лексику"
}
```

**Validation**:
- `reason` - **ОБЯЗАТЕЛЬНОЕ** поле, минимум 10 символов, максимум 500 символов

**Бизнес-логика**:
- Изменить `status` на `rejected`
- Установить `moderated_at = NOW()`
- Установить `moderator_id = текущий пользователь`
- Установить `moderation_reason = reason`
- Установить `is_public = false` (отклоненный отзыв всегда скрыт)
- НЕ учитывать отклоненный отзыв в репутации организации

**Права доступа**: SUPER_ADMIN

---

## Дополнительные требования

### Security
- Все endpoints доступны только пользователям с ролью `SUPER_ADMIN`
- Логирование всех действий модераторов (кто, когда, что изменил)

### Validation
- Проверка существования отзыва перед модерацией
- Проверка, что отзыв еще не модерирован (статус должен быть `pending`)
- Проверка обязательных полей (например, `reason` при отклонении)

### Business Logic
- При одобрении/отклонении отзыва пересчитывать репутацию организации (`reviews.user_reputation`)
- Только отзывы со статусом `approved` учитываются в репутации

### Performance
- Использовать существующие индексы из миграции `V20260107145200__create_reviews_indexes.sql`
- Оптимизация запросов с JOIN для получения данных организаций и перевозок

---

## Технический дизайн

### Структура модулей

```
kz.coube.backend.reviews
├── api
│   └── admin
│       └── ReviewModerationController.java
├── service
│   ├── ReviewModerationService.java
│   └── ReviewReputationService.java
├── repository
│   ├── ReviewRepository.java
│   ├── ReviewFlagRepository.java
│   └── UserReputationRepository.java
├── entity
│   ├── Review.java
│   ├── ReviewFlag.java
│   └── UserReputation.java
├── dto
│   ├── request
│   │   ├── ApproveReviewRequest.java
│   │   └── RejectReviewRequest.java
│   └── response
│       ├── ReviewDetailResponse.java
│       ├── ReviewListResponse.java
│       └── ReviewModerationResponse.java
└── mapper
    └── ReviewMapper.java
```

### Основные классы

#### ReviewModerationController.java
```java
@RestController
@RequestMapping("/api/v1/admin/reviews")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class ReviewModerationController {

    private final ReviewModerationService moderationService;

    @GetMapping("/moderation")
    public Page<ReviewListResponse> getReviewsForModeration(
        @RequestParam(required = false) List<ReviewStatus> status,
        @RequestParam(required = false) Long transportationId,
        @RequestParam(required = false) Long organizationId,
        @RequestParam(required = false) @DateTimeFormat(iso = ISO.DATE) LocalDate fromDate,
        @RequestParam(required = false) @DateTimeFormat(iso = ISO.DATE) LocalDate toDate,
        Pageable pageable
    ) {
        return moderationService.getReviewsForModeration(
            status, transportationId, organizationId, fromDate, toDate, pageable
        );
    }

    @GetMapping("/{reviewId}")
    public ReviewDetailResponse getReviewDetails(@PathVariable Long reviewId) {
        return moderationService.getReviewDetails(reviewId);
    }

    @PutMapping("/{reviewId}/approve")
    @AuditLog(action = "REVIEW_APPROVED")
    public ReviewModerationResponse approveReview(
        @PathVariable Long reviewId,
        @RequestBody(required = false) ApproveReviewRequest request,
        @AuthenticationPrincipal UserDetails userDetails
    ) {
        Long moderatorId = getCurrentUserId(userDetails);
        return moderationService.approveReview(reviewId, request, moderatorId);
    }

    @PutMapping("/{reviewId}/reject")
    @AuditLog(action = "REVIEW_REJECTED")
    public ReviewModerationResponse rejectReview(
        @PathVariable Long reviewId,
        @Valid @RequestBody RejectReviewRequest request,
        @AuthenticationPrincipal UserDetails userDetails
    ) {
        Long moderatorId = getCurrentUserId(userDetails);
        return moderationService.rejectReview(reviewId, request, moderatorId);
    }
}
```

#### ReviewModerationService.java
```java
@Service
@Slf4j
public class ReviewModerationService {

    private final ReviewRepository reviewRepository;
    private final ReviewReputationService reputationService;

    @Transactional
    public ReviewModerationResponse approveReview(
        Long reviewId,
        ApproveReviewRequest request,
        Long moderatorId
    ) {
        Review review = findReviewOrThrow(reviewId);

        // Проверка статуса
        if (review.getStatus() != ReviewStatus.PENDING) {
            throw new IllegalStateException("Review can only be approved from PENDING status");
        }

        // Обновление статуса
        review.setStatus(ReviewStatus.APPROVED);
        review.setModeratedAt(LocalDateTime.now());
        review.setModeratorId(moderatorId);

        boolean makePublic = request != null && request.getMakePublic() != null
            ? request.getMakePublic()
            : true;
        review.setIsPublic(makePublic);

        reviewRepository.save(review);

        // Пересчет репутации
        reputationService.recalculateReputation(review.getToOrganizationId());

        log.info("Review {} approved by moderator {}", reviewId, moderatorId);

        return mapToResponse(review);
    }

    @Transactional
    public ReviewModerationResponse rejectReview(
        Long reviewId,
        RejectReviewRequest request,
        Long moderatorId
    ) {
        Review review = findReviewOrThrow(reviewId);

        // Проверка статуса
        if (review.getStatus() != ReviewStatus.PENDING) {
            throw new IllegalStateException("Review can only be rejected from PENDING status");
        }

        // Обновление статуса
        review.setStatus(ReviewStatus.REJECTED);
        review.setModeratedAt(LocalDateTime.now());
        review.setModeratorId(moderatorId);
        review.setModerationReason(request.getReason());
        review.setIsPublic(false); // Отклоненные отзывы всегда скрыты

        reviewRepository.save(review);

        // Пересчет репутации (отклоненные не учитываются)
        reputationService.recalculateReputation(review.getToOrganizationId());

        log.info("Review {} rejected by moderator {}: {}", reviewId, moderatorId, request.getReason());

        return mapToResponse(review);
    }

    private Review findReviewOrThrow(Long reviewId) {
        return reviewRepository.findById(reviewId)
            .orElseThrow(() -> new EntityNotFoundException("Review not found: " + reviewId));
    }
}
```

#### RejectReviewRequest.java (DTO)
```java
public class RejectReviewRequest {

    @NotBlank(message = "Reason is required")
    @Size(min = 10, max = 500, message = "Reason must be between 10 and 500 characters")
    private String reason;

    // Getters, setters
}
```

#### Review.java (Entity)
```java
@Entity
@Table(name = "reviews", schema = "reviews")
@Data
public class Review {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "transportation_id", nullable = false)
    private Long transportationId;

    @Column(name = "from_organization_id", nullable = false)
    private Long fromOrganizationId;

    @Column(name = "to_organization_id", nullable = false)
    private Long toOrganizationId;

    @Column(name = "role_from", nullable = false)
    @Enumerated(EnumType.STRING)
    private ReviewRoleFrom roleFrom; // EXECUTOR, CUSTOMER

    @Column(name = "overall_rating", nullable = false)
    private Short overallRating;

    @Type(JsonBinaryType.class)
    @Column(name = "criteria", columnDefinition = "jsonb", nullable = false)
    private Map<String, Integer> criteria;

    @Column(name = "comment", length = 1000)
    private String comment;

    @Column(name = "is_public", nullable = false)
    private Boolean isPublic = true;

    @Column(name = "status", nullable = false)
    @Enumerated(EnumType.STRING)
    private ReviewStatus status = ReviewStatus.PENDING;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Column(name = "moderated_at")
    private LocalDateTime moderatedAt;

    @Column(name = "moderator_id")
    private Long moderatorId;

    @Column(name = "moderation_reason", length = 500)
    private String moderationReason;

    // Getters, setters
}

enum ReviewStatus {
    PENDING,
    APPROVED,
    REJECTED
}

enum ReviewRoleFrom {
    EXECUTOR,
    CUSTOMER
}
```

#### ReviewReputationService.java
```java
@Service
@Slf4j
public class ReviewReputationService {

    private final ReviewRepository reviewRepository;
    private final UserReputationRepository reputationRepository;

    @Transactional
    public void recalculateReputation(Long organizationId) {
        // Получить все одобренные отзывы для организации
        List<Review> approvedReviews = reviewRepository
            .findByToOrganizationIdAndStatus(organizationId, ReviewStatus.APPROVED);

        if (approvedReviews.isEmpty()) {
            // Если нет отзывов, обнулить репутацию
            UserReputation reputation = reputationRepository
                .findById(organizationId)
                .orElse(new UserReputation(organizationId));

            reputation.setAvgRating(BigDecimal.ZERO);
            reputation.setReviewsCount(0);
            reputation.setStars1(0);
            reputation.setStars2(0);
            reputation.setStars3(0);
            reputation.setStars4(0);
            reputation.setStars5(0);
            reputation.setUpdatedAt(LocalDateTime.now());

            reputationRepository.save(reputation);
            return;
        }

        // Подсчет статистики
        int total = approvedReviews.size();
        double sumRatings = approvedReviews.stream()
            .mapToDouble(Review::getOverallRating)
            .sum();

        Map<Integer, Long> starsDistribution = approvedReviews.stream()
            .collect(Collectors.groupingBy(
                r -> r.getOverallRating().intValue(),
                Collectors.counting()
            ));

        // Обновление репутации
        UserReputation reputation = reputationRepository
            .findById(organizationId)
            .orElse(new UserReputation(organizationId));

        reputation.setAvgRating(BigDecimal.valueOf(sumRatings / total).setScale(2, RoundingMode.HALF_UP));
        reputation.setReviewsCount(total);
        reputation.setStars1(starsDistribution.getOrDefault(1, 0L).intValue());
        reputation.setStars2(starsDistribution.getOrDefault(2, 0L).intValue());
        reputation.setStars3(starsDistribution.getOrDefault(3, 0L).intValue());
        reputation.setStars4(starsDistribution.getOrDefault(4, 0L).intValue());
        reputation.setStars5(starsDistribution.getOrDefault(5, 0L).intValue());
        reputation.setUpdatedAt(LocalDateTime.now());

        reputationRepository.save(reputation);

        log.info("Reputation recalculated for organization {}: avg={}, count={}",
            organizationId, reputation.getAvgRating(), total);
    }
}
```

---

## Критерии приемки

### Backend
- ✅ Реализованы 4 основных endpoints для модерации отзывов
- ✅ Добавлена роль `SUPER_ADMIN` и проверка прав доступа
- ✅ Реализован сервис пересчета репутации организаций
- ✅ Добавлено логирование всех действий модераторов
- ✅ Написаны unit-тесты для сервисов (coverage > 80%)
- ✅ Написаны integration-тесты для API endpoints
- ✅ Добавлена валидация входных данных (обязательное поле `reason` при отклонении)
- ✅ Реализована обработка ошибок и исключений

### Database
- ✅ Используются существующие таблицы БД (миграции уже применены)
- ✅ Проверены все индексы для производительности

### Documentation
- ✅ Добавлена Swagger/OpenAPI документация для всех endpoints
- ✅ Обновлена README в модуле reviews

---

## Зависимости

- ✅ Миграции БД уже применены:
  - `V20260107145000__create_reviews_tables.sql`
  - `V20260107145200__create_reviews_indexes.sql`
- Роль `SUPER_ADMIN` должна быть добавлена в Keycloak
- Audit logging (Spring AOP или аналог)

---

## Связанные таблицы

- `reviews.reviews` - основная таблица отзывов
- `reviews.review_flags` - жалобы на отзывы (только для чтения в GET /{id})
- `reviews.user_reputation` - кэш репутации организаций
- `applications.transportation` - перевозки
- `users.organization` - организации
- `users.employee` - модераторы

---

## Следующие задачи (Next Steps)

После реализации MVP модерации:

1. **TASK-2**: API для пользователей (создание, просмотр отзывов)
2. **TASK-3**: Интеграция frontend для суперадмина (Admin Dashboard)
3. **TASK-4**: Bulk операции (массовое одобрение/отклонение)
4. **TASK-5**: Статистика и аналитика по модерации
5. **TASK-6**: Email/Push уведомления организациям

---

## Примечания

- Backend-разработчик: Back-N-Trick (автор миграций БД)
- Приоритет: High - MVP для запуска функционала отзывов
- Сроки: 3-4 рабочих дня
- **ВАЖНО**: `reason` при отклонении - обязательное поле (10-500 символов)
- **ВАЖНО**: Репутация пересчитывается автоматически при одобрении/отклонении
- **ВАЖНО**: Статус `flagged` не используется в MVP (остается в БД для будущих версий)

---

## Вопросы для уточнения

1. Нужно ли отправлять уведомления организациям при изменении статуса отзыва? (откладывается на TASK-6)
2. Нужно ли API для просмотра истории модерации? (откладывается, таблица не создается)
3. Кто имеет роль SUPER_ADMIN в Keycloak? (уточнить с DevOps)
