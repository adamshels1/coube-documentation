# Задача 24: API для получения списка складов курьерской доставки

## 🎯 Цель

Создать REST API endpoints для получения информации о складах/ПВЗ курьерской доставки для использования в UI.

## 📋 Описание

При редактировании курьерских заявок на фронтенде (`/applications/courier-delivery/edit/{id}`) нужно отображать информацию о складах по `warehouseId`. Сейчас есть Entity и Service, но нет Controller и endpoints.

**Use case:**
1. Логист открывает страницу редактирования курьерской заявки
2. В точках маршрута есть поле `warehouseId` (например, "58")
3. Фронтенд должен показать название и адрес склада (например, "PET-55 - Петропавловск, Назарбаева 109")
4. Для dropdown выбора склада нужен список всех активных складов

---

## 🔧 Что нужно реализовать

### API Endpoints

**1. Получить список всех складов**
```
GET /api/v1/courier/warehouses
```

**2. Получить информацию о конкретном складе**
```
GET /api/v1/courier/warehouses/{warehouseId}
```

---

## 📝 Детальная спецификация

### Endpoint 1: GET /api/v1/courier/warehouses

**Описание:** Получить список всех активных складов курьерской доставки

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `sourceSystem` | String | No | Фильтр по системе-источнику (TEEZ_PVZ, KASPI, etc.) |
| `organizationId` | UUID | No | Фильтр по организации |

**Request:**
```bash
GET /api/v1/courier/warehouses?sourceSystem=TEEZ_PVZ
Authorization: Bearer {token}
```

**Response 200 OK:**
```json
[
  {
    "id": "b6d80e58-3273-4f38-919b-e0d33e276d16",
    "externalId": "b6d80e58-3273-4f38-919b-e0d33e276d16",
    "partnerWarehouseId": 58,
    "name": "Курьерская доставка Петропавловск",
    "address": "Петропавловск, Назарбаева 109",
    "abbreviation": "PET-55",
    "latitude": 54.8642,
    "longitude": 69.1398,
    "organizationId": "a1b2c3d4-...",
    "sourceSystem": "TEEZ_PVZ",
    "isActive": true,
    "warehouseType": "PVZ"
  },
  {
    "id": "85e08a8d-237c-4ce4-8877-b726ed1c2add",
    "externalId": "85e08a8d-237c-4ce4-8877-b726ed1c2add",
    "partnerWarehouseId": 52,
    "name": "Курьерская доставка Караганда",
    "address": "Караганда, Ашимова 21",
    "abbreviation": "KRG-55",
    "latitude": null,
    "longitude": null,
    "organizationId": "a1b2c3d4-...",
    "sourceSystem": "TEEZ_PVZ",
    "isActive": true,
    "warehouseType": "PVZ"
  }
]
```

---

### Endpoint 2: GET /api/v1/courier/warehouses/{warehouseId}

**Описание:** Получить детальную информацию о конкретном складе

**Path Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `warehouseId` | UUID | Yes | ID склада |

**Request:**
```bash
GET /api/v1/courier/warehouses/b6d80e58-3273-4f38-919b-e0d33e276d16
Authorization: Bearer {token}
```

**Response 200 OK:**
```json
{
  "id": "b6d80e58-3273-4f38-919b-e0d33e276d16",
  "externalId": "b6d80e58-3273-4f38-919b-e0d33e276d16",
  "partnerWarehouseId": 58,
  "name": "Курьерская доставка Петропавловск",
  "address": "Петропавловск, Назарбаева 109",
  "abbreviation": "PET-55",
  "latitude": 54.8642,
  "longitude": 69.1398,
  "organizationId": "a1b2c3d4-...",
  "sourceSystem": "TEEZ_PVZ",
  "isActive": true,
  "warehouseType": "PVZ",
  "createdAt": "2025-12-01T10:00:00Z",
  "updatedAt": "2025-12-01T10:00:00Z"
}
```

**Response 404 Not Found:**
```json
{
  "status": "error",
  "error": "NOT_FOUND",
  "message": "Warehouse not found",
  "warehouseId": "b6d80e58-3273-4f38-919b-e0d33e276d16"
}
```

---

## 🔨 Реализация

### 1. DTO

**Файл:** `src/main/java/kz/coube/backend/applications/dto/CourierWarehouseDto.java`

```java
package kz.coube.backend.applications.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CourierWarehouseDto {

    @JsonProperty("id")
    private UUID id;

    @JsonProperty("externalId")
    private String externalId;

    @JsonProperty("partnerWarehouseId")
    private Integer partnerWarehouseId;

    @JsonProperty("name")
    private String name;

    @JsonProperty("address")
    private String address;

    @JsonProperty("abbreviation")
    private String abbreviation;

    @JsonProperty("latitude")
    private BigDecimal latitude;

    @JsonProperty("longitude")
    private BigDecimal longitude;

    @JsonProperty("organizationId")
    private UUID organizationId;

    @JsonProperty("sourceSystem")
    private String sourceSystem;

    @JsonProperty("isActive")
    private Boolean isActive;

    @JsonProperty("warehouseType")
    private String warehouseType;

    @JsonProperty("createdAt")
    private OffsetDateTime createdAt;

    @JsonProperty("updatedAt")
    private OffsetDateTime updatedAt;
}
```

---

### 2. Service (обновление)

**Файл:** `src/main/java/kz/coube/backend/applications/service/CourierWarehouseService.java`

Добавить методы:

```java
@Service
@RequiredArgsConstructor
@Slf4j
public class CourierWarehouseService {

    private final CourierWarehouseRepository warehouseRepository;

    // ... существующие методы

    /**
     * Получить список всех активных складов
     */
    @Transactional(readOnly = true)
    public List<CourierWarehouse> getAllActiveWarehouses(String sourceSystem, UUID organizationId) {
        if (sourceSystem != null && organizationId != null) {
            return warehouseRepository.findBySourceSystemAndOrganizationIdAndIsActiveTrue(
                sourceSystem, organizationId
            );
        } else if (sourceSystem != null) {
            return warehouseRepository.findBySourceSystemAndIsActiveTrue(sourceSystem);
        } else if (organizationId != null) {
            return warehouseRepository.findByOrganizationIdAndIsActiveTrue(organizationId);
        } else {
            return warehouseRepository.findByIsActiveTrue();
        }
    }

    /**
     * Получить склад по ID
     */
    @Transactional(readOnly = true)
    public CourierWarehouse getWarehouseById(UUID warehouseId) {
        return warehouseRepository.findById(warehouseId)
            .orElseThrow(() -> new NotFoundException(
                String.format("Warehouse not found: %s", warehouseId)
            ));
    }
}
```

---

### 3. Repository (обновление)

**Файл:** `src/main/java/kz/coube/backend/applications/repository/CourierWarehouseRepository.java`

Добавить методы:

```java
@Repository
public interface CourierWarehouseRepository extends JpaRepository<CourierWarehouse, UUID> {

    // ... существующие методы

    List<CourierWarehouse> findByIsActiveTrue();

    List<CourierWarehouse> findBySourceSystemAndOrganizationIdAndIsActiveTrue(
        String sourceSystem,
        UUID organizationId
    );
}
```

---

### 4. Controller (новый)

**Файл:** `src/main/java/kz/coube/backend/applications/api/CourierWarehouseController.java`

```java
package kz.coube.backend.applications.api;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import kz.coube.backend.applications.dto.CourierWarehouseDto;
import kz.coube.backend.applications.entity.CourierWarehouse;
import kz.coube.backend.applications.service.CourierWarehouseService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/courier/warehouses")
@RequiredArgsConstructor
@Tag(name = "Courier Warehouses", description = "API для работы со складами курьерской доставки")
public class CourierWarehouseController {

    private final CourierWarehouseService warehouseService;

    @Operation(summary = "Получить список всех активных складов")
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO', 'LOGISTICIAN')")
    public ResponseEntity<List<CourierWarehouseDto>> getAllWarehouses(
            @RequestParam(required = false) String sourceSystem,
            @RequestParam(required = false) UUID organizationId) {

        List<CourierWarehouse> warehouses = warehouseService.getAllActiveWarehouses(
            sourceSystem,
            organizationId
        );

        List<CourierWarehouseDto> dtos = warehouses.stream()
            .map(this::toDto)
            .collect(Collectors.toList());

        return ResponseEntity.ok(dtos);
    }

    @Operation(summary = "Получить информацию о складе по ID")
    @GetMapping("/{warehouseId}")
    @PreAuthorize("hasAnyRole('ADMIN', 'CEO', 'LOGISTICIAN')")
    public ResponseEntity<CourierWarehouseDto> getWarehouseById(
            @PathVariable UUID warehouseId) {

        CourierWarehouse warehouse = warehouseService.getWarehouseById(warehouseId);
        return ResponseEntity.ok(toDto(warehouse));
    }

    /**
     * Маппер Entity -> DTO
     */
    private CourierWarehouseDto toDto(CourierWarehouse warehouse) {
        return CourierWarehouseDto.builder()
            .id(warehouse.getId())
            .externalId(warehouse.getExternalId())
            .partnerWarehouseId(warehouse.getPartnerWarehouseId())
            .name(warehouse.getName())
            .address(warehouse.getAddress())
            .abbreviation(warehouse.getAbbreviation())
            .latitude(warehouse.getLatitude())
            .longitude(warehouse.getLongitude())
            .organizationId(warehouse.getOrganization() != null
                ? warehouse.getOrganization().getId()
                : null)
            .sourceSystem(warehouse.getSourceSystem())
            .isActive(warehouse.getIsActive())
            .warehouseType(warehouse.getWarehouseType())
            .createdAt(warehouse.getCreatedAt())
            .updatedAt(warehouse.getUpdatedAt())
            .build();
    }
}
```

---

## 🧪 Тестирование

### 1. Unit тесты для Service

**Файл:** `CourierWarehouseServiceTest.java`

```java
@Test
void getAllActiveWarehouses_withSourceSystem_shouldReturnFilteredList() {
    // Given
    String sourceSystem = "TEEZ_PVZ";

    // When
    List<CourierWarehouse> result = warehouseService.getAllActiveWarehouses(
        sourceSystem, null
    );

    // Then
    assertFalse(result.isEmpty());
    assertTrue(result.stream()
        .allMatch(w -> sourceSystem.equals(w.getSourceSystem())));
}

@Test
void getWarehouseById_existingId_shouldReturnWarehouse() {
    // Given
    UUID warehouseId = UUID.fromString("b6d80e58-3273-4f38-919b-e0d33e276d16");

    // When
    CourierWarehouse result = warehouseService.getWarehouseById(warehouseId);

    // Then
    assertNotNull(result);
    assertEquals(warehouseId, result.getId());
}

@Test
void getWarehouseById_nonExistingId_shouldThrowException() {
    // Given
    UUID warehouseId = UUID.randomUUID();

    // When & Then
    assertThrows(NotFoundException.class, () -> {
        warehouseService.getWarehouseById(warehouseId);
    });
}
```

### 2. REST API тесты

```bash
# 1. Получить все склады
curl -X GET "http://localhost:8080/api/v1/courier/warehouses" \
  -H "Authorization: Bearer {token}"

# Expected: 200 OK, массив складов

# 2. Получить склады TEEZ
curl -X GET "http://localhost:8080/api/v1/courier/warehouses?sourceSystem=TEEZ_PVZ" \
  -H "Authorization: Bearer {token}"

# Expected: 200 OK, только склады TEEZ

# 3. Получить склад по ID
curl -X GET "http://localhost:8080/api/v1/courier/warehouses/b6d80e58-3273-4f38-919b-e0d33e276d16" \
  -H "Authorization: Bearer {token}"

# Expected: 200 OK, один склад

# 4. Несуществующий склад
curl -X GET "http://localhost:8080/api/v1/courier/warehouses/00000000-0000-0000-0000-000000000000" \
  -H "Authorization: Bearer {token}"

# Expected: 404 Not Found
```

---

## 📱 Использование на фронтенде

### Vue.js (coube-frontend)

**1. API Service:**

```typescript
// src/api/courierWarehouse.ts
import { apiClient } from './client'

export interface CourierWarehouse {
  id: string
  externalId: string
  partnerWarehouseId: number
  name: string
  address: string
  abbreviation: string
  latitude?: number
  longitude?: number
  organizationId: string
  sourceSystem: string
  isActive: boolean
  warehouseType: string
}

export const courierWarehouseApi = {
  // Получить список складов
  getAll(params?: { sourceSystem?: string; organizationId?: string }) {
    return apiClient.get<CourierWarehouse[]>('/api/v1/courier/warehouses', {
      params
    })
  },

  // Получить склад по ID
  getById(warehouseId: string) {
    return apiClient.get<CourierWarehouse>(
      `/api/v1/courier/warehouses/${warehouseId}`
    )
  }
}
```

**2. Использование в компоненте:**

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { courierWarehouseApi, type CourierWarehouse } from '@/api/courierWarehouse'

const warehouses = ref<CourierWarehouse[]>([])
const loading = ref(false)

onMounted(async () => {
  loading.value = true
  try {
    const response = await courierWarehouseApi.getAll({
      sourceSystem: 'TEEZ_PVZ'
    })
    warehouses.value = response.data
  } catch (error) {
    console.error('Failed to load warehouses:', error)
  } finally {
    loading.value = false
  }
})

// Получить название склада по ID
const getWarehouseName = (warehouseId: string) => {
  const warehouse = warehouses.value.find(w => w.id === warehouseId)
  return warehouse
    ? `${warehouse.abbreviation} - ${warehouse.address}`
    : warehouseId
}
</script>

<template>
  <div>
    <!-- Dropdown выбора склада -->
    <select v-model="selectedWarehouseId">
      <option value="">Выберите склад</option>
      <option
        v-for="warehouse in warehouses"
        :key="warehouse.id"
        :value="warehouse.id"
      >
        {{ warehouse.abbreviation }} - {{ warehouse.name }}
      </option>
    </select>

    <!-- Отображение адреса склада -->
    <div v-if="delivery.warehouseId">
      <strong>Склад:</strong> {{ getWarehouseName(delivery.warehouseId) }}
    </div>
  </div>
</template>
```

---

## ✅ Чеклист реализации

### Backend

- [ ] **DTO:** Создать `CourierWarehouseDto.java`
- [ ] **Repository:** Добавить методы в `CourierWarehouseRepository.java`
- [ ] **Service:** Добавить методы в `CourierWarehouseService.java`
- [ ] **Controller:** Создать `CourierWarehouseController.java`
- [ ] **Swagger:** Проверить документацию API
- [ ] **Тесты:** Unit тесты для Service
- [ ] **Тесты:** Integration тесты для Controller

### Frontend (опционально)

- [ ] **API Service:** Создать `courierWarehouse.ts`
- [ ] **Types:** Добавить типы TypeScript
- [ ] **Integration:** Использовать в странице редактирования заявки

---

## ⏱️ Оценка времени

**Backend:**
- DTO: 20 минут
- Repository методы: 15 минут
- Service методы: 30 минут
- Controller: 45 минут
- Unit тесты: 30 минут
- Integration тесты: 30 минут

**Frontend (опционально):**
- API Service: 20 минут
- Integration в UI: 30 минут

**Итого Backend:** ~3 часа
**Итого с Frontend:** ~4 часа

---

## 📌 Примечания

### Права доступа

API доступен для ролей:
- `ADMIN`
- `CEO`
- `LOGISTICIAN`

### Кеширование на фронтенде

Список складов меняется редко, поэтому рекомендуется:
1. Загружать список один раз при монтировании компонента
2. Сохранять в Pinia store для переиспользования
3. Инвалидировать кеш только при явном обновлении

### Фильтрация

Если в системе много складов от разных партнеров, используйте параметр `sourceSystem` для фильтрации.

---

## 🔗 Связанные задачи

- **Задача 18:** Создание справочника складов (Entity, Repository)
- **Задача 21:** Назначение логистов на склады
- **Задача 23:** Добавление поля "Квартира / Офис"

---

**Дата создания:** 2025-12-22
**Приоритет:** HIGH
**Статус:** Ready for Development
**Оценка:** 3 часа (Backend)
**Автор:** Claude Code
