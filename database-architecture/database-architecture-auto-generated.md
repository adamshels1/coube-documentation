# Архитектура базы данных Coube

**Дата обновления**: 2025-10-16 15:19:35  
**Источник**: Автоматически сгенерировано из Flyway миграций

> ⚠️ **Внимание**: Этот файл создается автоматически. Для ручного редактирования используйте `database-architecture-complete.md`

## 📊 Обзор схем БД

Система использует **PostgreSQL** с **PostGIS** расширением для геопространственных данных.

---

## 🗂️ Схема `applications`

**Основная бизнес-логика**: перевозки, контракты, инвойсы, акты, соглашения.

### 📋 Таблицы схемы `applications`

#### `applications.applications.acts`

- **act_number** - `TEXT`NOT NULL UNIQUE
- **document_date** - `DATE`NOT NULL
- **customer_organization_id** - `BIGINT`
- **executor_organization_id** - `BIGINT`
- **total_amount_without_vat** - `NUMERIC(19`
- **total_vat_amount** - `NUMERIC(19`
- **total_amount_with_vat** - `NUMERIC(19`
- **file_id** - `UUID`
- **file_name** - `TEXT`
- **status** - `TEXT`NOT NULL
- **invoice_id** - `BIGINT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.agreement`

- **organization_id** - `BIGINT`
- **deadline_date** - `TIMESTAMP`
- **without_deadline** - `BOOLEAN`
- **transportation_type** - `TEXT`
- **status** - `TEXT`
- **agreement_end_date** - `TIMESTAMP`
- **cargo_name** - `TEXT`
- **cargo_type_id** - `BIGINT`
- **vehicle_body_type_id** - `BIGINT`
- **payment_delay** - `INTEGER`
- **is_signed_eds** - `BOOLEAN`
- **agreement_file_id** - `UUID`UNIQUE
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `applications.applications.agreement_change_history`

- **id** - `BIGSERIAL`PRIMARY KEY PRIMARY KEY
- **agreement_id** - `BIGINT`NOT NULL
- **changed_at** - `TIMESTAMP`NOT NULL DEFAULT
- **description** - `TEXT`
- **changed_by** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `VARCHAR(255)`
- **updated_by** - `VARCHAR(255)`

---

#### `applications.applications.agreement_country`

- **country_id** - `BIGINT`NOT NULL

---

#### `applications.applications.agreement_executor`

- **agreement_id** - `BIGINT`NOT NULL
- **organization_id** - `BIGINT`
- **status** - `TEXT`
- **contract_id** - `BIGINT`UNIQUE
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `applications.applications.agreement_vehicle_body_type`

- **vehicle_body_type_id** - `BIGINT`NOT NULL

---

#### `applications.applications.app_min_supported_version`

- **platform** - `VARCHAR(50)`NOT NULL UNIQUE
- **min_supported_version** - `VARCHAR(20)`NOT NULL
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `applications.applications.cargo_loading`

- **transportation_id** - `BIGINT`NOT NULL
- **loading_method_id** - `BIGINT`
- **loading_operation_id** - `BIGINT`
- **order_num** - `INT`
- **loading_type** - `TEXT`
- **shipper_bin** - `TEXT`NOT NULL
- **loading_datetime** - `TIMESTAMP`NOT NULL
- **address** - `TEXT`NOT NULL
- **longitude** - `TEXT`NOT NULL
- **latitude** - `TEXT`NOT NULL
- **commentary** - `TEXT`
- **weight** - `NUMERIC(15`
- **weight_unit** - `TEXT`NOT NULL
- **volume** - `NUMERIC(15`
- **loading_time_hours** - `INT`NOT NULL
- **contact_number** - `TEXT`NOT NULL
- **contact_person_name** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.contract`

- **transportation_id** - `BIGINT`NOT NULL
- **original_file_id** - `BIGINT`
- **expected_signatures_count** - `INTEGER`
- **signature_with_one_sign** - `BIGINT`
- **signature_with_two_signs** - `BIGINT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.courier_integration_log`

- **id** - `BIGSERIAL`PRIMARY KEY PRIMARY KEY
- **transportation_id** - `BIGINT`
- **direction** - `TEXT`NOT NULL
- **source_system** - `TEXT`NOT NULL
- **http_method** - `TEXT`NOT NULL
- **endpoint** - `TEXT`NOT NULL
- **http_status_code** - `INT`
- **request_payload** - `JSONB`
- **response_payload** - `JSONB`
- **status** - `TEXT`NOT NULL
- **error_message** - `TEXT`
- **retry_count** - `INT`DEFAULT
- **request_datetime** - `TIMESTAMP`NOT NULL
- **response_datetime** - `TIMESTAMP`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.courier_route_order`

- **id** - `BIGSERIAL`PRIMARY KEY PRIMARY KEY
- **cargo_loading_history_id** - `BIGINT`NOT NULL
- **track_number** - `TEXT`NOT NULL UNIQUE
- **external_id** - `TEXT`NOT NULL
- **load_type** - `TEXT`NOT NULL
- **status** - `TEXT`NOT NULL DEFAULT
- **status_reason** - `TEXT`
- **status_datetime** - `TIMESTAMP`
- **sms_code_used** - `TEXT`
- **photo_id** - `UUID`
- **courier_comment** - `TEXT`
- **positions** - `JSONB`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.create_drafts`

- **id** - `BIGSERIAL`PRIMARY KEY
- **organization_id** - `BIGINT`NOT NULL
- **employee_id** - `BIGINT`NOT NULL
- **data** - `JSONB`NOT NULL
- **type** - `VARCHAR(50)`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `VARCHAR(255)`
- **updated_by** - `VARCHAR(255)`

---

#### `applications.applications.employee_transport`

- **id** - `BIGSERIAL`PRIMARY KEY PRIMARY KEY
- **employee_id** - `BIGINT`NOT NULL
- **transport_id** - `BIGINT`NOT NULL
- **organization_id** - `BIGINT`NOT NULL
- **assigned_at** - `TIMESTAMP`NOT NULL DEFAULT
- **unassigned_at** - `TIMESTAMP`
- **active** - `BOOLEAN`NOT NULL DEFAULT
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `applications.applications.invoices`

- **invoice_number** - `TEXT`NOT NULL UNIQUE
- **document_date** - `DATE`
- **customer_organization_id** - `BIGINT`
- **executor_organization_id** - `BIGINT`
- **total_amount_without_vat** - `NUMERIC(19`
- **total_vat_amount** - `NUMERIC(19`
- **total_amount_with_vat** - `NUMERIC(19`
- **file_id** - `UUID`
- **file_name** - `TEXT`
- **status** - `TEXT`
- **executor_signer_full_name** - `TEXT`
- **customer_signer_full_name** - `TEXT`
- **signed_date** - `TIMESTAMP`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.registries`

- **registry_number** - `TEXT`NOT NULL UNIQUE
- **date_from** - `DATE`
- **date_to** - `DATE`
- **act_id** - `BIGINT`
- **customer_organization_id** - `BIGINT`
- **executor_organization_id** - `BIGINT`
- **total_downtime** - `NUMERIC(19`
- **total_insurance** - `NUMERIC(19`
- **total_prr** - `NUMERIC(19`
- **total_security** - `NUMERIC(19`
- **total_sum** - `NUMERIC(19`
- **file_id** - `UUID`
- **file_name** - `TEXT`
- **status** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.transport`

- **vehicle_id** - `BIGINT`NOT NULL
- **status** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `applications.applications.transport_employee`

- **employee_id** - `BIGINT`NOT NULL

---

#### `applications.applications.transportation`

- **organization_id** - `BIGINT`
- **contact_employee_id** - `BIGINT`
- **cargo_type_id** - `BIGINT`
- **tare_type_id** - `BIGINT`
- **cargo_price_currency_code** - `TEXT`
- **vehicle_body_type_id** - `BIGINT`
- **capacity_value_id** - `BIGINT`
- **transportation_type** - `TEXT`NOT NULL
- **status** - `TEXT`NOT NULL
- **filling_step** - `TEXT`NOT NULL
- **deadline_date** - `TIMESTAMP`
- **cargo_name** - `TEXT`
- **cargo_price** - `NUMERIC(15`
- **cargo_weight** - `NUMERIC(15`
- **cargo_weight_unit** - `TEXT`
- **cargo_volume** - `NUMERIC(15`
- **vehicle_capacity** - `NUMERIC(15`
- **capacity_unit** - `TEXT`
- **additional_info** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.transportation_cost`

- **transportation_id** - `BIGINT`NOT NULL
- **executor_organization_id** - `BIGINT`
- **tariff_type** - `TEXT`NOT NULL
- **cost_currency_code** - `TEXT`NOT NULL
- **idle_payment_currency_code** - `TEXT`NOT NULL
- **cost** - `NUMERIC(15`
- **idle_payment** - `NUMERIC(15`
- **idle_payment_time_unit** - `TEXT`
- **payment_delay** - `INT`
- **down_payment** - `NUMERIC(15`
- **transportation_number** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL
- **status** - `TEXT`NOT NULL
- **type** - `TEXT`NOT NULL

---

#### `applications.applications.transportation_selected_executor`

- **transportation_id** - `BIGINT`NOT NULL
- **organization_id** - `BIGINT`NOT NULL

---

#### `applications.applications.user_device_tokens`

- **employee_id** - `BIGINT`
- **device_token** - `TEXT`NOT NULL UNIQUE
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `applications.applications.vehicle`

- **transportation_type** - `TEXT`
- **vehicle_body_type_id** - `BIGINT`
- **image_id** - `BIGINT`
- **executor_organization_id** - `BIGINT`
- **brand** - `TEXT`
- **model** - `TEXT`
- **registration_plate** - `TEXT`
- **issue_year** - `INT`
- **color** - `TEXT`
- **semi_trailer_model** - `TEXT`
- **semi_trailer_registration_plate** - `TEXT`
- **semi_trailer_issue_year** - `INT`
- **power** - `INT`
- **capacity_value** - `INT`
- **cargo_volume** - `INT`
- **registration_certificate_id** - `BIGINT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

---

## 🗂️ Схема `user`

**Пользователи и организации**: управление доступом, профили, KYC данные.

### 📋 Таблицы схемы `user`

#### `user.users.bank_requisite`

- **account_number** - `TEXT`NOT NULL
- **bank** - `TEXT`NOT NULL
- **bic** - `TEXT`NOT NULL
- **organization_id** - `BIGINT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.company_check_data`

- **bin** - `VARCHAR(12)`NOT NULL UNIQUE
- **legal_status** - `VARCHAR(50)`
- **registration_date** - `DATE`
- **tax_debt_amount** - `NUMERIC(14`
- **tax_debt_last_updated** - `DATE`
- **lawsuits_count** - `INTEGER`
- **lawsuits_total_claims** - `NUMERIC(14`
- **affiliates_count** - `INTEGER`
- **credit_status** - `VARCHAR(50)`
- **factoring_deals** - `INTEGER`
- **factoring_overdue** - `INTEGER`
- **licenses_count** - `INTEGER`
- **complaints_count** - `INTEGER`
- **financial_score** - `INTEGER`
- **kompra_data_updated_at** - `TIMESTAMP`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.employee`

- **organization_id** - `BIGINT`NOT NULL
- **employee_status** - `TEXT`NOT NULL
- **email** - `TEXT`NOT NULL
- **phone** - `TEXT`
- **iin** - `TEXT`
- **first_name** - `TEXT`NOT NULL
- **last_name** - `TEXT`
- **middle_name** - `TEXT`
- **is_kz_residence** - `BOOLEAN`
- **telegram_acc** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.employees_roles`

- **role** - `TEXT`NOT NULL

---

#### `user.users.kyc_score`

- **company_check_data_id** - `BIGINT`
- **person_check_data_id** - `BIGINT`
- **total_score** - `INTEGER`
- **legal_status_score** - `INTEGER`
- **legal_status_max_score** - `INTEGER`
- **legal_status_status** - `VARCHAR(255)`
- **tax_discipline_score** - `INTEGER`
- **tax_discipline_max_score** - `INTEGER`
- **tax_discipline_status** - `VARCHAR(255)`
- **lawsuits_score** - `INTEGER`
- **lawsuits_max_score** - `INTEGER`
- **lawsuits_status** - `VARCHAR(255)`
- **credit_history_score** - `INTEGER`
- **credit_history_max_score** - `INTEGER`
- **credit_history_status** - `VARCHAR(255)`
- **factoring_score** - `INTEGER`
- **factoring_max_score** - `INTEGER`
- **factoring_status** - `VARCHAR(255)`
- **dtp_fines_score** - `INTEGER`
- **dtp_fines_max_score** - `INTEGER`
- **dtp_fines_status** - `VARCHAR(255)`
- **customer_reviews_score** - `INTEGER`
- **customer_reviews_max_score** - `INTEGER`
- **customer_reviews_status** - `VARCHAR(255)`
- **order_history_score** - `INTEGER`
- **order_history_max_score** - `INTEGER`
- **order_history_status** - `VARCHAR(255)`
- **documents_score** - `INTEGER`
- **documents_max_score** - `INTEGER`
- **documents_status** - `VARCHAR(255)`
- **license_revocation_score** - `INTEGER`
- **license_revocation_max_score** - `INTEGER`
- **license_revocation_status** - `VARCHAR(255)`
- **criminal_record_score** - `INTEGER`
- **criminal_record_max_score** - `INTEGER`
- **criminal_record_status** - `VARCHAR(255)`
- **fines_score** - `INTEGER`
- **fines_max_score** - `INTEGER`
- **fines_status** - `VARCHAR(255)`
- **dtp_score** - `INTEGER`
- **dtp_max_score** - `INTEGER`
- **dtp_status** - `VARCHAR(255)`
- **medical_restrictions_score** - `INTEGER`
- **medical_restrictions_max_score** - `INTEGER`
- **medical_restrictions_status** - `VARCHAR(255)`
- **created_at** - `TIMESTAMP`
- **updated_at** - `TIMESTAMP`
- **created_by** - `VARCHAR(255)`
- **updated_by** - `VARCHAR(255)`

**Foreign Keys:**
- **REFERENCES**: → `()`
- **users.company_check_data**: → `()`
- **REFERENCES**: → `()`
- **users.person_check_data**: → `()`

---

#### `user.users.organization`

- **business_type** - `TEXT`NOT NULL
- **iin_bin** - `TEXT`NOT NULL
- **organization_status** - `TEXT`NOT NULL
- **organization_name** - `TEXT`NOT NULL
- **legal_address** - `TEXT`
- **actual_address** - `TEXT`
- **vat** - `BOOLEAN`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.organization_employees_roles`

- **role** - `TEXT`NOT NULL
- **organization_id** - `BIGINT`NOT NULL
- **company_type** - `TEXT`NOT NULL
- **assigned_at** - `TIMESTAMP`NOT NULL DEFAULT
- **dismissed_at** - `TIMESTAMP`
- **is_active** - `BOOLEAN`NOT NULL DEFAULT

---

#### `user.users.organization_profile_settings`

- **logo_file_id** - `UUID`
- **certificate_of_registration_file_id** - `UUID`
- **organization_charter_file_id** - `UUID`
- **general_director_appointment_order_file_id** - `UUID`
- **accounting_documents_email** - `TEXT`
- **organization_email** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.person_check_data`

- **iin** - `VARCHAR(20)`NOT NULL UNIQUE
- **passport_status** - `VARCHAR(20)`
- **driving_license_status** - `VARCHAR(20)`
- **license_expiry_date** - `DATE`
- **criminal_record** - `BOOLEAN`
- **criminal_details** - `TEXT`
- **dtp_count** - `INTEGER`DEFAULT
- **dtp_with_fault** - `INTEGER`DEFAULT
- **fines_total_amount** - `NUMERIC(14`
- **fines_count** - `INTEGER`DEFAULT
- **psych_status** - `VARCHAR(20)`
- **narc_status** - `VARCHAR(20)`
- **medical_check_date** - `DATE`
- **transport_license_number** - `TEXT`
- **transport_license_expiry** - `DATE`
- **kompra_data_updated_at** - `TIMESTAMP`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `user.users.profile_settings`

- **icon_file_id** - `UUID`
- **language** - `TEXT`
- **theme_mode** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

---

## 🗂️ Схема `dictionaries`

**Справочники**: страны, валюты, типы грузов, методы погрузки.

### 📋 Таблицы схемы `dictionaries`

#### `dictionaries.dictionaries.capacity_value`

- **capacity_unit** - `TEXT`NOT NULL
- **capacity_value** - `NUMERIC(15`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.cargo_type`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.cities`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **country_id** - `BIGINT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.countries`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.currency`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.factoring_payment_delay_value`

- **id** - `BIGSERIAL`PRIMARY KEY
- **payment_delay_value** - `INTEGER`NOT NULL
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `VARCHAR(255)`
- **updated_at** - `TIMESTAMP`
- **updated_by** - `VARCHAR(255)`

---

#### `dictionaries.dictionaries.loading_method`

- **vehicle_body_type_id** - `BIGINT`NOT NULL
- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.loading_operation`

- **id** - `BIGSERIAL`PRIMARY KEY
- **loading_method_id** - `BIGINT`
- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.payment_delay_value`

- **id** - `BIGSERIAL`PRIMARY KEY
- **payment_delay_value** - `INTEGER`NOT NULL
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `VARCHAR(255)`
- **updated_at** - `TIMESTAMP`
- **updated_by** - `VARCHAR(255)`

---

#### `dictionaries.dictionaries.tare_type`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `dictionaries.dictionaries.vehicle_body_type`

- **name_ru** - `TEXT`NOT NULL
- **name_kk** - `TEXT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

---

## 🗂️ Схема `file`

**Файлы и подписи**: метаданные файлов, цифровые подписи Kalkan.

### 📋 Таблицы схемы `file`

#### `file.file.file_meta_info`

- **minio_file_path** - `TEXT`NOT NULL
- **file_type** - `TEXT`
- **file_name** - `TEXT`
- **file_size** - `BIGINT`
- **description** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `file.file.signature`

- **signed_file_id** - `BIGINT`NOT NULL
- **tsp_gen_time** - `TIMESTAMP`
- **common_name** - `TEXT`
- **sur_name** - `TEXT`
- **email** - `TEXT`
- **iin** - `TEXT`
- **country** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `file.file.static_file`

- **list_order** - `INTEGER`
- **type** - `TEXT`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL
- **FOREIGN** - `KEY`

---

---

## 🗂️ Схема `gis`

**Геопространственные данные**: маршруты, координаты (PostGIS).

### 📋 Таблицы схемы `gis`

#### `gis.GIS.driver_location`

- **transportation_id** - `BIGINT`NOT NULL
- **location** - `GEOGRAPHY(P`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **timestamp** - `TIMESTAMP`
- **speed** - `NUMERIC`
- **heading** - `NUMERIC`
- **accuracy** - `NUMERIC`
- **created_by** - `TEXT`
- **updated_by** - `TEXT`

---

#### `gis.gis.cargo_loading_history`

- **route_history_id** - `BIGINT`NOT NULL
- **previous_cargo_loading_history_id** - `BIGINT`
- **action** - `TEXT`NOT NULL
- **loading_method_id** - `BIGINT`
- **loading_operation_id** - `BIGINT`
- **order_num** - `INTEGER`
- **loading_type** - `TEXT`
- **shipper_bin** - `TEXT`
- **loading_datetime** - `TIMESTAMP`
- **address** - `TEXT`
- **commentary** - `TEXT`
- **weight** - `NUMERIC(15`
- **weight_unit** - `TEXT`
- **volume** - `NUMERIC(15`
- **loading_time_hours** - `INTEGER`
- **contact_number** - `TEXT`
- **contact_person_name** - `TEXT`
- **location** - `GEOGRAPHY(P`
- **is_active** - `BOOLEAN`
- **is_driver_at_location** - `BOOLEAN`
- **original_order_num** - `INTEGER`
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL

---

#### `gis.gis.transportation_route_history`

- **transportation_id** - `BIGINT`NOT NULL
- **version_number** - `INTEGER`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL
- **updated_by** - `TEXT`NOT NULL
- **status** - `TEXT`NOT NULL
- **change_type** - `TEXT`NOT NULL
- **notes** - `TEXT`

---

#### `gis.gis.veh_latest_loc`

- **vehicle_id** - `BIGINT`PRIMARY KEY
- **timestamp** - `TIMESTAMP`NOT NULL
- **accuracy** - `NUMERIC`
- **status** - `TEXT`NOT NULL

---

---

## 🗂️ Схема `factoring`

**Факторинг**: финансовые услуги, тарифы, выплаты.

### 📋 Таблицы схемы `factoring`

#### `factoring.factoring.contract`

- **id** - `BIGSERIAL`PRIMARY KEY
- **factoring_agreement_id** - `UUID`UNIQUE
- **signature_id** - `BIGINT`UNIQUE
- **signed_at** - `TIMESTAMP`
- **signed_by_iin** - `VARCHAR(255)`
- **created_by** - `VARCHAR(255)`
- **updated_by** - `VARCHAR(255)`
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT

---

#### `factoring.factoring.factor`

- **id** - `UUID`PRIMARY KEY
- **name** - `VARCHAR(255)`NOT NULL
- **email** - `VARCHAR(255)`NOT NULL
- **financing_percentage** - `NUMERIC(5`
- **delay_days** - `INTEGER`NOT NULL
- **is_active** - `BOOLEAN`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL
- **updated_at** - `TIMESTAMP`

---

#### `factoring.factoring.factor_tariff`

- **id** - `BIGSERIAL`PRIMARY KEY
- **factor_id** - `UUID`NOT NULL
- **name** - `VARCHAR(255)`NOT NULL
- **min_payment_delay_days** - `INTEGER`NOT NULL
- **max_payment_delay_days** - `INTEGER`NOT NULL
- **tariff_percentage** - `DECIMAL(5`
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **created_by** - `VARCHAR(255)`
- **updated_at** - `TIMESTAMP`
- **updated_by** - `VARCHAR(255)`

---

#### `factoring.factoring.factoring_agreement`

- **id** - `UUID`PRIMARY KEY
- **role** - `VARCHAR(50)`NOT NULL
- **status** - `VARCHAR(50)`NOT NULL
- **contract_url** - `TEXT`
- **signed_contract_url** - `TEXT`
- **organization_id** - `BIGINT`
- **original_file_id** - `UUID`
- **signature_id** - `BIGINT`
- **created_at** - `TIMESTAMP`
- **updated_at** - `TIMESTAMP`
- **signed_at** - `TIMESTAMP`

---

#### `factoring.factoring.payout_request`

- **id** - `UUID`PRIMARY KEY
- **transportation_id** - `BIGINT`NOT NULL
- **factoring_agreement_id** - `UUID`NOT NULL
- **status** - `VARCHAR(50)`NOT NULL
- **amount** - `NUMERIC(15`
- **request_number** - `VARCHAR(100)`NOT NULL UNIQUE
- **organization_id** - `BIGINT`NOT NULL
- **created_at** - `TIMESTAMP`NOT NULL DEFAULT
- **sms_signed_at** - `TIMESTAMP`
- **confirmed_at** - `TIMESTAMP`
- **email_sent_at** - `TIMESTAMP`
- **paid_at** - `TIMESTAMP`
- **original_file_id** - `UUID`

---

---

## 🗂️ Схема `notifications`

**Уведомления**: пуш, SMS, email нотификации.

### 📋 Таблицы схемы `notifications`

#### `notifications.notifications.customer_subscriptions`

- **id** - `BIGSERIAL`PRIMARY KEY
- **user_id** - `BIGINT`NOT NULL
- **customer_organization_id** - `BIGINT`NOT NULL
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.delivery_attempt`

- **id** - `BIGSERIAL`PRIMARY KEY
- **notification_id** - `BIGINT`NOT NULL
- **channel_type** - `VARCHAR(20)`NOT NULL
- **attempt_no** - `INT`NOT NULL
- **priority** - `INT`NOT NULL
- **scheduled_at** - `TIMESTAMPTZ`NOT NULL
- **status** - `VARCHAR(20)`NOT NULL DEFAULT
- **external_msg_id** - `TEXT`
- **error_code** - `TEXT`
- **error_message** - `TEXT`
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.notification`

- **id** - `BIGSERIAL`PRIMARY KEY
- **dedup_key** - `TEXT`UNIQUE
- **user_id** - `BIGINT`NOT NULL
- **title** - `TEXT`
- **body** - `TEXT`
- **template_code** - `TEXT`
- **payload** - `JSONB`
- **status** - `VARCHAR(20)`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **delivered_at** - `TIMESTAMPTZ`
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.notification_blacklist`

- **id** - `BIGSERIAL`PRIMARY KEY
- **contact_type** - `VARCHAR(10)`NOT NULL
- **contact_value** - `VARCHAR(255)`NOT NULL
- **reason** - `VARCHAR(100)`
- **blacklisted_at** - `TIMESTAMP`DEFAULT
- **last_attempt_at** - `TIMESTAMP`

---

#### `notifications.notifications.notification_conversion`

- **id** - `BIGSERIAL`PRIMARY KEY
- **notification_id** - `BIGINT`
- **conversion_type** - `VARCHAR(30)`NOT NULL
- **conversion_value** - `DECIMAL(15`
- **converted_at** - `TIMESTAMP`DEFAULT

---

#### `notifications.notifications.notification_cost`

- **id** - `BIGSERIAL`PRIMARY KEY
- **channel** - `VARCHAR(20)`NOT NULL
- **provider_id** - `VARCHAR(50)`
- **cost_per_message** - `DECIMAL(10`
- **currency** - `VARCHAR(3)`DEFAULT
- **effective_from** - `DATE`NOT NULL
- **effective_to** - `DATE`
- **created_at** - `TIMESTAMP`DEFAULT

---

#### `notifications.notifications.notification_filters`

- **id** - `BIGSERIAL`PRIMARY KEY
- **user_id** - `BIGINT`NOT NULL
- **geo_radius_km** - `INTEGER`DEFAULT
- **geo_latitude** - `DECIMAL(10`
- **geo_longitude** - `DECIMAL(11`
- **geo_type** - `VARCHAR(20)`DEFAULT
- **near_driver** - `BOOLEAN`NOT NULL DEFAULT
- **body_types** - `TEXT`DEFAULT
- **min_capacity** - `DECIMAL(10`
- **max_capacity** - `DECIMAL(10`
- **min_volume** - `DECIMAL(10`
- **max_volume** - `DECIMAL(10`
- **transport_types** - `TEXT`DEFAULT
- **loading_date_from** - `TIMESTAMPTZ`
- **loading_date_to** - `TIMESTAMPTZ`
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.notification_log`

- **id** - `BIGSERIAL`PRIMARY KEY
- **organization_id** - `BIGINT`
- **recipient_user_id** - `BIGINT`
- **notification_type** - `VARCHAR(50)`NOT NULL
- **channel** - `VARCHAR(20)`NOT NULL
- **priority** - `VARCHAR(10)`DEFAULT
- **subject** - `VARCHAR(255)`
- **message** - `TEXT`
- **template_id** - `VARCHAR(50)`
- **template_variables** - `JSONB`
- **sent_at** - `TIMESTAMP`
- **delivered_at** - `TIMESTAMP`
- **delivery_status** - `VARCHAR(20)`DEFAULT
- **delivery_attempts** - `INTEGER`DEFAULT
- **provider_id** - `VARCHAR(50)`
- **external_message_id** - `VARCHAR(100)`
- **opened** - `BOOLEAN`DEFAULT
- **opened_at** - `TIMESTAMP`
- **clicked** - `BOOLEAN`DEFAULT
- **clicked_at** - `TIMESTAMP`
- **replied** - `BOOLEAN`DEFAULT
- **replied_at** - `TIMESTAMP`
- **error_code** - `VARCHAR(50)`
- **error_message** - `TEXT`
- **retry_count** - `INTEGER`DEFAULT
- **next_retry_at** - `TIMESTAMP`
- **related_entity_type** - `VARCHAR(30)`
- **related_entity_id** - `BIGINT`
- **campaign_id** - `VARCHAR(50)`
- **user_agent** - `TEXT`
- **ip_address** - `INET`
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT

---

#### `notifications.notifications.notification_logs`

- **id** - `BIGSERIAL`PRIMARY KEY
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **user_id** - `BIGINT`
- **customer_organization_id** - `BIGINT`
- **transportation_id** - `BIGINT`
- **channel_type** - `VARCHAR(20)`
- **status** - `VARCHAR(20)`NOT NULL
- **message_id** - `TEXT`
- **error_message** - `TEXT`
- **delivered_at** - `TIMESTAMPTZ`
- **attempt** - `INTEGER`NOT NULL DEFAULT
- **scheduled_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **processing_started_at** - `TIMESTAMPTZ`
- **worker_id** - `TEXT`
- **max_attempts** - `INT`NOT NULL DEFAULT
- **backoff_sec** - `INT`NOT NULL DEFAULT
- **notification_id** - `BIGINT`
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.notification_provider`

- **id** - `VARCHAR(50)`PRIMARY KEY
- **name** - `VARCHAR(100)`NOT NULL
- **channel** - `VARCHAR(20)`NOT NULL
- **api_endpoint** - `VARCHAR(255)`
- **api_key_encrypted** - `TEXT`
- **is_active** - `BOOLEAN`DEFAULT
- **max_rate_per_minute** - `INTEGER`DEFAULT
- **reliability_score** - `DECIMAL(3`
- **cost_per_message** - `DECIMAL(10`
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT

---

#### `notifications.notifications.notification_template`

- **id** - `VARCHAR(50)`PRIMARY KEY
- **name** - `VARCHAR(100)`NOT NULL
- **description** - `TEXT`
- **channel** - `VARCHAR(20)`NOT NULL
- **subject_template** - `VARCHAR(255)`
- **body_template** - `TEXT`NOT NULL
- **variables** - `JSONB`
- **is_active** - `BOOLEAN`DEFAULT
- **created_at** - `TIMESTAMP`DEFAULT
- **updated_at** - `TIMESTAMP`DEFAULT

---

#### `notifications.notifications.user_channel_order`

- **id** - `BIGSERIAL`PRIMARY KEY
- **user_id** - `BIGINT`NOT NULL
- **channel_type** - `VARCHAR(32)`NOT NULL
- **priority** - `INTEGER`NOT NULL
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.user_delivery_channels`

- **id** - `BIGSERIAL`PRIMARY KEY
- **user_id** - `BIGINT`NOT NULL
- **channel_type** - `VARCHAR(20)`NOT NULL
- **priority** - `INTEGER`NOT NULL DEFAULT
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **quiet_hours_from** - `TIME`DEFAULT
- **quiet_hours_to** - `TIME`DEFAULT
- **tz** - `TEXT`NOT NULL DEFAULT
- **endpoint** - `TEXT`
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---

#### `notifications.notifications.user_notification_settings`

- **id** - `BIGSERIAL`PRIMARY KEY
- **user_id** - `BIGINT`NOT NULL UNIQUE
- **notification_level** - `VARCHAR(20)`NOT NULL DEFAULT
- **is_active** - `BOOLEAN`NOT NULL DEFAULT
- **timezone** - `TEXT`NOT NULL DEFAULT
- **created_by** - `TEXT`NOT NULL DEFAULT
- **updated_by** - `TEXT`NOT NULL DEFAULT
- **created_at** - `TIMESTAMPTZ`NOT NULL DEFAULT
- **updated_at** - `TIMESTAMPTZ`NOT NULL DEFAULT

---


---

## 📊 Статистика генерации

**Всего схем обработано**:        7
**Всего таблиц найдено**: 69
**Всего колонок найдено**: 773
**Всего Foreign Key найдено**: 2
**Всего Primary Key найдено**: 0

---
*Автоматически сгенерировано скриптом generate-db-architecture.sh*  
*Для обновления запустите: `./generate-db-architecture.sh`*
