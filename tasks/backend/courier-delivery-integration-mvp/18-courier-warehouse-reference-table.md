# 18. Справочник складов/ПВЗ для курьерской доставки

## Описание задачи
Создать справочную таблицу для хранения информации о пунктах выдачи заказов (ПВЗ) и складах, используемых в курьерской доставке.

## Причина добавления
TEEZ и другие партнеры предоставляют список своих ПВЗ с уникальными идентификаторами. Необходимо хранить эту информацию для:
- Валидации warehouseId при импорте маршрутных листов
- Отображения названий и адресов ПВЗ в интерфейсах
- Геолокации и построения маршрутов
- Разделения ПВЗ по компаниям-партнерам

## Структура данных от TEEZ

```
id (UUID)                               название                                адрес                                   pvz_id  abbreviation
b6d80e58-3273-4f38-919b-e0d33e276d16   Курьерская доставка Петропавловск     Петропавловск, Назарбаева 109         58      PET-55
85e08a8d-237c-4ce4-8877-b726ed1c2add   Курьерская доставка Караганда         Караганда, Ашимова 21                  52      KRG-55
...
```

## 1. SQL Миграция

### Файл: `V20251206__create_courier_warehouse_table.sql`

```sql
-- Создание таблицы справочника складов/ПВЗ для курьерской доставки
CREATE TABLE IF NOT EXISTS applications.courier_warehouse (
    -- Первичный ключ (UUID от партнера)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Внешний ID от партнера (для TEEZ это их UUID)
    external_id TEXT NOT NULL,

    -- Числовой ID от партнера (pvz_id от TEEZ)
    partner_warehouse_id INTEGER,

    -- Основная информация
    name TEXT NOT NULL,
    address TEXT,
    abbreviation TEXT,

    -- Геолокация
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),

    -- Привязка к организации
    organization_id UUID NOT NULL REFERENCES applications.organization(id),

    -- Источник данных
    source_system TEXT NOT NULL, -- 'TEEZ_PVZ', 'KASPI', etc.

    -- Статус
    is_active BOOLEAN DEFAULT true,

    -- Тип точки
    warehouse_type TEXT DEFAULT 'PVZ', -- 'PVZ', 'WAREHOUSE', 'SORTING_CENTER'

    -- Метаданные
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by TEXT,
    updated_by TEXT,

    -- Уникальные ограничения
    CONSTRAINT uk_courier_warehouse_external_org UNIQUE(external_id, organization_id),
    CONSTRAINT uk_courier_warehouse_partner_id_org UNIQUE(partner_warehouse_id, organization_id)
);

-- Индексы для быстрого поиска
CREATE INDEX idx_courier_warehouse_organization ON applications.courier_warehouse(organization_id);
CREATE INDEX idx_courier_warehouse_source_system ON applications.courier_warehouse(source_system);
CREATE INDEX idx_courier_warehouse_active ON applications.courier_warehouse(is_active) WHERE is_active = true;
CREATE INDEX idx_courier_warehouse_partner_id ON applications.courier_warehouse(partner_warehouse_id) WHERE partner_warehouse_id IS NOT NULL;

-- Комментарии
COMMENT ON TABLE applications.courier_warehouse IS 'Справочник складов и ПВЗ для курьерской доставки';
COMMENT ON COLUMN applications.courier_warehouse.external_id IS 'Внешний ID от партнера (UUID для TEEZ)';
COMMENT ON COLUMN applications.courier_warehouse.partner_warehouse_id IS 'Числовой ID от партнера (pvz_id для TEEZ)';
COMMENT ON COLUMN applications.courier_warehouse.name IS 'Название ПВЗ/склада';
COMMENT ON COLUMN applications.courier_warehouse.address IS 'Физический адрес';
COMMENT ON COLUMN applications.courier_warehouse.abbreviation IS 'Краткое обозначение (например, PET-55)';
COMMENT ON COLUMN applications.courier_warehouse.latitude IS 'Широта для геолокации';
COMMENT ON COLUMN applications.courier_warehouse.longitude IS 'Долгота для геолокации';
COMMENT ON COLUMN applications.courier_warehouse.organization_id IS 'ID организации-владельца ПВЗ';
COMMENT ON COLUMN applications.courier_warehouse.source_system IS 'Система-источник данных';
COMMENT ON COLUMN applications.courier_warehouse.warehouse_type IS 'Тип точки: PVZ, WAREHOUSE, SORTING_CENTER';
```

## 2. Java Entity

### Файл: `CourierWarehouse.java`

```java
package kz.coube.backend.applications.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "courier_warehouse", schema = "applications")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@ToString
public class CourierWarehouse {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "external_id", nullable = false)
    private String externalId;

    @Column(name = "partner_warehouse_id")
    private Integer partnerWarehouseId;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "address")
    private String address;

    @Column(name = "abbreviation")
    private String abbreviation;

    @Column(name = "latitude", precision = 10, scale = 8)
    private BigDecimal latitude;

    @Column(name = "longitude", precision = 11, scale = 8)
    private BigDecimal longitude;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "organization_id", nullable = false)
    private Organization organization;

    @Column(name = "source_system", nullable = false)
    private String sourceSystem;

    @Column(name = "is_active")
    @Builder.Default
    private Boolean isActive = true;

    @Column(name = "warehouse_type")
    @Builder.Default
    private String warehouseType = "PVZ";

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @Column(name = "created_by")
    private String createdBy;

    @Column(name = "updated_by")
    private String updatedBy;
}
```

## 3. Repository

### Файл: `CourierWarehouseRepository.java`

```java
package kz.coube.backend.applications.repository;

import kz.coube.backend.applications.entity.CourierWarehouse;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface CourierWarehouseRepository extends JpaRepository<CourierWarehouse, UUID> {

    Optional<CourierWarehouse> findByExternalIdAndOrganizationId(String externalId, UUID organizationId);

    Optional<CourierWarehouse> findByPartnerWarehouseIdAndOrganizationId(Integer partnerWarehouseId, UUID organizationId);

    List<CourierWarehouse> findByOrganizationIdAndIsActiveTrue(UUID organizationId);

    List<CourierWarehouse> findBySourceSystemAndIsActiveTrue(String sourceSystem);

    @Query("SELECT cw FROM CourierWarehouse cw WHERE cw.partnerWarehouseId = :warehouseId " +
           "AND cw.sourceSystem = :sourceSystem AND cw.isActive = true")
    Optional<CourierWarehouse> findActiveByPartnerIdAndSource(
        @Param("warehouseId") Integer warehouseId,
        @Param("sourceSystem") String sourceSystem
    );
}
```

## 4. Service для работы со справочником

### Файл: `CourierWarehouseService.java`

```java
package kz.coube.backend.applications.service;

import kz.coube.backend.applications.entity.CourierWarehouse;
import kz.coube.backend.applications.repository.CourierWarehouseRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class CourierWarehouseService {

    private final CourierWarehouseRepository warehouseRepository;

    /**
     * Найти склад по ID партнера и системе-источнику
     */
    public Optional<CourierWarehouse> findByPartnerIdAndSource(Integer partnerId, String sourceSystem) {
        return warehouseRepository.findActiveByPartnerIdAndSource(partnerId, sourceSystem);
    }

    /**
     * Валидация существования склада
     */
    public boolean validateWarehouseExists(String warehouseId, String sourceSystem) {
        try {
            Integer partnerId = Integer.parseInt(warehouseId);
            return warehouseRepository.findActiveByPartnerIdAndSource(partnerId, sourceSystem).isPresent();
        } catch (NumberFormatException e) {
            log.warn("Invalid warehouse ID format: {}", warehouseId);
            return false;
        }
    }

    /**
     * Получить информацию о складе для отображения
     */
    @Transactional(readOnly = true)
    public CourierWarehouse getWarehouseInfo(String warehouseId, String sourceSystem) {
        Integer partnerId = Integer.parseInt(warehouseId);
        return warehouseRepository.findActiveByPartnerIdAndSource(partnerId, sourceSystem)
            .orElseThrow(() -> new IllegalArgumentException(
                String.format("Warehouse not found: %s from %s", warehouseId, sourceSystem)
            ));
    }
}
```

## 5. Изменения в CourierIntegrationService

Обновить метод импорта для валидации warehouseId:

```java
// В методе importWaybill добавить валидацию
private void validateWarehouseIds(CourierWaybillImportDto dto) {
    for (CourierDeliveryDto delivery : dto.getDeliveries()) {
        if (Boolean.TRUE.equals(delivery.getIsCourierWarehouse()) && delivery.getWarehouseId() != null) {
            boolean exists = courierWarehouseService.validateWarehouseExists(
                delivery.getWarehouseId(),
                dto.getSourceSystem()
            );

            if (!exists) {
                throw new ValidationException(
                    String.format("Unknown warehouse ID: %s", delivery.getWarehouseId())
                );
            }
        }
    }
}
```

## 6. SQL для заполнения данными от TEEZ

```sql
-- Пример заполнения данными от TEEZ (выполнить после создания таблицы)
INSERT INTO applications.courier_warehouse (
    external_id, partner_warehouse_id, name, address, abbreviation,
    latitude, longitude, organization_id, source_system, warehouse_type
) VALUES
('b6d80e58-3273-4f38-919b-e0d33e276d16', 58, 'Курьерская доставка Петропавловск', 'Петропавловск, Назарбаева 109', 'PET-55', NULL, NULL, 'ORG-TEEZ-UUID', 'TEEZ_PVZ', 'PVZ'),
('85e08a8d-237c-4ce4-8877-b726ed1c2add', 52, 'Курьерская доставка Караганда', 'Караганда, Ашимова 21', 'KRG-55', NULL, NULL, 'ORG-TEEZ-UUID', 'TEEZ_PVZ', 'PVZ'),
('c7f6cd58-a12f-49c2-b98e-7bd834391eae', 54, 'Курьерская доставка Талдыкорган', 'Талдыкорган, Конаева 20', 'TAL-55', NULL, NULL, 'ORG-TEEZ-UUID', 'TEEZ_PVZ', 'PVZ'),
-- Добавить остальные ПВЗ...
ON CONFLICT (external_id, organization_id) DO UPDATE SET
    partner_warehouse_id = EXCLUDED.partner_warehouse_id,
    name = EXCLUDED.name,
    address = EXCLUDED.address,
    abbreviation = EXCLUDED.abbreviation,
    updated_at = NOW();
```

## 7. API endpoint для управления справочником (опционально)

```java
@RestController
@RequestMapping("/api/v1/courier/warehouses")
@RequiredArgsConstructor
public class CourierWarehouseController {

    private final CourierWarehouseService warehouseService;

    @GetMapping("/{sourceSystem}")
    public List<CourierWarehouseDto> getWarehouses(@PathVariable String sourceSystem) {
        // Возвращает список активных ПВЗ для системы
    }

    @GetMapping("/{sourceSystem}/{warehouseId}")
    public CourierWarehouseDto getWarehouseInfo(
        @PathVariable String sourceSystem,
        @PathVariable String warehouseId
    ) {
        // Возвращает детали конкретного ПВЗ
    }
}
```

## Связь с существующим кодом

1. Поле `courier_warehouse_id` в таблице `cargo_loading_history` будет хранить `partner_warehouse_id` (pvz_id от TEEZ)
2. При импорте маршрутных листов будет проверяться существование ПВЗ в справочнике
3. При отображении информации можно будет показывать полное название и адрес из справочника

## Преимущества решения

✅ Централизованное хранение информации о ПВЗ
✅ Валидация при импорте маршрутных листов
✅ Возможность добавления геокоординат для построения маршрутов
✅ Разделение ПВЗ по компаниям-партнерам
✅ Гибкое управление активностью ПВЗ
✅ История изменений через created_at/updated_at

## Данные от TEEZ для заполнения

```
id                                      название                                адрес                                   pvz_id  abbreviation
b6d80e58-3273-4f38-919b-e0d33e276d16   Курьерская доставка Петропавловск     Петропавловск, Назарбаева 109         58      PET-55
85e08a8d-237c-4ce4-8877-b726ed1c2add   Курьерская доставка Караганда         Караганда, Ашимова 21                  52      KRG-55
c7f6cd58-a12f-49c2-b98e-7bd834391eae   Курьерская доставка Талдыкорган       Талдыкорган, Конаева 20                54      TAL-55
891cc2b1-b116-4283-87dd-9019db536d0b   Курьерская доставка Каскелен          (адрес не указан)                      56      KAS-55
e868469a-71c2-4fad-8eb7-7ccbd7e53008   Курьерская доставка Атырау            Атырау, Азаттык 30                     60      ATR-55
bcab7f69-382a-41ca-8e8f-6c5bed9bf0c3   Курьерская доставка Семей             Семей, Севастопольскую 13а             62      SEM-55
67cb8650-4496-459e-9b1e-74fd59b96de4   Курьерская доставка Актобе            Актобе, Молдагулова 36                 64      AKB-55
14b4afb9-0616-4da6-b23c-a11343dadab8   Курьерская доставка Костанай          Костанай, Чехова 96 (+курьерка Рудного) 66     KOS-55
674ba411-ed86-4814-8f69-04851799f3e1   Курьерская доставка Темиртау          Темиртау, Мира 90                      68      TEM-55
ae9d32f0-f0f7-4c6d-9b88-91ac720dc445   Курьерская доставка Сатпаев           (адрес не указан)                      70      SAT-55
a1f7ce1b-442e-43e7-afd0-e8c3cc18e14c   Курьерская доставка Балхаш            Балхаш, уалиханова 9                   72      BAL-55
907c6665-3d54-4846-985b-5495b988bd27   Курьерская доставка Кентау            (адрес не указан)                      74      KEN-55
156875c2-be91-4391-9670-d5636f1a6eeb   Курьерская доставка Кызылорда         Кызылорда, Муратбаева 17               78      KYZ-55
0b948fb3-1761-4e9d-9a96-44693383d041   Курьерская доставка Тараз             Тараз, Абая 149А                       79      TAR-55
26d19fae-c4b0-402e-bfa6-76c5e3fb05b5   Курьерская доставка Жанаозен          Жанаозен, Самал 25                     76      JAN-55
f2cc20de-587b-4b85-9039-1c2308603a82   Курьерская доставка Рудный            (адрес не указан)                      80      RUD-55
a7359543-f3dc-42c6-8fdf-fb14378f7c9f   Курьерская доставка Талгар            (адрес не указан)                      81      TAG-55
fa2dc840-f7b8-4bd0-94fd-fb97f9d7fa77   Курьерская доставка Алматы            (адрес не указан)                      137     ALM-55
5b4f487f-fb47-43d9-9e4c-c8c371c2d4e6   Курьерская доставка Конаев            (адрес не указан)                      53      KON-55
c8b173c1-9957-4549-93c4-e1699125b3bd   Курьерская доставка Аксу              Аксу, Ауэзова 36                       55      AKS-55
43c35331-5b70-44c9-ae3f-2c111a4d06e3   Курьерская доставка Кульсары          Кульсары, 3 мкр 48                     57      KUL-55
07eeba14-5f2f-4edb-9abb-d499b55b30f1   Курьерская доставка Туркестан         Туркестан, 32 улица                    59      TUR-55
3899549c-6d03-438c-84bc-032273d1ee56   Курьерская доставка Жезказган         Жезказган, Гарышкерлер 11              61      JEZ-55
61222fc2-8192-424d-ab33-3afdadc8cb9e   Курьерская доставка Кокшетау          Кокшетау Ауельбекова 125               63      KOK-55
bfa162e2-eb4a-4299-bf3d-53185d889fef   Курьерская доставка Алатау            (адрес не указан)                      65      ALA-55
f0054de1-2c1e-41ea-8623-2cc2b4b5c759   Курьерская доставка Шымкент           Шымкент, 16 мкр 6                      67      SHM-55
7ba11153-3cb7-4d0b-8b00-031b12a6f7c4   Курьерская доставка Уральск           Уральск, Абая 86                       69      URA-55
383b4cab-a52a-4bbe-ae43-40169254a2ed   Курьерская доставка Усть-Каменогорск  Усть-Каменогорск, Абая 7               71      UKA-55
b5ef34b9-5acb-4802-98c5-3e75d76dbd74   Курьерская доставка Актау             Актау, 6 мкр 39                        73      AKT-55
27dec95c-8098-4d98-a59a-ac333d64f5e0   Курьерская доставка Экибастуз         Экибастуз, Кеншилер 12                 75      EKB-55
30b45cec-2ad7-4aac-baa3-92c2321873d5   Курьерская доставка Павлодар          Павлодар, Катаева 42                   77      PAV-55
f68a100d-59cb-46a6-ad1e-ea1fe3dbd820   Курьерская доставка Астана            Астана, кумисбекова 11                 138     AST-55
0a99cf90-8443-4a43-9074-80af2a998f72   Курьерская доставка Щучинск           Щучинск, Ауэзова 65                    367     SHC-55
```

**Примечание**: Для ПВЗ без адресов необходимо дозаполнить перед вставкой в базу.

## Тестирование

1. Создать миграцию и запустить
2. Заполнить таблицу данными от TEEZ
3. Проверить импорт маршрутного листа с warehouseId из справочника
4. Проверить валидацию несуществующего warehouseId

## Оценка времени

- Создание миграции: 0.5 часа
- Entity + Repository: 1 час
- Service + интеграция: 2 часа
- Тестирование: 1 час
- **Итого**: 4.5 часа

---

**Дата создания**: 2025-12-06
**Приоритет**: 🟡 Medium
**Статус**: 📝 Ready for Development