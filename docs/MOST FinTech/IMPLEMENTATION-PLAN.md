# MOST FinTech — Детальный план реализации

> Основан на анализе реального кода. Все пути файлов, имена классов и методов — актуальные.

---

## ЗАДАЧА 1 — Исправить баг URL отправки OTP

**Приоритет: КРИТИЧЕСКИЙ | Время: 5 минут**

### Проблема
В `coube-frontend/src/api/factoring.ts` строка `sendOTP`:
```typescript
// СЕЙЧАС (баг — двойной сегмент):
sendOTP: (id) => request('post', `v1/factoring/payout/payouts/${id}/send-otp`, {}),

// ДОЛЖНО БЫТЬ:
sendOTP: (id) => request('post', `v1/factoring/payout/${id}/send-otp`, {}),
```

### Файл
`coube-frontend/src/api/factoring.ts` — строка с `sendOTP`

---

## ЗАДАЧА 2 — Polling клиентов + авто-включение факторинга

**Приоритет: КРИТИЧЕСКИЙ | Время: ~4 часа**

### Проблема
`MostStatusPollingService` опрашивает только заявки (`GET /factoring`).
Никто не следит за тем, одобрил ли MOST организацию (`GET /client`).
Когда MOST ставит `factoring_available: true` — Coube об этом не узнаёт.

### Что нужно добавить в репозиторий организаций

**Файл:** `coube-backend/src/main/java/kz/coube/backend/organization/model/OrganizationRepository.java`

Добавить запрос для поиска организаций, зарегистрированных в MOST но ещё не получивших одобрение:

```java
@Query("""
    select o from Organization o
    where o.mostRegisteredAt is not null
      and o.factoringAllowed = false
""")
List<Organization> findPendingMostApproval();
```

### Новый сервис

**Новый файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/service/MostClientPollingService.java`

```java
package kz.coube.backend.factoring.service;

import kz.coube.backend.factoring.dto.MostClientCheckLimitResponse;
import kz.coube.backend.organization.model.Organization;
import kz.coube.backend.organization.model.OrganizationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.concurrent.TimeUnit;

@Service
@RequiredArgsConstructor
@Slf4j
public class MostClientPollingService {

    private final OrganizationRepository organizationRepository;
    private final MostClientCheckService mostClientCheckService;
    // TODO: подключить NotificationService для уведомлений

    @Scheduled(fixedRate = 30, timeUnit = TimeUnit.MINUTES)
    @Transactional
    public void pollClientApprovals() {
        List<Organization> pending = organizationRepository.findPendingMostApproval();

        log.info("MOST client polling tick. pending={}", pending.size());

        for (Organization org : pending) {
            try {
                MostClientCheckLimitResponse resp =
                        mostClientCheckService.checkClientLimit(org.getIinBin());

                if (resp == null) continue;

                boolean approved = Boolean.TRUE.equals(resp.factoring_available())
                        && resp.limit_amount() != null;

                if (approved) {
                    org.setFactoringAllowed(true);
                    organizationRepository.save(org);

                    log.info("MOST approved orgId={} taxId={} limit={}",
                            org.getId(), org.getIinBin(), resp.limit_amount());

                    // TODO: уведомить сотрудников организации
                    // notificationService.notifyFactoringApproved(org);
                }

            } catch (Exception e) {
                log.warn("MOST client poll failed orgId={} taxId={}: {}",
                        org.getId(), org.getIinBin(), e.getMessage());
            }
        }
    }
}
```

### Обновить MostClientCheckLimitResponse

**Файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/dto/MostClientCheckLimitResponse.java`

Убедиться что поле `factoring_available` есть в record:

```java
public record MostClientCheckLimitResponse(
    String tax_id,
    String title,
    String kind,
    java.math.BigDecimal limit_amount,
    Boolean factoring_available   // ← убедиться что это поле есть
) {}
```

### Очистить кэш после авто-включения

В `MostClientPollingService` после `org.setFactoringAllowed(true)` нужно сбросить кэш `mostApiClient` для этого `taxId`, чтобы следующий запрос `getMostLimit()` вернул актуальные данные:

```java
// Добавить в MostClientPollingService
private final org.springframework.cache.CacheManager cacheManager;

// После save(org):
var cache = cacheManager.getCache("mostApiClient");
if (cache != null) cache.evict(org.getIinBin());
```

---

## ЗАДАЧА 3 — MostApiOutboxService

**Приоритет: КРИТИЧЕСКИЙ | Время: ~6 часов**

### Проблема
Таблица `factoring.most_api_outbox` создана в БД но Java-сервис не реализован.
При падении MOST API в момент `confirmPayout()` или `processSignedFactoringActs()` — запрос теряется навсегда.

### Шаг 1 — Entity

**Новый файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/entity/MostApiOutbox.java`

```java
package kz.coube.backend.factoring.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "most_api_outbox", schema = "factoring")
@Getter @Setter @NoArgsConstructor
public class MostApiOutbox {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "payout_request_id")
    private UUID payoutRequestId;

    // "CREATE_APPLICATION" или "UPLOAD_DOCUMENTS"
    @Column(name = "operation", nullable = false, length = 30)
    private String operation;

    @Column(name = "payload", columnDefinition = "jsonb", nullable = false)
    private String payload;

    // PENDING / PROCESSING / COMPLETED / FAILED
    @Column(name = "status", nullable = false, length = 20)
    private String status = "PENDING";

    @Column(name = "attempts")
    private int attempts = 0;

    @Column(name = "max_attempts")
    private int maxAttempts = 5;

    @Column(name = "last_error", columnDefinition = "text")
    private String lastError;

    @Column(name = "next_retry_at")
    private LocalDateTime nextRetryAt;

    @Column(name = "created_at")
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "completed_at")
    private LocalDateTime completedAt;
}
```

### Шаг 2 — Repository

**Новый файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/repository/MostApiOutboxRepository.java`

```java
package kz.coube.backend.factoring.repository;

import kz.coube.backend.factoring.entity.MostApiOutbox;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Repository
public interface MostApiOutboxRepository extends JpaRepository<MostApiOutbox, UUID> {

    @Query("""
        select o from MostApiOutbox o
        where o.status = 'PENDING'
          and (o.nextRetryAt is null or o.nextRetryAt <= :now)
          and o.attempts < o.maxAttempts
        order by o.createdAt asc
    """)
    List<MostApiOutbox> findPendingForProcessing(LocalDateTime now);
}
```

### Шаг 3 — Сервис

**Новый файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/service/MostApiOutboxService.java`

```java
package kz.coube.backend.factoring.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import kz.coube.backend.factoring.entity.FactoringPayoutRequest;
import kz.coube.backend.factoring.entity.MostApiOutbox;
import kz.coube.backend.factoring.repository.FactoringPayoutRequestRepository;
import kz.coube.backend.factoring.repository.MostApiOutboxRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
@RequiredArgsConstructor
@Slf4j
public class MostApiOutboxService {

    private final MostApiOutboxRepository outboxRepo;
    private final FactoringPayoutRequestRepository payoutRepo;
    private final MostCreateApplicationService mostCreateApplicationService;
    private final MostUploadDocumentsService mostUploadDocumentsService;
    private final ObjectMapper objectMapper;

    // Exponential backoff в минутах: 1, 2, 4, 8, 16
    private static final int[] BACKOFF_MINUTES = {1, 2, 4, 8, 16};

    public void scheduleCreateApplication(UUID payoutId) {
        MostApiOutbox entry = new MostApiOutbox();
        entry.setPayoutRequestId(payoutId);
        entry.setOperation("CREATE_APPLICATION");
        entry.setPayload("{\"payoutId\":\"" + payoutId + "\"}");
        entry.setStatus("PENDING");
        outboxRepo.save(entry);
        log.info("Scheduled CREATE_APPLICATION for payoutId={}", payoutId);
    }

    public void scheduleUploadDocuments(UUID payoutId) {
        MostApiOutbox entry = new MostApiOutbox();
        entry.setPayoutRequestId(payoutId);
        entry.setOperation("UPLOAD_DOCUMENTS");
        entry.setPayload("{\"payoutId\":\"" + payoutId + "\"}");
        entry.setStatus("PENDING");
        outboxRepo.save(entry);
        log.info("Scheduled UPLOAD_DOCUMENTS for payoutId={}", payoutId);
    }

    @Scheduled(fixedRate = 1, timeUnit = TimeUnit.MINUTES)
    @Transactional
    public void processOutbox() {
        List<MostApiOutbox> items = outboxRepo.findPendingForProcessing(LocalDateTime.now());
        if (items.isEmpty()) return;

        log.info("Processing outbox items={}", items.size());

        for (MostApiOutbox item : items) {
            item.setStatus("PROCESSING");
            item.setAttempts(item.getAttempts() + 1);
            outboxRepo.save(item);

            try {
                processItem(item);
                item.setStatus("COMPLETED");
                item.setCompletedAt(LocalDateTime.now());
                log.info("Outbox item completed id={} op={}", item.getId(), item.getOperation());

            } catch (Exception e) {
                log.warn("Outbox item failed id={} op={} attempt={}/{} err={}",
                        item.getId(), item.getOperation(),
                        item.getAttempts(), item.getMaxAttempts(), e.getMessage());

                item.setLastError(e.getMessage());

                if (item.getAttempts() >= item.getMaxAttempts()) {
                    item.setStatus("FAILED");
                    log.error("Outbox item FAILED permanently id={} op={} payoutId={}",
                            item.getId(), item.getOperation(), item.getPayoutRequestId());
                } else {
                    item.setStatus("PENDING");
                    int backoffIdx = Math.min(item.getAttempts() - 1, BACKOFF_MINUTES.length - 1);
                    item.setNextRetryAt(LocalDateTime.now().plusMinutes(BACKOFF_MINUTES[backoffIdx]));
                }
            }

            outboxRepo.save(item);
        }
    }

    private void processItem(MostApiOutbox item) {
        UUID payoutId = item.getPayoutRequestId();
        FactoringPayoutRequest payout = payoutRepo.findById(payoutId)
                .orElseThrow(() -> new IllegalStateException("Payout not found: " + payoutId));

        switch (item.getOperation()) {
            case "CREATE_APPLICATION" -> {
                var resp = mostCreateApplicationService.createFactoringApplication(payout).block();
                if (resp != null) {
                    payout.setMostApplicationNumber(resp.application_number());
                    payout.setMostStatus(resp.status());
                    payout.setMostCreatedAt(LocalDateTime.now());
                    payout.setMostLastCheckedAt(LocalDateTime.now());
                    payoutRepo.save(payout);
                }
            }
            case "UPLOAD_DOCUMENTS" -> {
                // TODO: передать act, invoice, contract из связанных сущностей
                // mostUploadDocumentsService.uploadDocuments(payout, act, invoice, contract).block();
                log.info("UPLOAD_DOCUMENTS processing for payoutId={}", payoutId);
            }
            default -> throw new IllegalArgumentException("Unknown operation: " + item.getOperation());
        }
    }
}
```

### Шаг 4 — Использовать outbox в PayoutFactoringServiceImpl

**Файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/service/PayoutFactoringServiceImpl.java`

Найти место где вызывается `mostCreateApplicationService.createFactoringApplication(payout).block()` (строки ~316-335) и заменить на outbox:

```java
// БЫЛО (прямой вызов):
try {
    var mostResp = mostCreateApplicationService.createFactoringApplication(payout).block();
    payout.setMostApplicationNumber(mostResp.application_number());
    ...
} catch (MostApiException e) {
    throw new ClientAppException("...");
}

// СТАЛО (через outbox):
mostApiOutboxService.scheduleCreateApplication(payout.getId());
log.info("Scheduled MOST CREATE_APPLICATION via outbox payoutId={}", payout.getId());
```

### Шаг 5 — Использовать outbox в FactoringActProcessingService

**Файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/service/FactoringActProcessingService.java`

Найти место где вызывается `mostUploadDocumentsService.uploadDocuments(...)` (строка ~139) и заменить:

```java
// БЫЛО:
mostUploadDocumentsService.uploadDocuments(payout, act, invoice, contract);

// СТАЛО:
mostApiOutboxService.scheduleUploadDocuments(payout.getId());
log.info("Scheduled MOST UPLOAD_DOCUMENTS via outbox payoutId={}", payout.getId());
```

---

## ЗАДАЧА 4 — Endpoint для регистрации Executor в MOST

**Приоритет: КРИТИЧЕСКИЙ | Время: ~1 час**

### Проблема
Нет отдельного endpoint для регистрации перевозчика в MOST.
Сейчас регистрация происходит только неявно при `createPayout()`.
Нужен явный endpoint для кнопки "Подключить быструю оплату".

### Добавить в ExecutorFactoringController

**Файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/api/ExecutorFactoringController.java`

```java
// Добавить инжекцию в конструктор:
private final MostClientRegistrationService mostClientRegistrationService;
private final OrganizationService organizationService;

// Добавить endpoint:
@Operation(
    summary = "Зарегистрировать организацию в MOST для быстрой оплаты",
    description = "Отправляет заявку на подключение факторинга. После одобрения MOST автоматически включит быструю оплату."
)
@PostMapping("/register-most")
public ResponseEntity<MostClientRegistrationResponse> registerInMost() {
    Long orgId = RequestContext.getOrganizationId();
    Organization org = organizationService.getOrganizationById(orgId);
    MostClientRegistrationResponse resp = mostClientRegistrationService.registerExecutor(org);
    return ResponseEntity.ok(resp);
}

// Добавить endpoint для проверки статуса регистрации:
@Operation(summary = "Статус регистрации организации в MOST")
@GetMapping("/most-status")
public ResponseEntity<MostOnboardingStatusResponse> getMostOnboardingStatus() {
    Long orgId = RequestContext.getOrganizationId();
    Organization org = organizationService.getOrganizationById(orgId);

    String status;
    if (org.getMostRegisteredAt() == null) {
        status = "not_registered";
    } else if (!org.isFactoringAllowed()) {
        status = "pending";          // ждём одобрения MOST
    } else if (!factoringService.hasSignedFactoringAgreementForExecutor()) {
        status = "approved";         // одобрен, нужно подписать договор
    } else {
        status = "active";           // всё готово
    }

    return ResponseEntity.ok(new MostOnboardingStatusResponse(
        status,
        org.getMostRegisteredAt(),
        org.isFactoringAllowed()
    ));
}
```

**Новый DTO:**
```java
// MostOnboardingStatusResponse.java
public record MostOnboardingStatusResponse(
    String status,                  // not_registered | pending | approved | active
    LocalDateTime registeredAt,
    boolean factoringAllowed
) {}
```

---

## ЗАДАЧА 5 — Admin toggle для factoring_allowed

**Приоритет: СРЕДНИЙ | Время: ~2 часа**

### Бэкенд

**Файл:** `coube-backend/src/main/java/kz/coube/backend/superadmin/api/SuperAdminOrganizationController.java`

Добавить endpoint:

```java
@PatchMapping("/{id}/factoring")
public ResponseEntity<Void> toggleFactoring(
        @PathVariable Long id,
        @RequestBody ToggleFactoringRequest request) {
    Organization org = organizationService.getOrganizationById(id);
    org.setFactoringAllowed(request.factoringAllowed());
    organizationService.saveOrganization(org);
    log.info("Admin toggled factoring orgId={} allowed={}", id, request.factoringAllowed());
    return ResponseEntity.ok().build();
}

public record ToggleFactoringRequest(boolean factoringAllowed) {}
```

### Фронтенд (coube-admin)

**Файл:** `coube-admin/app/(app)/companies/[id]/page.tsx`

> ⚠️ В файле используется `@nextui-org/react` (старый NextUI). По CLAUDE.md нужно использовать HeroUI (`@heroui/react`). При правке этого блока использовать HeroUI Switch.

Найти блок с `factoringAllowed` чипом и заменить на переключатель:

```tsx
// Добавить state:
const [togglingFactoring, setTogglingFactoring] = useState(false);

const handleToggleFactoring = async () => {
  if (!organization) return;
  setTogglingFactoring(true);
  try {
    await fetch(`/api/super-admin/organizations/${organizationId}/factoring`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ factoringAllowed: !organization.factoringAllowed }),
    });
    await fetchOrganizationDetails(); // перезагрузить данные
  } finally {
    setTogglingFactoring(false);
  }
};

// Заменить read-only чип на:
<div className="flex items-center gap-2">
  <span className="text-sm">Быстрая оплата:</span>
  <Switch
    isSelected={organization.factoringAllowed}
    isDisabled={togglingFactoring}
    onValueChange={handleToggleFactoring}
  >
    {organization.factoringAllowed ? "Включена" : "Отключена"}
  </Switch>
</div>
```

Добавить импорт `Switch` из `@heroui/react`.

Также добавить маршрут в `coube-admin/app/api/super-admin/organizations/[id]/factoring/route.ts`:

```typescript
import { NextRequest, NextResponse } from 'next/server';
import { getAuthHeaders } from '@/lib/auth';

export async function PATCH(req: NextRequest, { params }: { params: { id: string } }) {
  const body = await req.json();
  const res = await fetch(
    `${process.env.BACKEND_URL}/api/v1/super-admin/organizations/${params.id}/factoring`,
    {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json', ...getAuthHeaders() },
      body: JSON.stringify(body),
    }
  );
  return NextResponse.json({}, { status: res.status });
}
```

---

## ЗАДАЧА 6 — Frontend: страница подключения быстрой оплаты

**Приоритет: КРИТИЧЕСКИЙ | Время: ~4 часа**

### Добавить API методы

**Файл:** `coube-frontend/src/api/factoring.ts`

```typescript
executor: {
  // ... существующие методы ...

  // НОВЫЕ:
  registerInMost: () => request('post', 'v1/factoring/executor/register-most', {}),
  getMostOnboardingStatus: () => request('get', 'v1/factoring/executor/most-status', {}),
},
```

### Новый компонент

**Новый файл:** `coube-frontend/src/components/Factoring/FactoringOnboarding.vue`

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import api from '@/api'

const { t } = useI18n()

const status = ref<'not_registered' | 'pending' | 'approved' | 'active' | null>(null)
const limitAmount = ref<number | null>(null)
const isLoading = ref(false)

onMounted(async () => {
  await loadStatus()
})

const loadStatus = async () => {
  try {
    const { data } = await api.factoring.executor.getMostOnboardingStatus()
    status.value = data.status
    if (data.status === 'approved' || data.status === 'active') {
      const { data: limit } = await api.factoring.executor.getMostLimit()
      limitAmount.value = limit.limitAmount
    }
  } catch {
    status.value = 'not_registered'
  }
}

const handleConnect = async () => {
  isLoading.value = true
  try {
    await api.factoring.executor.registerInMost()
    status.value = 'pending'
  } catch (e) {
    // показать ошибку
  } finally {
    isLoading.value = false
  }
}
</script>

<template>
  <div class="factoring-onboarding">

    <!-- Не зарегистрирован -->
    <template v-if="status === 'not_registered'">
      <h3>{{ t('factoring.onboarding.title') }}</h3>
      <p>{{ t('factoring.onboarding.description') }}</p>
      <BaseButton :loading="isLoading" @click="handleConnect">
        {{ t('factoring.onboarding.connect') }}
      </BaseButton>
    </template>

    <!-- На рассмотрении -->
    <template v-else-if="status === 'pending'">
      <div class="factoring-onboarding__pending">
        <span>⏳</span>
        <h3>{{ t('factoring.onboarding.pending.title') }}</h3>
        <p>{{ t('factoring.onboarding.pending.description') }}</p>
      </div>
    </template>

    <!-- Одобрен, нужно подписать договор -->
    <template v-else-if="status === 'approved'">
      <div class="factoring-onboarding__approved">
        <span>✅</span>
        <h3>{{ t('factoring.onboarding.approved.title') }}</h3>
        <p v-if="limitAmount">
          {{ t('factoring.onboarding.limit') }}: {{ limitAmount.toLocaleString() }} ₸
        </p>
        <BaseButton @click="$emit('sign-contract')">
          {{ t('factoring.onboarding.signContract') }}
        </BaseButton>
      </div>
    </template>

    <!-- Активен -->
    <template v-else-if="status === 'active'">
      <div class="factoring-onboarding__active">
        <span>✅</span>
        <h3>{{ t('factoring.onboarding.active.title') }}</h3>
        <p v-if="limitAmount">
          {{ t('factoring.onboarding.limit') }}: {{ limitAmount.toLocaleString() }} ₸
        </p>
      </div>
    </template>

  </div>
</template>
```

### Добавить i18n ключи

**Файл:** `coube-frontend/public/locales/ru.json` (и en/kk/zh)

```json
{
  "factoring": {
    "onboarding": {
      "title": "Быстрая оплата",
      "description": "Получайте деньги сразу после выполнения перевозки, не дожидаясь оплаты от заказчика.",
      "connect": "Подключить быструю оплату",
      "limit": "Доступный лимит",
      "signContract": "Подписать договор",
      "pending": {
        "title": "Заявка на рассмотрении",
        "description": "Обычно занимает 1–2 рабочих дня. Мы уведомим вас когда всё будет готово."
      },
      "approved": {
        "title": "Быстрая оплата одобрена!"
      },
      "active": {
        "title": "Быстрая оплата подключена"
      }
    }
  }
}
```

---

## ЗАДАЧА 7 — Frontend: блокировка кнопки при нулевом лимите

**Приоритет: ВЫСОКИЙ | Время: ~2 часа**

**Файл:** `coube-frontend/src/components/TransportationForm/ExecutorTransportationForm.vue`

### Добавить в `<script setup>`:

```typescript
import { useOrganizationStore } from '@/store/organization'
const { mostClientLimit } = storeToRefs(organizationStore)

// При монтировании компонента если факторинг доступен:
onMounted(async () => {
  if (transportation.value?.isFactoringAllowed) {
    await organizationStore.getMostLimitSafe()
  }
})

const isMostLimitAvailable = computed(() =>
  mostClientLimit.value?.available === true && mostClientLimit.value?.limitAmount != null
)

const mostLimitText = computed(() => {
  if (!mostClientLimit.value) return null
  if (!isMostLimitAvailable.value) return t('factoring.onboarding.pending.description')
  return `${t('factoring.onboarding.limit')}: ${mostClientLimit.value.limitAmount?.toLocaleString()} ₸`
})
```

### В template — найти кнопку "Быстрая оплата" и добавить:

```html
<!-- Показать лимит или предупреждение -->
<p v-if="mostLimitText" class="factoring-limit-text">
  {{ mostLimitText }}
</p>

<!-- Заблокировать кнопку если лимит не одобрен -->
<BaseButton
  :disabled="!isMostLimitAvailable"
  @click="acceptFactoring"
>
  {{ t('factoring.fastPayment') }}
</BaseButton>
```

---

## ЗАДАЧА 8 — Frontend: polling статуса заявки

**Приоритет: ВЫСОКИЙ | Время: ~1.5 часа**

**Файл:** `coube-frontend/src/components/TransportationForm/ExecutorTransportationForm.vue`

### Добавить polling:

```typescript
const POLLING_INTERVAL_MS = 30_000
let pollingTimer: ReturnType<typeof setInterval> | null = null

const ACTIVE_MOST_STATUSES = ['new', 'processing', 'ready_for_issue']

const startPolling = () => {
  if (pollingTimer) return
  pollingTimer = setInterval(async () => {
    if (!factoringPayoutInfo.value?.mostApplicationNumber) return
    const currentStatus = factoringPayoutInfo.value?.mostStatus
    if (!currentStatus || !ACTIVE_MOST_STATUSES.includes(currentStatus)) {
      stopPolling()
      return
    }
    await refreshPayoutStatus()
  }, POLLING_INTERVAL_MS)
}

const stopPolling = () => {
  if (pollingTimer) {
    clearInterval(pollingTimer)
    pollingTimer = null
  }
}

const refreshPayoutStatus = async () => {
  if (!factoringPayoutInfo.value?.id) return
  try {
    const { data } = await api.factoring.payout.getById(factoringPayoutInfo.value.id)
    const prevStatus = factoringPayoutInfo.value.mostStatus
    factoringPayoutInfo.value = data

    // Toast при смене статуса
    if (prevStatus !== data.mostStatus) {
      notifyStatusChange(data.mostStatus)
    }
  } catch (e) {
    // silent fail
  }
}

const notifyStatusChange = (newStatus: string | null) => {
  switch (newStatus) {
    case 'processing':
      toast.info(t('factoring.most.status.processing'))
      break
    case 'ready_for_issue':
      toast.success(t('factoring.most.status.ready_for_issue'))
      break
    case 'issued':
      toast.success(t('factoring.most.paid.title'))
      break
    case 'rejected':
      toast.error(t('factoring.most.rejected.title'))
      break
  }
}

// Запускаем polling когда есть активная заявка
watch(factoringPayoutInfo, (val) => {
  if (val?.mostApplicationNumber && ACTIVE_MOST_STATUSES.includes(val.mostStatus ?? '')) {
    startPolling()
  } else {
    stopPolling()
  }
})

onUnmounted(() => stopPolling())
```

---

## ЗАДАЧА 9 — Frontend: UI для статуса REJECTED

**Приоритет: ВЫСОКИЙ | Время: ~1 час**

**Файл:** `coube-frontend/src/components/TransportationForm/ExecutorTransportationForm.vue`

В template найти блок с отображением `factoringPayoutInfo` и добавить обработку REJECTED:

```html
<!-- Блок REJECTED -->
<div
  v-if="factoringPayoutInfo?.mostStatus === 'rejected' || factoringPayoutInfo?.status === 'REJECTED'"
  class="factoring-rejected-block"
>
  <BaseIcon name="error" />
  <div>
    <h4>{{ t('factoring.most.rejected.title') }}</h4>
    <p>{{ t('factoring.most.rejected.description') }}</p>
  </div>
</div>
```

```scss
.factoring-rejected-block {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px;
  background: #FFF0F0;
  border: 1px solid #EC1B2E;
  border-radius: 8px;
  color: #EC1B2E;
}
```

---

---

## ЗАДАЧА 10 — Автоматизация онбординга заказчика в MOST

**Приоритет: ВЫСОКИЙ | Время: ~3 часа**

### Проблема

У заказчика сейчас:
- `factoringAllowed` — включается **вручную** менеджером через БД
- Нет промежуточных состояний: кнопка "Подключить" либо есть (если `factoring-enabled = true`), либо нет
- После `POST /factoring/customer/client` — заказчик не видит статус "На рассмотрении"
- `MostClientPollingService` (реализован для перевозчика) охватывает **всех** у кого `mostRegisteredAt != null and factoringAllowed = false` — включая заказчиков, но для заказчика нужно ещё установить `mostRegisteredAt` при регистрации (сейчас это делает `MostClientRegistrationService.registerCustomer()` ✅)

### Что нужно сделать

#### Шаг 1 — Бэкенд: endpoint статуса для заказчика

**Файл:** `coube-backend/src/main/java/kz/coube/backend/factoring/api/CustomerFactoringController.java`

```java
@GetMapping("/most-status")
public ResponseEntity<MostOnboardingStatusResponse> getMostOnboardingStatus() {
    Long orgId = RequestContext.getOrganizationId();
    Organization org = organizationService.getOrganizationById(orgId);

    String status;
    if (org.getMostRegisteredAt() == null) {
        status = "not_registered";
    } else if (!org.isFactoringAllowed()) {
        status = "pending";     // зарегистрировались, ждём одобрения MOST
    } else {
        status = "active";      // одобрено, можно создавать перевозки с факторингом
    }

    return ResponseEntity.ok(new MostOnboardingStatusResponse(
        status,
        org.getMostRegisteredAt(),
        org.isFactoringAllowed()
    ));
}
```

> `MostOnboardingStatusResponse` — тот же DTO что и для executor (уже создан в ЗАДАЧА 4)

#### Шаг 2 — Фронтенд: добавить API метод

**Файл:** `coube-frontend/src/api/factoring.ts`

```typescript
customer: {
  // ... существующие методы ...
  getMostOnboardingStatus: () => request('get', 'v1/factoring/customer/most-status', {}),
}
```

#### Шаг 3 — Фронтенд: обновить OrganizationContainer

**Файл:** `coube-frontend/src/components/Organization/OrganizationContainer/OrganizationContainer.vue`

Сейчас логика:
- `isFactoringAvailable = false` → тост "Обратитесь в тех поддержку"
- `isFactoringAvailable = true` → кнопка "Подключить" → `POST /customer/client`

Нужно заменить на 3 состояния используя `GET /customer/most-status`:

```typescript
// Добавить в script setup:
const mostCustomerStatus = ref<'not_registered' | 'pending' | 'active' | null>(null)

onMounted(async () => {
  // ... существующая логика ...
  try {
    const { data } = await api.factoring.customer.getMostOnboardingStatus()
    mostCustomerStatus.value = data.status
  } catch {
    mostCustomerStatus.value = 'not_registered'
  }
})
```

В template заменить блок с кнопкой "Подключить":

```html
<!-- Не зарегистрирован — показываем кнопку -->
<template v-if="mostCustomerStatus === 'not_registered'">
  <BaseButton @click="registerMostClientForCustomer">
    {{ $t('factoring.organization.action.applyFastPayment') }}
  </BaseButton>
</template>

<!-- На рассмотрении -->
<template v-else-if="mostCustomerStatus === 'pending'">
  <div class="organization-factoring-label pending">
    ⏳ {{ $t('factoring.organization.status.pendingConfirmation') }}
  </div>
</template>

<!-- Активен -->
<template v-else-if="mostCustomerStatus === 'active'">
  <div class="organization-factoring-label success">
    ✅ {{ $t('factoring.organization.status.available') }}
  </div>
</template>
```

### Что НЕ нужно менять

- `MostClientPollingService` — уже покрывает заказчиков (ищет все орги с `mostRegisteredAt != null and factoringAllowed = false`)
- `POST /factoring/customer/client` — уже работает, устанавливает `mostRegisteredAt`
- Логику создания перевозок с факторингом — она завязана на `factoringAllowed` которое уже ставится автоматически

---

## Порядок выполнения

```
День 1:
  ✦ ЗАДАЧА 1 — Баг URL OTP (5 мин)
  ✦ ЗАДАЧА 4 — Бэкенд endpoint /register-most и /most-status (1 ч)
  ✦ ЗАДАЧА 2 — MostClientPollingService (2 ч)

День 2:
  ✦ ЗАДАЧА 3 — MostApiOutboxService (6 ч)

День 3:
  ✦ ЗАДАЧА 6 — FactoringOnboarding.vue + i18n (4 ч)
  ✦ ЗАДАЧА 7 — Блокировка кнопки лимитом (2 ч)

День 4:
  ✦ ЗАДАЧА 8 — Polling на фронте (1.5 ч)
  ✦ ЗАДАЧА 9 — UI REJECTED (1 ч)
  ✦ ЗАДАЧА 5 — Admin toggle (2 ч)
```

---

## Итоговая таблица

| # | Задача | Приоритет | Где | Файлы |
|---|---|---|---|---|
| 1 | Баг URL OTP | 🔴 | Frontend | `api/factoring.ts` |
| 2 | Polling клиентов + авто-включение | 🔴 | Backend | Новый `MostClientPollingService.java` |
| 3 | MostApiOutboxService | 🔴 | Backend | Новые entity/repo/service + изменение 2 сервисов |
| 4 | Endpoint /register-most + /most-status | 🔴 | Backend | `ExecutorFactoringController.java` |
| 5 | Admin toggle factoring | 🟡 | Backend + Admin | `SuperAdminOrganizationController.java` + `page.tsx` |
| 6 | Страница онбординга | 🔴 | Frontend | Новый `FactoringOnboarding.vue` + i18n |
| 7 | Блокировка кнопки лимитом | 🟠 | Frontend | `ExecutorTransportationForm.vue` |
| 8 | Polling статуса на фронте | 🟠 | Frontend | `ExecutorTransportationForm.vue` |
| 9 | UI для REJECTED | 🟠 | Frontend | `ExecutorTransportationForm.vue` |
| 10 | Автоматизация онбординга заказчика | 🟠 | Backend + Frontend | `CustomerFactoringController.java` + `OrganizationContainer.vue` |
