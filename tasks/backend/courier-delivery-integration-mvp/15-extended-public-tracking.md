# 15. Расширенная публичная ссылка отслеживания для всех типов заявок

**Дата создания**: 2025-12-04
**Статус**: TO DO
**Приоритет**: MEDIUM
**Автор**: Ali (Product Requirements)

---

## 📋 Проблема

**Бизнес-кейс:**
Текущая реализация публичного трекинга работает только для курьерской доставки (COURIER_DELIVERY). Заказчики других типов перевозок также хотят отслеживать свои грузы:
- FTL (магистральные перевозки) - крупные грузы между городами
- LTL (сборные перевозки) - частичная загрузка транспорта
- CITY (городские перевозки) - доставка по городу
- BULK (сыпучие материалы) - специализированные перевозки

**Текущие ограничения:**
1. PublicTrackingService проверяет тип и работает только с COURIER_DELIVERY
2. В RoutePoint не передаются координаты точек маршрута (latitude/longitude), хотя они есть в БД
3. FTL-заявки не могут генерировать публичные ссылки отслеживания
4. Нет визуализации точек маршрута на карте для планирования

**Решение:**
Расширить функциональность публичного трекинга для всех типов транспортировки и добавить координаты в данные маршрута.

---

## 🎯 Решение

### Основные изменения

1. **Поддержка всех типов транспортировки**
   - Убрать ограничение только на COURIER_DELIVERY
   - Добавить специфичную обработку для разных типов заявок

2. **Координаты в RoutePoint**
   - Добавить latitude/longitude в RoutePoint DTO
   - Извлекать координаты из CargoLoadingHistory.location

3. **Улучшенная визуализация**
   - Показывать точки маршрута на карте
   - Рассчитывать расстояние между точками
   - Более точный расчет ETA на основе координат

---

## 🗄️ Изменения в БД

База данных уже готова - никаких миграций не требуется:
- Поле `public_tracking_token` уже есть в таблице `transportation`
- Поле `location` с координатами уже есть в `cargo_loading_history`

---

## 🔧 Backend изменения

### 1. Обновить PublicTrackingService

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/service/PublicTrackingService.java`

```java
package kz.coube.backend.courier.service;

import kz.coube.backend.applications.TransportationService;
import kz.coube.backend.applications.entity.CourierRouteOrder;
import kz.coube.backend.applications.entity.Transportation;
import kz.coube.backend.courier.dto.PublicTrackingResponse;
import kz.coube.backend.dictionaries.enumeration.TransportationType;
import kz.coube.backend.driver.DriverLocationService;
import kz.coube.backend.driver.model.DriverLocation;
import kz.coube.backend.organization.model.Employee;
import kz.coube.backend.route.entity.CargoLoadingHistory;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class PublicTrackingService {

    private final TransportationService transportationService;
    private final CourierRouteOrderService courierRouteOrderService;
    private final DriverLocationService driverLocationService;

    // Типы транспортировки, поддерживающие публичный трекинг
    private static final Set<TransportationType> SUPPORTED_TYPES = Set.of(
        TransportationType.COURIER_DELIVERY,
        TransportationType.FTL,
        TransportationType.LTL,
        TransportationType.CITY,
        TransportationType.BULK
    );

    /**
     * Генерировать или получить существующий токен для transportation
     * Теперь поддерживает все типы транспортировки
     */
    @Transactional
    public String generateOrGetTrackingToken(Long transportationId) {
        Transportation transportation = transportationService.findById(transportationId);

        // Проверка поддерживаемых типов (по факту - все типы)
        if (!SUPPORTED_TYPES.contains(transportation.getTransportationType())) {
            throw new IllegalStateException(
                "Public tracking is not supported for transportation type: " +
                transportation.getTransportationType()
            );
        }

        // Если токен уже есть - вернуть его
        if (transportation.getPublicTrackingToken() != null) {
            return transportation.getPublicTrackingToken().toString();
        }

        // Генерируем новый токен
        UUID token = UUID.randomUUID();
        transportation.setPublicTrackingToken(token);
        transportationService.save(transportation);

        log.info("Generated public tracking token for {} transportation {}: {}",
                 transportation.getTransportationType(), transportationId, token);

        return token.toString();
    }

    /**
     * Получить данные для публичного отслеживания (БЕЗ авторизации)
     * Расширенная версия с поддержкой всех типов транспортировки
     */
    @Transactional(readOnly = true)
    public PublicTrackingResponse getTrackingData(UUID token) {

        Transportation transportation = transportationService
                .getByPublicTrackingToken(token);

        // Получить текущую позицию транспорта
        PublicTrackingResponse.CourierLocation location = null;
        List<DriverLocation> driverLocationResponses =
            driverLocationService.getDriverLocationsByTransportationId(transportation.getId());

        if (!driverLocationResponses.isEmpty()) {
            DriverLocation latestLocation = driverLocationResponses.stream()
                    .max(Comparator.comparing(DriverLocation::getTimestamp))
                    .orElse(null);
            if (latestLocation != null) {
                location = PublicTrackingResponse.CourierLocation.builder()
                        .latitude(latestLocation.getLocation().getY())
                        .longitude(latestLocation.getLocation().getX())
                        .timestamp(latestLocation.getTimestamp())
                        .build();
            }
        }

        // Получить информацию о водителе/курьере
        PublicTrackingResponse.CourierInfo courierInfo = getCourierInfo(transportation);

        // Получить точки маршрута с координатами
        List<PublicTrackingResponse.RoutePoint> routePoints = getRoutePoints(transportation);

        // Рассчитать прогресс
        PublicTrackingResponse.Progress progress = calculateProgress(transportation);

        // Рассчитать ETA (с учетом координат для более точного расчета)
        LocalDateTime eta = calculateETA(transportation, location, routePoints);

        // Добавить информацию о типе транспортировки
        String transportationTypeDescription = getTransportationTypeDescription(
            transportation.getTransportationType()
        );

        return PublicTrackingResponse.builder()
                .transportationId(transportation.getId())
                .transportationType(transportation.getTransportationType().name())
                .transportationTypeDescription(transportationTypeDescription)
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
        Employee driver = transportation.getExecutorEmployee();

        if (driver == null) {
            // Различные сообщения в зависимости от типа
            String noDriverMessage = switch (transportation.getTransportationType()) {
                case COURIER_DELIVERY -> "Курьер не назначен";
                case FTL, LTL, CITY, BULK -> "Водитель не назначен";
                default -> "Исполнитель не назначен";
            };

            return PublicTrackingResponse.CourierInfo.builder()
                    .fullName(noDriverMessage)
                    .phone(null)
                    .build();
        }

        return PublicTrackingResponse.CourierInfo.builder()
                .fullName(driver.getFullName())
                .phone(driver.getPhone())
                .build();
    }

    /**
     * Получить точки маршрута с добавлением координат
     */
    private List<PublicTrackingResponse.RoutePoint> getRoutePoints(Transportation transportation) {
        List<CargoLoadingHistory> cargoLoadings = transportation.getCargoLoadings();
        if (cargoLoadings == null || cargoLoadings.isEmpty()) {
            return List.of();
        }

        // Фильтрация в зависимости от типа транспортировки
        return cargoLoadings.stream()
                .filter(cl -> shouldIncludePoint(cl, transportation.getTransportationType()))
                .map(cl -> {
                    // Для курьерской доставки получаем заказы
                    Integer orderCount = null;
                    if (transportation.getTransportationType() == TransportationType.COURIER_DELIVERY) {
                        List<CourierRouteOrder> orders = courierRouteOrderService.getByCargoLoadingHistory(cl);
                        orderCount = orders.size();
                    }

                    // Извлекаем координаты из location
                    Double latitude = null;
                    Double longitude = null;
                    if (cl.getLocation() != null) {
                        latitude = cl.getLocation().getY();
                        longitude = cl.getLocation().getX();
                    }

                    return PublicTrackingResponse.RoutePoint.builder()
                            .orderNum(cl.getOrderNum())
                            .address(cl.getAddress())
                            .contactName(cl.getContactPersonName())
                            .contactPhone(cl.getContactNumber())
                            .latitude(latitude)
                            .longitude(longitude)
                            .loadingType(cl.getLoadingType() != null ? cl.getLoadingType().name() : null)
                            .loadingDatetime(cl.getLoadingDatetime())
                            .weight(cl.getWeight())
                            .weightUnit(cl.getWeightUnit() != null ? cl.getWeightUnit().name() : null)
                            .volume(cl.getVolume())
                            .commentary(cl.getCommentary())
                            .isCompleted(cl.getIsActive() == null || !cl.getIsActive())
                            .isCurrentPoint(Boolean.TRUE.equals(cl.getIsActive()))
                            .isDriverAtLocation(cl.getIsDriverAtLocation())
                            .orderCount(orderCount)
                            .build();
                })
                .collect(Collectors.toList());
    }

    /**
     * Определить, нужно ли включать точку в маршрут
     */
    private boolean shouldIncludePoint(CargoLoadingHistory cl, TransportationType type) {
        // Для курьерской доставки - только точки со складами
        if (type == TransportationType.COURIER_DELIVERY) {
            return cl.getCourierWarehouseId() != null;
        }
        // Для остальных типов - все активные точки
        return true;
    }

    private PublicTrackingResponse.Progress calculateProgress(Transportation transportation) {
        List<CargoLoadingHistory> cargoLoadings = transportation.getCargoLoadings();
        if (cargoLoadings == null || cargoLoadings.isEmpty()) {
            return PublicTrackingResponse.Progress.builder()
                    .totalPoints(0)
                    .completedPoints(0)
                    .currentPoint(0)
                    .percentage(0.0)
                    .build();
        }

        // Фильтруем точки в зависимости от типа
        List<CargoLoadingHistory> relevantPoints = cargoLoadings.stream()
                .filter(cl -> shouldIncludePoint(cl, transportation.getTransportationType()))
                .toList();

        long completed = relevantPoints.stream()
                .filter(cl -> cl.getIsActive() == null || !cl.getIsActive())
                .count();

        int currentPoint = relevantPoints.stream()
                .filter(cl -> Boolean.TRUE.equals(cl.getIsActive()))
                .findFirst()
                .map(CargoLoadingHistory::getOrderNum)
                .orElse(relevantPoints.size());

        double percentage = relevantPoints.isEmpty() ? 0 :
                           (completed * 100.0) / relevantPoints.size();

        return PublicTrackingResponse.Progress.builder()
                .totalPoints(relevantPoints.size())
                .completedPoints((int) completed)
                .currentPoint(currentPoint)
                .percentage(percentage)
                .build();
    }

    /**
     * Расчет ETA с учетом координат точек
     */
    private LocalDateTime calculateETA(Transportation transportation,
                                       PublicTrackingResponse.CourierLocation currentLocation,
                                       List<PublicTrackingResponse.RoutePoint> routePoints) {

        // Найти текущую активную точку
        PublicTrackingResponse.RoutePoint activePoint = routePoints.stream()
                .filter(rp -> Boolean.TRUE.equals(rp.isCurrentPoint()))
                .findFirst()
                .orElse(null);

        if (activePoint == null) {
            return null; // Маршрут завершен
        }

        // Если есть координаты текущего местоположения и целевой точки
        if (currentLocation != null && activePoint.latitude() != null && activePoint.longitude() != null) {
            // Расчет расстояния между точками (формула гаверсинуса)
            double distance = calculateDistance(
                currentLocation.latitude(), currentLocation.longitude(),
                activePoint.latitude(), activePoint.longitude()
            );

            // Средняя скорость в зависимости от типа транспортировки (км/ч)
            double averageSpeed = switch (transportation.getTransportationType()) {
                case COURIER_DELIVERY, CITY -> 30.0; // Городская скорость
                case FTL, LTL -> 60.0; // Магистральная скорость
                case BULK -> 40.0; // Скорость для спецтехники
                default -> 45.0;
            };

            // Время в минутах = (расстояние в км) / (скорость в км/ч) * 60
            int estimatedMinutes = (int) ((distance / averageSpeed) * 60);

            // Добавить буфер времени для погрузки/разгрузки
            int bufferMinutes = switch (transportation.getTransportationType()) {
                case COURIER_DELIVERY -> 10;
                case CITY -> 15;
                case FTL, LTL, BULK -> 30;
                default -> 20;
            };

            return LocalDateTime.now().plusMinutes(estimatedMinutes + bufferMinutes);
        }

        // Если координат нет - используем заглушку
        return LocalDateTime.now().plusMinutes(30);
    }

    /**
     * Расчет расстояния между двумя точками (формула гаверсинуса)
     * @return расстояние в километрах
     */
    private double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371; // Радиус Земли в километрах

        double latDistance = Math.toRadians(lat2 - lat1);
        double lonDistance = Math.toRadians(lon2 - lon1);
        double a = Math.sin(latDistance / 2) * Math.sin(latDistance / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(lonDistance / 2) * Math.sin(lonDistance / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

        return R * c;
    }

    private String getStatusDescription(kz.coube.backend.dictionaries.enumeration.TransportationStatus status) {
        return switch (status) {
            case DRIVER_ACCEPTED -> "Водитель принял заказ";
            case ON_THE_WAY -> "В пути";
            case AWAITING_RETURN_CONFIRMATION -> "Ожидает подтверждения возврата";
            case FINISHED -> "Доставка завершена";
            case LOADING -> "Погрузка";
            case UNLOADING -> "Разгрузка";
            default -> status.name();
        };
    }

    private String getTransportationTypeDescription(TransportationType type) {
        return switch (type) {
            case FTL -> "Магистральные перевозки (FTL)";
            case LTL -> "Сборные перевозки (LTL)";
            case CITY -> "Городские перевозки";
            case BULK -> "Перевозка сыпучих материалов";
            case COURIER_DELIVERY -> "Курьерская доставка";
            default -> type.name();
        };
    }
}
```

---

### 2. Обновить PublicTrackingResponse DTO

**File:** `coube-backend/src/main/java/kz/coube/backend/courier/dto/PublicTrackingResponse.java`

```java
package kz.coube.backend.courier.dto;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public record PublicTrackingResponse(
        Long transportationId,
        String transportationType,
        String transportationTypeDescription,
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
            Double latitude,  // NEW: координаты точки
            Double longitude, // NEW: координаты точки
            String loadingType, // NEW: тип операции (загрузка/разгрузка)
            LocalDateTime loadingDatetime, // NEW: время операции
            BigDecimal weight, // NEW: вес груза в точке
            String weightUnit, // NEW: единица измерения веса
            BigDecimal volume, // NEW: объем груза
            String commentary, // NEW: комментарий к точке
            Boolean isCompleted,
            Boolean isCurrentPoint,
            Boolean isDriverAtLocation, // NEW: водитель прибыл на точку
            Integer orderCount // только для курьерской доставки
    ) {}

    @Builder
    public record Progress(
            Integer totalPoints,
            Integer completedPoints,
            Integer currentPoint,
            Double percentage // NEW: процент выполнения
    ) {}
}
```

---

### 3. Обновить Controller для поддержки всех типов

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
@RequestMapping("/api/v1/tracking/management") // Изменен путь - не только courier
@RequiredArgsConstructor
@AuthorizationRequired(roles = {KeycloakRole.LOGISTICIAN, KeycloakRole.ADMIN, KeycloakRole.CUSTOMER})
@Tag(name = "Tracking Management", description = "API управления публичными ссылками отслеживания для всех типов заявок")
public class TrackingManagementController {

    private final PublicTrackingService publicTrackingService;

    @Value("${app.frontend.url:https://coube.kz}")
    private String frontendUrl;

    @PostMapping("/transportations/{transportationId}/generate-link")
    @Operation(
        summary = "Сгенерировать публичную ссылку отслеживания",
        description = "Генерирует уникальную ссылку для отслеживания груза. " +
                      "Поддерживает все типы транспортировки: FTL, LTL, CITY, BULK, COURIER_DELIVERY"
    )
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

## 🎨 Frontend изменения

### Обновить страницу трекинга для отображения координат

**File:** `coube-frontend/src/components/tracking/RouteMap.vue`

```vue
<template>
  <div class="route-map">
    <YandexMap
      :center="mapCenter"
      :zoom="mapZoom"
      @ready="onMapReady"
    >
      <!-- Маркер текущей позиции транспорта -->
      <YandexMarker
        v-if="courierLocation"
        :coordinates="[courierLocation.longitude, courierLocation.latitude]"
        :icon="vehicleIcon"
        :title="$t('tracking.currentPosition')"
      />

      <!-- Маркеры точек маршрута -->
      <YandexMarker
        v-for="point in routePoints"
        :key="point.orderNum"
        :coordinates="[point.longitude, point.latitude]"
        :icon="getPointIcon(point)"
        :title="point.address"
        @click="showPointDetails(point)"
      />

      <!-- Линия маршрута между точками -->
      <YandexPolyline
        :coordinates="routeCoordinates"
        :stroke-color="'#007bff'"
        :stroke-width="3"
        :stroke-opacity="0.7"
      />
    </YandexMap>

    <!-- Popup с деталями точки -->
    <PointDetailsPopup
      v-if="selectedPoint"
      :point="selectedPoint"
      @close="selectedPoint = null"
    />
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import type { PublicTrackingResponse } from '@/types/tracking'

const props = defineProps<{
  courierLocation: PublicTrackingResponse['courierLocation']
  routePoints: PublicTrackingResponse['routePoints']
  transportationType: string
}>()

const selectedPoint = ref(null)

// Вычисляем центр карты
const mapCenter = computed(() => {
  if (props.courierLocation) {
    return [props.courierLocation.longitude, props.courierLocation.latitude]
  }

  // Находим первую точку с координатами
  const firstPoint = props.routePoints?.find(p => p.latitude && p.longitude)
  if (firstPoint) {
    return [firstPoint.longitude, firstPoint.latitude]
  }

  // Дефолтные координаты (Астана)
  return [71.4704, 51.1605]
})

// Координаты для линии маршрута
const routeCoordinates = computed(() => {
  return props.routePoints
    ?.filter(p => p.latitude && p.longitude)
    .map(p => [p.longitude, p.latitude]) || []
})

// Иконка в зависимости от типа транспорта
const vehicleIcon = computed(() => {
  switch (props.transportationType) {
    case 'COURIER_DELIVERY':
      return '/icons/courier-van.svg'
    case 'FTL':
    case 'LTL':
      return '/icons/truck.svg'
    case 'BULK':
      return '/icons/bulk-truck.svg'
    case 'CITY':
      return '/icons/city-truck.svg'
    default:
      return '/icons/default-vehicle.svg'
  }
})

const getPointIcon = (point) => {
  if (point.isCompleted) {
    return '/icons/point-completed.svg'
  } else if (point.isCurrentPoint) {
    return '/icons/point-active.svg'
  }
  return '/icons/point-pending.svg'
}

const showPointDetails = (point) => {
  selectedPoint.value = point
}

const mapZoom = ref(12)

const onMapReady = (map) => {
  // Автоматически подстраиваем масштаб под все точки
  if (props.routePoints?.length > 1) {
    const bounds = calculateBounds()
    map.setBounds(bounds, { padding: 50 })
  }
}

const calculateBounds = () => {
  const points = [
    ...(props.courierLocation ? [[props.courierLocation.longitude, props.courierLocation.latitude]] : []),
    ...props.routePoints
      .filter(p => p.latitude && p.longitude)
      .map(p => [p.longitude, p.latitude])
  ]

  if (points.length === 0) return null

  const lats = points.map(p => p[1])
  const lngs = points.map(p => p[0])

  return [
    [Math.min(...lngs), Math.min(...lats)],
    [Math.max(...lngs), Math.max(...lats)]
  ]
}
</script>
```

---

## 🧪 Testing Checklist

### Backend Tests

- [ ] Генерация токена для всех типов транспортировки (FTL, LTL, CITY, BULK, COURIER_DELIVERY)
- [ ] Получение данных трекинга с координатами точек маршрута
- [ ] Расчет ETA на основе реальных координат
- [ ] Фильтрация точек для разных типов транспортировки
- [ ] Расчет прогресса с процентами

### Frontend Tests

- [ ] Отображение точек маршрута на карте с правильными координатами
- [ ] Корректная работа для всех типов транспортировки
- [ ] Автоматическое масштабирование карты под все точки
- [ ] Отображение линии маршрута между точками
- [ ] Popup с деталями точки при клике
- [ ] Разные иконки для разных типов транспорта

### Integration Tests

- [ ] E2E: Генерация ссылки для FTL заявки → открытие → отображение на карте
- [ ] E2E: Обновление координат в real-time при движении транспорта
- [ ] Проверка расчета ETA для разных расстояний

---

## 📊 Example Request/Response

### Генерация ссылки для FTL заявки

```http
POST /api/v1/tracking/management/transportations/67890/generate-link
Authorization: Bearer {token}
```

**Response:**
```json
{
  "transportationId": 67890,
  "trackingToken": "123e4567-e89b-12d3-a456-426614174000",
  "trackingUrl": "https://coube.kz/tracking/123e4567-e89b-12d3-a456-426614174000"
}
```

### Получение данных трекинга с координатами

```http
GET /api/v1/public/tracking/123e4567-e89b-12d3-a456-426614174000
```

**Response:**
```json
{
  "transportationId": 67890,
  "transportationType": "FTL",
  "transportationTypeDescription": "Магистральные перевозки (FTL)",
  "status": "ON_THE_WAY",
  "statusDescription": "В пути",
  "courierLocation": {
    "latitude": 51.2345,
    "longitude": 71.5678,
    "timestamp": "2025-12-04T10:30:00Z"
  },
  "courierInfo": {
    "fullName": "Водитель Иван Петров",
    "phone": "+77001234567"
  },
  "routePoints": [
    {
      "orderNum": 1,
      "address": "г. Астана, ул. Промышленная 10",
      "contactName": "ТОО Грузоотправитель",
      "contactPhone": "+77001111111",
      "latitude": 51.1605,
      "longitude": 71.4704,
      "loadingType": "LOADING",
      "loadingDatetime": "2025-12-04T08:00:00",
      "weight": 20000,
      "weightUnit": "KG",
      "volume": 85,
      "commentary": "Погрузка контейнеров",
      "isCompleted": true,
      "isCurrentPoint": false,
      "isDriverAtLocation": false,
      "orderCount": null
    },
    {
      "orderNum": 2,
      "address": "г. Алматы, ул. Складская 25",
      "contactName": "ТОО Грузополучатель",
      "contactPhone": "+77002222222",
      "latitude": 43.2220,
      "longitude": 76.8512,
      "loadingType": "UNLOADING",
      "loadingDatetime": "2025-12-05T14:00:00",
      "weight": 20000,
      "weightUnit": "KG",
      "volume": 85,
      "commentary": "Разгрузка на склад",
      "isCompleted": false,
      "isCurrentPoint": true,
      "isDriverAtLocation": false,
      "orderCount": null
    }
  ],
  "progress": {
    "totalPoints": 2,
    "completedPoints": 1,
    "currentPoint": 2,
    "percentage": 50.0
  },
  "eta": "2025-12-05T13:45:00",
  "createdAt": "2025-12-04T07:00:00"
}
```

---

## 🔐 Безопасность

1. **Rate Limiting**: Сохраняется существующее ограничение 100 req/min на IP
2. **Валидация координат**: Проверка корректности latitude (-90 до 90) и longitude (-180 до 180)
3. **Фильтрация данных**: Не показываем чувствительную информацию (цены, внутренние ID)
4. **Логирование**: Запись всех обращений с указанием типа транспортировки

---

## 📝 Notes

### Приоритеты реализации

1. **Phase 1 (обязательно)**:
   - Поддержка всех типов транспортировки
   - Добавление координат в RoutePoint

2. **Phase 2 (желательно)**:
   - Улучшенный расчет ETA на основе координат
   - Визуализация маршрута на карте

3. **Phase 3 (опционально)**:
   - Интеграция с Yandex Maps API для расчета реального времени прибытия
   - Push-уведомления о прибытии в точку
   - История перемещений

### Технические заметки

- Координаты уже есть в БД (CargoLoadingHistory.location)
- Для FTL/LTL заявок обычно 2-3 точки (загрузка и разгрузка)
- Для курьерской доставки может быть 10-50 точек
- Рекомендуется кеширование данных маршрута на фронтенде

---

**Estimated**: 2-3 дня разработки + 1 день тестирования
**Priority**: MEDIUM
**Dependencies**: Задача #14 (базовый публичный трекинг)