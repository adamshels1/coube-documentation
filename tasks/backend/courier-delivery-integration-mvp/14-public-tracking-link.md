# 14. Публичная ссылка отслеживания курьера для заказчика

**Дата создания**: 2025-11-10
**Статус**: TO DO
**Приоритет**: MEDIUM
**Автор**: Ali (Product Requirements)

---

## 📋 Проблема

**Бизнес-кейс:**
Заказчик хочет знать:
- Где сейчас находится курьер?
- Когда примерно приедет?
- Кто курьер и как с ним связаться?

**Текущая ситуация:**
- Заказчик не видит местоположение курьера
- Нет прозрачности процесса доставки
- Заказчик звонит логисту с вопросами "где курьер?"

**Решение:**
Логист может поделиться публичной ссылкой отслеживания с заказчиком, где будет:
- 🗺️ Карта с real-time позицией курьера
- 👤 Контакты курьера (ФИО, телефон)
- 📍 Маршрут с точками доставки
- ⏱️ ETA (ожидаемое время прибытия)
- 📊 Прогресс выполнения

---

## 🎯 Решение

### Архитектура

```
┌─────────────┐                    ┌──────────────┐
│   Логист    │──── генерирует ───>│ Tracking URL │
│  (Web UI)   │     токен          │              │
└─────────────┘                    └──────┬───────┘
                                          │
                                   shares │
                                          ↓
┌─────────────┐                    ┌──────────────┐
│  Заказчик   │<──── открывает ────│ Public Page  │
│  (Browser)  │      ссылку        │  /tracking/  │
└─────────────┘                    └──────┬───────┘
                                          │
                                   polling │ 15-30s
                                          ↓
                                   ┌──────────────┐
                                   │ Public API   │
                                   │ (no auth)    │
                                   └──────┬───────┘
                                          │
                                          ↓
                                   ┌──────────────┐
                                   │   Database   │
                                   │ transportation│
                                   └──────────────┘
```

---

## 🗄️ Изменения в БД

### 1. Добавить поле `public_tracking_token` в таблицу `transportation`

**Migration:** `V20251110000000__add_public_tracking_token_to_transportation.sql`

```sql
-- Добавить поле для публичного токена отслеживания
ALTER TABLE applications.transportation
ADD COLUMN public_tracking_token UUID DEFAULT NULL;

-- Уникальный индекс для быстрого поиска
CREATE UNIQUE INDEX idx_transportation_tracking_token
ON applications.transportation (public_tracking_token)
WHERE public_tracking_token IS NOT NULL;

-- Комментарий
COMMENT ON COLUMN applications.transportation.public_tracking_token
IS 'Уникальный токен для публичного отслеживания курьера без авторизации';
```

---

## 🔧 Backend изменения

### 1. Entity: Добавить поле в `Transportation`

**File:** `coube-backend/src/main/java/kz/coube/backend/applications/entity/Transportation.java`

```java
@Entity
@Table(name = "transportation", schema = "applications")
public class Transportation extends BaseIdEntity {

    // ... existing fields

    @Column(name = "public_tracking_token", unique = true)
    private UUID publicTrackingToken;

    // ... existing methods
}
```

---

### 2. Repository: Добавить метод поиска по токену

**File:** `coube-backend/src/main/java/kz/coube/backend/applications/repository/TransportationRepository.java`

```java
@Repository
public interface TransportationRepository extends JpaRepository<Transportation, Long> {

    // ... existing methods

    /**
     * Найти transportation по публичному токену отслеживания
     */
    Optional<Transportation> findByPublicTrackingToken(UUID token);
}
```

---

### 3. Service: Генерация и управление токенами

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/service/PublicTrackingService.java`

```java
package kz.coube.backend.courier.service;

import kz.coube.backend.applications.TransportationService;
import kz.coube.backend.applications.entity.CourierRouteOrder;
import kz.coube.backend.applications.entity.Transportation;
import kz.coube.backend.common.exception.ResourceNotFoundException;
import kz.coube.backend.courier.dto.PublicTrackingResponse;
import kz.coube.backend.dictionaries.enumeration.TransportationType;
import kz.coube.backend.organization.model.Employee;
import kz.coube.backend.route.entity.CargoLoadingHistory;
import kz.coube.backend.transport.entity.Vehicle;
import kz.coube.backend.transport.entity.VehicleLatestLocation;
import kz.coube.backend.transport.repository.VehicleLatestLocationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class PublicTrackingService {

    private final TransportationService transportationService;
    private final VehicleLatestLocationRepository vehicleLatestLocationRepository;
    private final CourierRouteOrderService courierRouteOrderService;

    /**
     * Генерировать или получить существующий токен для transportation
     */
    @Transactional
    public String generateOrGetTrackingToken(Long transportationId) {
        Transportation transportation = transportationService.findById(transportationId);

        // Проверка: только для COURIER_DELIVERY
        if (transportation.getTransportationType() != TransportationType.COURIER_DELIVERY) {
            throw new IllegalStateException("Public tracking is only available for courier delivery");
        }

        // Если токен уже есть - вернуть его
        if (transportation.getPublicTrackingToken() != null) {
            return transportation.getPublicTrackingToken().toString();
        }

        // Генерируем новый токен
        UUID token = UUID.randomUUID();
        transportation.setPublicTrackingToken(token);
        transportationService.save(transportation);

        log.info("Generated public tracking token for transportation {}: {}",
                 transportationId, token);

        return token.toString();
    }

    /**
     * Получить данные для публичного отслеживания (БЕЗ авторизации)
     */
    @Transactional(readOnly = true)
    public PublicTrackingResponse getTrackingData(String tokenStr) {
        UUID token;
        try {
            token = UUID.fromString(tokenStr);
        } catch (IllegalArgumentException e) {
            throw new ResourceNotFoundException("Invalid tracking token");
        }

        // Найти transportation по токену
        Transportation transportation = transportationService
            .findByPublicTrackingToken(token)
            .orElseThrow(() -> new ResourceNotFoundException("Tracking not found"));

        // Получить текущую позицию курьера
        PublicTrackingResponse.CourierLocation location = null;
        if (transportation.getTransport() != null &&
            transportation.getTransport().getVehicle() != null) {

            Vehicle vehicle = transportation.getTransport().getVehicle();
            VehicleLatestLocation latestLocation = vehicleLatestLocationRepository
                .findById(vehicle.getId())
                .orElse(null);

            if (latestLocation != null && latestLocation.getLocation() != null) {
                location = PublicTrackingResponse.CourierLocation.builder()
                    .latitude(latestLocation.getLocation().getY())
                    .longitude(latestLocation.getLocation().getX())
                    .timestamp(latestLocation.getTimestamp())
                    .build();
            }
        }

        // Получить информацию о курьере
        PublicTrackingResponse.CourierInfo courierInfo = getCourierInfo(transportation);

        // Получить точки маршрута
        List<PublicTrackingResponse.RoutePoint> routePoints = getRoutePoints(transportation);

        // Рассчитать прогресс
        PublicTrackingResponse.Progress progress = calculateProgress(transportation);

        // Рассчитать ETA
        LocalDateTime eta = calculateETA(transportation, location);

        return PublicTrackingResponse.builder()
            .transportationId(transportation.getId())
            .status(transportation.getStatus().name())
            .statusDescription(getStatusDescription(transportation.getStatus()))
            .courierLocation(location)
            .courierInfo(courierInfo)
            .routePoints(routePoints)
            .progress(progress)
            .eta(eta)
            .createdAt(transportation.getCreatedAt())
            .build();
    }

    private PublicTrackingResponse.CourierInfo getCourierInfo(Transportation transportation) {
        Employee courier = transportation.getExecutorEmployee();
        if (courier == null && transportation.getTransport() != null) {
            // Попытка получить курьера через Transport
            // (логика из DriverService.driverForTransportation)
            courier = null; // TODO: implement if needed
        }

        if (courier == null) {
            return PublicTrackingResponse.CourierInfo.builder()
                .fullName("Курьер не назначен")
                .phone(null)
                .build();
        }

        return PublicTrackingResponse.CourierInfo.builder()
            .fullName(courier.getFullName())
            .phone(courier.getPhone())
            .build();
    }

    private List<PublicTrackingResponse.RoutePoint> getRoutePoints(Transportation transportation) {
        List<CargoLoadingHistory> cargoLoadings = transportation.getCargoLoadings();
        if (cargoLoadings == null || cargoLoadings.isEmpty()) {
            return List.of();
        }

        return cargoLoadings.stream()
            .filter(cl -> !Boolean.TRUE.equals(cl.getIsCourierWarehouse())) // Скрыть склады
            .map(cl -> {
                // Получить заказы для этой точки
                List<CourierRouteOrder> orders = courierRouteOrderService.getByCargoLoadingHistory(cl);

                return PublicTrackingResponse.RoutePoint.builder()
                    .orderNum(cl.getOrderNum())
                    .address(cl.getAddress())
                    .contactName(cl.getContactName())
                    .contactPhone(cl.getContactNumber())
                    .isCompleted(cl.getIsActive() == null || !cl.getIsActive())
                    .isCurrentPoint(Boolean.TRUE.equals(cl.getIsActive()))
                    .orderCount(orders.size())
                    .build();
            })
            .collect(Collectors.toList());
    }

    private PublicTrackingResponse.Progress calculateProgress(Transportation transportation) {
        List<CargoLoadingHistory> cargoLoadings = transportation.getCargoLoadings();
        if (cargoLoadings == null || cargoLoadings.isEmpty()) {
            return PublicTrackingResponse.Progress.builder()
                .totalPoints(0)
                .completedPoints(0)
                .currentPoint(0)
                .build();
        }

        long completed = cargoLoadings.stream()
            .filter(cl -> cl.getIsActive() == null || !cl.getIsActive())
            .count();

        int currentPoint = cargoLoadings.stream()
            .filter(cl -> Boolean.TRUE.equals(cl.getIsActive()))
            .findFirst()
            .map(CargoLoadingHistory::getOrderNum)
            .orElse(cargoLoadings.size());

        return PublicTrackingResponse.Progress.builder()
            .totalPoints(cargoLoadings.size())
            .completedPoints((int) completed)
            .currentPoint(currentPoint)
            .build();
    }

    private LocalDateTime calculateETA(Transportation transportation,
                                       PublicTrackingResponse.CourierLocation location) {
        // Простая оценка: если активная точка существует
        CargoLoadingHistory activePoint = transportation.getCargoLoadings().stream()
            .filter(cl -> Boolean.TRUE.equals(cl.getIsActive()))
            .findFirst()
            .orElse(null);

        if (activePoint == null) {
            return null; // Маршрут завершен
        }

        // TODO: Реализовать расчет ETA на основе:
        // - Текущей позиции курьера
        // - Координат активной точки
        // - Средней скорости движения
        // - Пробок (если есть интеграция)

        // Временная заглушка: +30 минут от текущего времени
        return LocalDateTime.now().plusMinutes(30);
    }

    private String getStatusDescription(kz.coube.backend.dictionaries.enumeration.TransportationStatus status) {
        return switch (status) {
            case DRIVER_ACCEPTED -> "Курьер принял заказ";
            case ON_THE_WAY -> "Курьер в пути";
            case AWAITING_RETURN_CONFIRMATION -> "Ожидает подтверждения возврата";
            case FINISHED -> "Доставка завершена";
            default -> status.name();
        };
    }
}
```

---

### 4. DTO: Response для публичного API

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/PublicTrackingResponse.java`

```java
package kz.coube.backend.courier.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;

import java.time.LocalDateTime;
import java.util.List;

@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PublicTrackingResponse(
    Long transportationId,
    String status,
    String statusDescription,
    CourierLocation courierLocation,
    CourierInfo courierInfo,
    List<RoutePoint> routePoints,
    Progress progress,
    LocalDateTime eta,
    LocalDateTime createdAt
) {
    @Builder
    public record CourierLocation(
        Double latitude,
        Double longitude,
        LocalDateTime timestamp
    ) {}

    @Builder
    public record CourierInfo(
        String fullName,
        String phone
    ) {}

    @Builder
    public record RoutePoint(
        Integer orderNum,
        String address,
        String contactName,
        String contactPhone,
        Boolean isCompleted,
        Boolean isCurrentPoint,
        Integer orderCount
    ) {}

    @Builder
    public record Progress(
        Integer totalPoints,
        Integer completedPoints,
        Integer currentPoint
    ) {}
}
```

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/GenerateTrackingLinkResponse.java`

```java
package kz.coube.backend.courier.dto;

import lombok.Builder;

@Builder
public record GenerateTrackingLinkResponse(
    Long transportationId,
    String trackingToken,
    String trackingUrl,
    String qrCodeUrl  // Опционально: URL для QR-кода
) {}
```

---

### 5. Controller: Публичный API (без авторизации)

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/api/PublicTrackingController.java`

```java
package kz.coube.backend.courier.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import kz.coube.backend.courier.dto.PublicTrackingResponse;
import kz.coube.backend.courier.service.PublicTrackingService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.concurrent.TimeUnit;

@RestController
@RequestMapping("/api/v1/public/tracking")
@RequiredArgsConstructor
@Tag(name = "Public Tracking", description = "Публичное API отслеживания курьера (без авторизации)")
public class PublicTrackingController {

    private final PublicTrackingService publicTrackingService;

    @GetMapping("/{token}")
    @Operation(
        summary = "Получить данные отслеживания курьера по токену",
        description = "Публичный endpoint без авторизации. Возвращает позицию курьера, контакты, маршрут, ETA."
    )
    public ResponseEntity<PublicTrackingResponse> getTracking(
        @PathVariable String token
    ) {
        PublicTrackingResponse response = publicTrackingService.getTrackingData(token);

        // Кеширование на 15 секунд (для polling)
        return ResponseEntity.ok()
            .cacheControl(CacheControl.maxAge(15, TimeUnit.SECONDS))
            .body(response);
    }
}
```

---

### 6. Controller: API для логиста (генерация ссылки)

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/api/CourierTrackingManagementController.java`

```java
package kz.coube.backend.courier.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import kz.coube.backend.auth.annotations.AuthorizationRequired;
import kz.coube.backend.auth.roles.KeycloakRole;
import kz.coube.backend.courier.dto.GenerateTrackingLinkResponse;
import kz.coube.backend.courier.service.PublicTrackingService;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/courier/tracking")
@RequiredArgsConstructor
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN})
@Tag(name = "Courier Tracking Management", description = "API управления публичными ссылками отслеживания")
public class CourierTrackingManagementController {

    private final PublicTrackingService publicTrackingService;

    @Value("${app.frontend.url:https://coube.kz}")
    private String frontendUrl;

    @PostMapping("/transportations/{transportationId}/generate-link")
    @Operation(summary = "Сгенерировать публичную ссылку отслеживания для заказчика")
    public ResponseEntity<GenerateTrackingLinkResponse> generateTrackingLink(
        @PathVariable Long transportationId
    ) {
        String token = publicTrackingService.generateOrGetTrackingToken(transportationId);
        String trackingUrl = frontendUrl + "/tracking/" + token;

        GenerateTrackingLinkResponse response = GenerateTrackingLinkResponse.builder()
            .transportationId(transportationId)
            .trackingToken(token)
            .trackingUrl(trackingUrl)
            .qrCodeUrl(null) // TODO: Добавить генерацию QR-кода
            .build();

        return ResponseEntity.ok(response);
    }
}
```

---

### 7. Service: Добавить метод в `TransportationService`

**File:** `coube-backend/src/main/java/kz/coube/backend/applications/TransportationService.java`

```java
@Service
public class TransportationService {

    // ... existing methods

    /**
     * Найти transportation по публичному токену отслеживания
     */
    public Optional<Transportation> findByPublicTrackingToken(UUID token) {
        return transportationRepository.findByPublicTrackingToken(token);
    }
}
```

---

### 8. Security: Rate Limiting для публичного API

**File:** `coube-backend/src/main/java/kz/coube/backend/config/RateLimitingConfig.java`

```java
package kz.coube.backend.config;

import io.github.bucket4j.Bandwidth;
import io.github.bucket4j.Bucket;
import io.github.bucket4j.Refill;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Configuration
public class RateLimitingConfig {

    private final Map<String, Bucket> cache = new ConcurrentHashMap<>();

    /**
     * Rate limiter для публичного tracking API
     * Лимит: 100 запросов в минуту на IP адрес
     */
    public Bucket resolveBucket(String key) {
        return cache.computeIfAbsent(key, k -> createNewBucket());
    }

    private Bucket createNewBucket() {
        Bandwidth limit = Bandwidth.classic(100, Refill.intervally(100, Duration.ofMinutes(1)));
        return Bucket.builder()
            .addLimit(limit)
            .build();
    }
}
```

**File:** `coube-backend/src/main/java/kz/coube/backend/config/RateLimitInterceptor.java`

```java
package kz.coube.backend.config;

import io.github.bucket4j.Bucket;
import io.github.bucket4j.ConsumptionProbe;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
@RequiredArgsConstructor
@Slf4j
public class RateLimitInterceptor implements HandlerInterceptor {

    private final RateLimitingConfig rateLimitingConfig;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String key = getClientIP(request);
        Bucket bucket = rateLimitingConfig.resolveBucket(key);
        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (probe.isConsumed()) {
            response.addHeader("X-Rate-Limit-Remaining", String.valueOf(probe.getRemainingTokens()));
            return true;
        } else {
            long waitForRefill = probe.getNanosToWaitForRefill() / 1_000_000_000;
            response.addHeader("X-Rate-Limit-Retry-After-Seconds", String.valueOf(waitForRefill));
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value(), "Too many requests. Please try again later.");
            return false;
        }
    }

    private String getClientIP(HttpServletRequest request) {
        String xfHeader = request.getHeader("X-Forwarded-For");
        if (xfHeader == null) {
            return request.getRemoteAddr();
        }
        return xfHeader.split(",")[0];
    }
}
```

**File:** `coube-backend/src/main/java/kz/coube/backend/config/WebMvcConfig.java`

```java
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Autowired
    private RateLimitInterceptor rateLimitInterceptor;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(rateLimitInterceptor)
            .addPathPatterns("/api/v1/public/**"); // Только для публичных endpoints
    }
}
```

---

## 🎨 Frontend изменения

### 1. Публичная страница отслеживания

**File:** `coube-frontend/src/pages/PublicTrackingPage.vue`

```vue
<template>
  <div class="public-tracking-page">
    <!-- Header -->
    <header class="tracking-header">
      <div class="container">
        <img src="@/assets/logo.png" alt="Coube" class="logo" />
        <h1>{{ $t('tracking.title') }}</h1>
      </div>
    </header>

    <!-- Loading -->
    <div v-if="loading" class="loading-container">
      <LoadingSpinner />
      <p>{{ $t('tracking.loading') }}</p>
    </div>

    <!-- Error -->
    <div v-else-if="error" class="error-container">
      <ErrorIcon />
      <h2>{{ $t('tracking.error.title') }}</h2>
      <p>{{ error }}</p>
    </div>

    <!-- Content -->
    <div v-else class="tracking-content">
      <!-- Map -->
      <div class="map-container">
        <YandexMap
          :courier-location="trackingData.courierLocation"
          :route-points="trackingData.routePoints"
          :zoom="12"
        />
      </div>

      <!-- Info Panel -->
      <div class="info-panel">
        <!-- Status -->
        <div class="status-card">
          <StatusIcon :status="trackingData.status" />
          <h2>{{ trackingData.statusDescription }}</h2>
          <p v-if="trackingData.eta" class="eta">
            {{ $t('tracking.eta') }}: {{ formatETA(trackingData.eta) }}
          </p>
        </div>

        <!-- Courier Info -->
        <div class="courier-card">
          <h3>{{ $t('tracking.courier') }}</h3>
          <div class="courier-details">
            <UserIcon />
            <div>
              <p class="name">{{ trackingData.courierInfo.fullName }}</p>
              <a
                v-if="trackingData.courierInfo.phone"
                :href="`tel:${trackingData.courierInfo.phone}`"
                class="phone"
              >
                <PhoneIcon />
                {{ trackingData.courierInfo.phone }}
              </a>
            </div>
          </div>
        </div>

        <!-- Progress -->
        <div class="progress-card">
          <h3>{{ $t('tracking.progress') }}</h3>
          <div class="progress-bar">
            <div
              class="progress-fill"
              :style="{ width: progressPercentage + '%' }"
            ></div>
          </div>
          <p>
            {{ trackingData.progress.completedPoints }} /
            {{ trackingData.progress.totalPoints }}
            {{ $t('tracking.pointsCompleted') }}
          </p>
        </div>

        <!-- Route Points -->
        <div class="route-points-card">
          <h3>{{ $t('tracking.routePoints') }}</h3>
          <ul class="route-list">
            <li
              v-for="point in trackingData.routePoints"
              :key="point.orderNum"
              :class="{
                completed: point.isCompleted,
                current: point.isCurrentPoint,
              }"
            >
              <span class="point-number">{{ point.orderNum }}</span>
              <div class="point-info">
                <p class="address">{{ point.address }}</p>
                <p v-if="point.contactName" class="contact">
                  {{ point.contactName }}
                </p>
              </div>
              <CheckIcon v-if="point.isCompleted" class="check-icon" />
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { getPublicTracking } from '@/api/publicTracking'
import type { PublicTrackingResponse } from '@/types/tracking'

const route = useRoute()
const { t } = useI18n()

const token = route.params.token as string
const trackingData = ref<PublicTrackingResponse | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)
let pollingInterval: number | null = null

const progressPercentage = computed(() => {
  if (!trackingData.value) return 0
  const { completedPoints, totalPoints } = trackingData.value.progress
  return (completedPoints / totalPoints) * 100
})

const fetchTrackingData = async () => {
  try {
    const data = await getPublicTracking(token)
    trackingData.value = data
    error.value = null
  } catch (err: any) {
    error.value = err.message || t('tracking.error.default')
  } finally {
    loading.value = false
  }
}

const formatETA = (eta: string) => {
  const date = new Date(eta)
  return date.toLocaleTimeString('ru-RU', {
    hour: '2-digit',
    minute: '2-digit',
  })
}

onMounted(() => {
  // Первоначальная загрузка
  fetchTrackingData()

  // Polling каждые 15 секунд
  pollingInterval = window.setInterval(fetchTrackingData, 15000)
})

onUnmounted(() => {
  if (pollingInterval) {
    clearInterval(pollingInterval)
  }
})
</script>

<style scoped lang="scss">
.public-tracking-page {
  min-height: 100vh;
  background: #f5f5f5;
}

.tracking-header {
  background: white;
  padding: 1rem 0;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);

  .container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 1rem;
    display: flex;
    align-items: center;
    gap: 1rem;

    .logo {
      height: 40px;
    }
  }
}

.tracking-content {
  display: grid;
  grid-template-columns: 2fr 1fr;
  gap: 1rem;
  padding: 1rem;
  max-width: 1400px;
  margin: 0 auto;

  @media (max-width: 768px) {
    grid-template-columns: 1fr;
  }
}

.map-container {
  height: calc(100vh - 120px);
  background: white;
  border-radius: 8px;
  overflow: hidden;
}

.info-panel {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  overflow-y: auto;
  height: calc(100vh - 120px);

  > div {
    background: white;
    padding: 1.5rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
  }
}

.courier-card {
  .courier-details {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-top: 1rem;

    .name {
      font-weight: 600;
      font-size: 1.1rem;
    }

    .phone {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      color: #007bff;
      text-decoration: none;
      font-size: 1.1rem;
      padding: 0.5rem 1rem;
      border: 1px solid #007bff;
      border-radius: 4px;
      margin-top: 0.5rem;

      &:hover {
        background: #007bff;
        color: white;
      }
    }
  }
}

.progress-card {
  .progress-bar {
    height: 8px;
    background: #e0e0e0;
    border-radius: 4px;
    overflow: hidden;
    margin: 1rem 0;

    .progress-fill {
      height: 100%;
      background: #4caf50;
      transition: width 0.3s ease;
    }
  }
}

.route-list {
  list-style: none;
  padding: 0;
  margin: 0;

  li {
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 1rem;
    border-left: 3px solid #e0e0e0;
    margin-bottom: 0.5rem;

    &.completed {
      border-color: #4caf50;
      opacity: 0.7;
    }

    &.current {
      border-color: #007bff;
      background: #f0f8ff;
    }

    .point-number {
      font-weight: 600;
      font-size: 1.2rem;
      min-width: 30px;
    }

    .point-info {
      flex: 1;

      .address {
        font-weight: 500;
      }

      .contact {
        color: #666;
        font-size: 0.9rem;
      }
    }

    .check-icon {
      color: #4caf50;
    }
  }
}
</style>
```

---

### 2. API клиент

**File:** `coube-frontend/src/api/publicTracking.ts`

```typescript
import axios from 'axios'
import type { PublicTrackingResponse } from '@/types/tracking'

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'https://api.coube.kz'

/**
 * Получить данные публичного отслеживания (БЕЗ авторизации)
 */
export const getPublicTracking = async (
  token: string
): Promise<PublicTrackingResponse> => {
  const response = await axios.get(
    `${API_BASE_URL}/api/v1/public/tracking/${token}`
  )
  return response.data
}

/**
 * Сгенерировать ссылку отслеживания (для логиста, с авторизацией)
 */
export const generateTrackingLink = async (
  transportationId: number
): Promise<{ trackingUrl: string; trackingToken: string }> => {
  const response = await axios.post(
    `${API_BASE_URL}/api/v1/courier/tracking/transportations/${transportationId}/generate-link`,
    {},
    {
      headers: {
        Authorization: `Bearer ${localStorage.getItem('token')}`,
      },
    }
  )
  return response.data
}
```

---

### 3. Кнопка "Поделиться ссылкой" в деталях заявки (для логиста)

**File:** `coube-frontend/src/components/TransportationDetails.vue`

```vue
<template>
  <div class="transportation-details">
    <!-- Existing content -->

    <!-- Share Tracking Link Button -->
    <button
      v-if="transportation.transportationType === 'COURIER_DELIVERY'"
      @click="shareTrackingLink"
      class="btn btn-primary"
    >
      <ShareIcon />
      {{ $t('transportation.shareTrackingLink') }}
    </button>

    <!-- Modal with tracking link -->
    <Modal v-if="showTrackingModal" @close="showTrackingModal = false">
      <h2>{{ $t('transportation.trackingLink') }}</h2>
      <div class="tracking-link-content">
        <input
          ref="linkInput"
          :value="trackingUrl"
          readonly
          class="tracking-input"
        />
        <button @click="copyToClipboard" class="btn btn-secondary">
          <CopyIcon />
          {{ $t('common.copy') }}
        </button>
      </div>
      <p class="hint">{{ $t('transportation.shareHint') }}</p>
    </Modal>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { generateTrackingLink } from '@/api/publicTracking'
import { useNotification } from '@/composables/useNotification'

const props = defineProps<{
  transportation: Transportation
}>()

const { t } = useI18n()
const { showSuccess, showError } = useNotification()

const showTrackingModal = ref(false)
const trackingUrl = ref('')
const linkInput = ref<HTMLInputElement | null>(null)

const shareTrackingLink = async () => {
  try {
    const response = await generateTrackingLink(props.transportation.id)
    trackingUrl.value = response.trackingUrl
    showTrackingModal.value = true
  } catch (error) {
    showError(t('transportation.error.generateLink'))
  }
}

const copyToClipboard = () => {
  if (linkInput.value) {
    linkInput.value.select()
    document.execCommand('copy')
    showSuccess(t('common.copiedToClipboard'))
  }
}
</script>
```

---

## 🧪 Testing Checklist

### Backend Tests

- [ ] `PublicTrackingService.generateOrGetTrackingToken()` - генерация токена
- [ ] `PublicTrackingService.getTrackingData()` - получение данных по токену
- [ ] Public API endpoint `/api/v1/public/tracking/{token}` - без авторизации
- [ ] Rate limiting - 100 req/min на IP
- [ ] Invalid token → 404 Not Found
- [ ] Expired token (если TTL реализован)
- [ ] Только COURIER_DELIVERY может генерировать токены

### Frontend Tests

- [ ] Публичная страница `/tracking/{token}` открывается
- [ ] Карта отображается с позицией курьера
- [ ] Контакты курьера отображаются
- [ ] Polling каждые 15 секунд работает
- [ ] Прогресс-бар обновляется
- [ ] Кнопка "Позвонить" работает на мобильных
- [ ] Responsive дизайн (мобильная версия)

### Integration Tests

- [ ] E2E: Логист генерирует ссылку → заказчик открывает → видит курьера
- [ ] Копирование ссылки в буфер обмена
- [ ] Обновление данных в real-time

---

## 📊 Example Request/Response

### Request 1: Логист генерирует ссылку

```http
POST /api/v1/courier/tracking/transportations/12345/generate-link
Authorization: Bearer {logist-token}
```

**Response:**
```json
{
  "transportationId": 12345,
  "trackingToken": "550e8400-e29b-41d4-a716-446655440000",
  "trackingUrl": "https://coube.kz/tracking/550e8400-e29b-41d4-a716-446655440000",
  "qrCodeUrl": null
}
```

---

### Request 2: Заказчик открывает ссылку (публичный API)

```http
GET /api/v1/public/tracking/550e8400-e29b-41d4-a716-446655440000
```

**Response:**
```json
{
  "transportationId": 12345,
  "status": "ON_THE_WAY",
  "statusDescription": "Курьер в пути",
  "courierLocation": {
    "latitude": 51.1605,
    "longitude": 71.4704,
    "timestamp": "2025-11-10T14:30:00Z"
  },
  "courierInfo": {
    "fullName": "Иванов Иван Иванович",
    "phone": "+77012345678"
  },
  "routePoints": [
    {
      "orderNum": 1,
      "address": "г. Астана, ул. Кабанбай батыра 1",
      "contactName": "Петров Петр",
      "contactPhone": "+77012345679",
      "isCompleted": true,
      "isCurrentPoint": false,
      "orderCount": 2
    },
    {
      "orderNum": 2,
      "address": "г. Астана, ул. Достык 5",
      "contactName": "Сидоров Сидор",
      "contactPhone": "+77012345680",
      "isCompleted": false,
      "isCurrentPoint": true,
      "orderCount": 1
    },
    {
      "orderNum": 3,
      "address": "г. Астана, ул. Абая 10",
      "contactName": "Казахов Казах",
      "contactPhone": "+77012345681",
      "isCompleted": false,
      "isCurrentPoint": false,
      "orderCount": 3
    }
  ],
  "progress": {
    "totalPoints": 3,
    "completedPoints": 1,
    "currentPoint": 2
  },
  "eta": "2025-11-10T15:00:00Z",
  "createdAt": "2025-11-10T10:00:00Z"
}
```

---

## 🔐 Безопасность

1. **Rate Limiting**: 100 запросов в минуту на IP адрес
2. **Минимум данных**: Только публичная информация (без внутренних ID организаций, цен, и т.д.)
3. **TTL токена (опционально)**: Токен перестает работать через 48 часов после завершения заявки
4. **CORS**: Разрешить запросы с любых доменов для публичного API
5. **Логирование**: Записывать все обращения к публичному API

---

## 📝 Notes

1. **Polling vs WebSocket**: В MVP используем polling (каждые 15 сек). В будущем можно добавить WebSocket для real-time
2. **ETA расчет**: Временная заглушка (+30 мин). Нужна интеграция с Yandex Maps API для точного расчета
3. **QR-код**: Опционально, можно добавить генерацию QR-кода для удобного шеринга
4. **TTL токена**: Можно добавить автоматическое истечение токена через N часов после завершения
5. **Уведомления**: В будущем можно добавить push-уведомления заказчику при изменении статуса

---

## 🔗 References

- **Similar features**: Uber tracking, Yandex.Taxi tracking, DHL tracking
- **Maps API**: Yandex Maps JavaScript API
- **Rate limiting**: Bucket4j library

---

**Estimated**: 3-4 дня разработки + 1 день тестирования
**Priority**: MEDIUM (nice-to-have feature, улучшает UX для заказчика)
