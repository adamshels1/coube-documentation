#!/bin/bash

# Скрипт для автоматической генерации полной архитектуры БД из миграций Flyway
# Парсит SQL файлы и создает актуальную документацию с полями и связями

set -e

# Цвета для вывода  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Константы
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKEND_DIR="$PROJECT_ROOT/coube-backend"
MIGRATIONS_DIR="$BACKEND_DIR/src/main/resources/db/migration"
DOCS_DIR="$SCRIPT_DIR"
OUTPUT_FILE="$DOCS_DIR/database-architecture-auto-generated.md"
TEMP_DIR="$(mktemp -d)"

echo -e "${BLUE}🏗️  Генерация полной архитектуры базы данных Coube${NC}"
echo -e "${BLUE}=====================================================${NC}"

# Проверка зависимостей
if ! command -v awk &> /dev/null; then
    echo -e "${RED}❌ Требуется awk${NC}"
    exit 1
fi

if ! command -v sed &> /dev/null; then
    echo -e "${RED}❌ Требуется sed${NC}"
    exit 1
fi

if [ ! -d "$MIGRATIONS_DIR" ]; then
    echo -e "${RED}❌ Директория миграций не найдена: $MIGRATIONS_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Найдены директории и зависимости${NC}"
echo -e "   📁 Миграции: $MIGRATIONS_DIR"
echo -e "   📁 Выходной файл: $OUTPUT_FILE"
echo

# Временные файлы для анализа
TABLES_FILE="$TEMP_DIR/tables.txt"
COLUMNS_FILE="$TEMP_DIR/columns.txt"
FOREIGN_KEYS_FILE="$TEMP_DIR/foreign_keys.txt"
SCHEMAS_FILE="$TEMP_DIR/schemas.txt"

# Функция для парсинга CREATE TABLE - исправленная версия
parse_create_table() {
    local sql_file="$1"
    local schema_name="$2"
    
    # Читаем весь файл в переменную для многострочной обработки
    local content=$(cat "$sql_file")
    
    # Удаляем комментарии SQL (-- и /**/)
    content=$(echo "$content" | sed 's/--.*$//g' | sed 's|/\*.*\*/||g')
    
    local in_table=0
    local current_table=""
    local current_schema=""
    local table_content=""
    
    # Обрабатываем построчно, но учитываем многострочные конструкции
    while IFS= read -r line; do
        # Удаляем лишние пробелы
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Пропускаем пустые строки
        [[ -z "$line" ]] && continue
        
        # Ищем CREATE TABLE (улучшенная регулярка)
        if [[ "$line" =~ ^CREATE[[:space:]]+TABLE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
            table_full_name="${BASH_REMATCH[2]}"
            
            # Разбираем схему и имя таблицы
            if [[ "$table_full_name" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\\.([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
                current_schema="${BASH_REMATCH[1]}"
                current_table="${BASH_REMATCH[2]}"
            else
                current_schema="$schema_name"
                current_table="$table_full_name"
            fi
            
            # Записываем таблицу
            echo "TABLE|$current_schema|$current_table" >> "$TABLES_FILE"
            in_table=1
            table_content=""
            continue
        fi
        
        # Собираем содержимое таблицы
        if [[ $in_table -eq 1 ]]; then
            table_content="$table_content$line "
            
            # Проверяем окончание таблицы
            if [[ "$line" =~ ^\)\;?$ ]]; then
                # Парсим все содержимое таблицы
                parse_table_content "$table_content" "$current_schema" "$current_table"
                in_table=0
                current_table=""
                current_schema=""
                table_content=""
            fi
        fi
    done <<< "$content"
}

# Функция для парсинга содержимого таблицы
parse_table_content() {
    local content="$1"
    local schema="$2" 
    local table="$3"
    
    # Убираем лишние пробелы и разбиваем по запятым, но аккуратно обрабатываем CONSTRAINT
    content=$(echo "$content" | tr -s ' ')
    
    # Разбиваем на строки по запятым, но сохраняем CONSTRAINT блоки целыми
    local lines=""
    local current_line=""
    local in_constraint=0
    
    while IFS= read -r part; do
        part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$part" ]] && continue
        
        if [[ "$part" =~ ^CONSTRAINT ]]; then
            in_constraint=1
            current_line="$part"
        elif [[ $in_constraint -eq 1 ]]; then
            current_line="$current_line $part"
            if [[ "$part" =~ \) ]]; then
                lines="$lines$current_line"$'\n'
                current_line=""
                in_constraint=0
            fi
        else
            lines="$lines$part"$'\n'
        fi
    done <<< "$(echo "$content" | sed 's/,/\n/g')"
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        
        # Обрабатываем CONSTRAINT с FOREIGN KEY (упрощенная версия)
        if [[ "$line" =~ CONSTRAINT.*FOREIGN.*KEY.*REFERENCES[[:space:]]+([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
            ref_table="${BASH_REMATCH[1]}"
            # Извлекаем имя constraint'а
            if [[ "$line" =~ CONSTRAINT[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                constraint_name="${BASH_REMATCH[1]}"
            else
                constraint_name="fk_constraint"
            fi
            echo "FOREIGN_KEY|$schema|$table|$constraint_name|$ref_table|id" >> "$TABLES_FILE"
            continue
        fi
        
        # Обрабатываем CONSTRAINT с PRIMARY KEY (упрощенная версия)
        if [[ "$line" =~ CONSTRAINT.*PRIMARY[[:space:]]+KEY ]]; then
            if [[ "$line" =~ CONSTRAINT[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                constraint_name="${BASH_REMATCH[1]}"
            else
                constraint_name="pk_constraint"
            fi
            echo "PRIMARY_KEY|$schema|$table|$constraint_name|id" >> "$TABLES_FILE"
            continue
        fi
        
        # Пропускаем другие служебные конструкции
        if [[ "$line" =~ ^(CONSTRAINT|PRIMARY[[:space:]]+KEY|UNIQUE|CHECK|INDEX) ]]; then
            continue
        fi
        
        # Парсим колонки: имя_колонки ТИП [атрибуты]
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+([A-Z][A-Z0-9_()]*|BIGINT|TIMESTAMP|TEXT|BOOLEAN|NUMERIC|VARCHAR|BIGSERIAL|UUID|DATE|TIME|INT|INTEGER|DECIMAL) ]]; then
            column_name="${BASH_REMATCH[1]}"
            column_type="${BASH_REMATCH[2]}"
            
            # Извлекаем дополнительные типы данных
            if [[ "$line" =~ GENERATED[[:space:]]+ALWAYS[[:space:]]+AS[[:space:]]+IDENTITY ]]; then
                column_type="BIGSERIAL"
            elif [[ "$line" =~ VARCHAR\(([0-9]+)\) ]]; then
                column_type="VARCHAR(${BASH_REMATCH[1]})"
            elif [[ "$line" =~ NUMERIC\(([0-9,]+)\) ]]; then
                column_type="NUMERIC(${BASH_REMATCH[1]})"
            elif [[ "$line" =~ DECIMAL\(([0-9,]+)\) ]]; then
                column_type="DECIMAL(${BASH_REMATCH[1]})"
            fi
            
            # Собираем атрибуты
            attributes=""
            [[ "$line" =~ NOT[[:space:]]+NULL ]] && attributes+="NOT NULL "
            [[ "$line" =~ PRIMARY[[:space:]]+KEY ]] && attributes+="PRIMARY KEY "
            [[ "$line" =~ UNIQUE ]] && attributes+="UNIQUE "
            [[ "$line" =~ DEFAULT ]] && attributes+="DEFAULT "
            [[ "$line" =~ GENERATED[[:space:]]+ALWAYS[[:space:]]+AS[[:space:]]+IDENTITY ]] && attributes+="PRIMARY KEY "
            
            echo "COLUMN|$schema|$table|$column_name|$column_type|$attributes" >> "$TABLES_FILE"
        fi
    done <<< "$lines"
}

# Функция для парсинга ALTER TABLE - исправленная версия
parse_alter_table() {
    local sql_file="$1"
    local schema_name="$2"
    
    # Читаем весь файл и удаляем комментарии
    local content=$(cat "$sql_file" | sed 's/--.*$//g')
    
    while IFS= read -r line; do
        # Удаляем лишние пробелы
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Пропускаем пустые строки
        [[ -z "$line" ]] && continue
        
        # Ищем ALTER TABLE (улучшенная регулярка)
        if [[ "$line" =~ ALTER[[:space:]]+TABLE[[:space:]]+([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
            table_full_name="${BASH_REMATCH[1]}"
            
            # Разбираем схему и имя таблицы
            if [[ "$table_full_name" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\\.([a-zA-Z_][a-zA-Z0-9_]*)$ ]]; then
                current_schema="${BASH_REMATCH[1]}"
                current_table="${BASH_REMATCH[2]}"
            else
                current_schema="$schema_name"
                current_table="$table_full_name"
            fi
            
            # ADD COLUMN (улучшенная регулярка для разных типов данных)
            if [[ "$line" =~ ADD[[:space:]]+COLUMN[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]+([A-Z][A-Z0-9_()]*|BIGINT|TIMESTAMP|TEXT|BOOLEAN|NUMERIC|VARCHAR) ]]; then
                column_name="${BASH_REMATCH[1]}"
                column_type="${BASH_REMATCH[2]}"
                
                # Улучшенное извлечение типов данных
                if [[ "$line" =~ VARCHAR\(([0-9]+)\) ]]; then
                    column_type="VARCHAR(${BASH_REMATCH[1]})"
                elif [[ "$line" =~ NUMERIC\(([0-9,]+)\) ]]; then
                    column_type="NUMERIC(${BASH_REMATCH[1]})"
                fi
                
                # Собираем атрибуты
                attributes=""
                [[ "$line" =~ NOT[[:space:]]+NULL ]] && attributes+="NOT NULL "
                [[ "$line" =~ DEFAULT ]] && attributes+="DEFAULT "
                
                echo "COLUMN|$current_schema|$current_table|$column_name|$column_type|$attributes" >> "$TABLES_FILE"
            fi
            
            # ADD FOREIGN KEY
            if [[ "$line" =~ FOREIGN[[:space:]]+KEY.*REFERENCES[[:space:]]+([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
                ref_table="${BASH_REMATCH[1]}"
                echo "FOREIGN_KEY|$current_schema|$current_table|REFERENCES $ref_table" >> "$TABLES_FILE"
            fi
        fi
    done <<< "$content"
}

# Функция для обработки схемы
process_schema_files() {
    local schema_name="$1"
    local schema_dir="$MIGRATIONS_DIR/$schema_name"
    
    if [ ! -d "$schema_dir" ]; then
        echo -e "${YELLOW}⚠️  Схема $schema_name не найдена${NC}"
        return
    fi
    
    echo -e "${BLUE}🔍 Парсинг схемы: $schema_name${NC}"
    echo "$schema_name" >> "$SCHEMAS_FILE"
    
    # Обрабатываем все миграции в хронологическом порядке
    find "$schema_dir" -name "*.sql" | sort | while read -r sql_file; do
        echo -e "   📄 $(basename "$sql_file")"
        parse_create_table "$sql_file" "$schema_name"
        parse_alter_table "$sql_file" "$schema_name"
    done
}

# Функция для генерации Mermaid диаграммы
generate_mermaid_diagram() {
    local schema="$1"
    local output_section="$2"
    
    echo "### Диаграмма связей схемы \`$schema\`" >> "$output_section"
    echo "" >> "$output_section"
    echo '```mermaid' >> "$output_section"
    echo 'erDiagram' >> "$output_section"
    
    # Генерируем таблицы с полями
    awk -F'|' -v schema="$schema" '
    $1 == "TABLE" && $2 == schema {
        tables[++table_count] = $3
        table_schemas[$3] = $2
    }
    $1 == "COLUMN" && $2 == schema {
        columns[$3] = columns[$3] "\n        " $4 " " $5 " " $6
    }
    END {
        for (i = 1; i <= table_count; i++) {
            table = tables[i]
            print "    " toupper(table) " {"
            if (columns[table] != "") {
                print columns[table]
            }
            print "    }"
            print ""
        }
    }
    ' "$TABLES_FILE" >> "$output_section"
    
    # Генерируем связи
    awk -F'|' -v schema="$schema" '
    $1 == "FOREIGN_KEY" && $2 == schema {
        fk_info = $4
        table = $3
        # Простой парсинг REFERENCES
        if (match(fk_info, /REFERENCES ([a-zA-Z_][a-zA-Z0-9_]*\.)?([a-zA-Z_][a-zA-Z0-9_]*)/)) {
            ref = substr(fk_info, RSTART, RLENGTH)
            gsub(/REFERENCES /, "", ref)
            if (index(ref, ".") > 0) {
                split(ref, parts, ".")
                ref_table = parts[2]
            } else {
                ref_table = ref
            }
            print "    " toupper(ref_table) " ||--o{ " toupper(table) " : \"связь\""
        }
    }
    ' "$TABLES_FILE" >> "$output_section"
    
    echo '```' >> "$output_section"
    echo "" >> "$output_section"
}

# Функция для генерации простого описания таблиц (как в manual example)
generate_simple_table_descriptions() {
    local schema="$1"
    local output_section="$2"
    
    echo "### 📋 Таблицы схемы \`$schema\`" >> "$output_section"
    echo "" >> "$output_section"
    
    # Сначала получаем список таблиц
    local tables=($(awk -F'|' -v schema="$schema" '$1 == "TABLE" && $2 == schema {print $3}' "$TABLES_FILE" | sort -u))
    
    for table in "${tables[@]}"; do
        echo "#### \`$schema.$table\`" >> "$output_section"
        echo "" >> "$output_section"
        
        # Получаем колонки для этой таблицы
        awk -F'|' -v schema="$schema" -v table="$table" '
        $1 == "COLUMN" && $2 == schema && $3 == table {
            column = $4
            type = $5
            attrs = $6
            # Очищаем атрибуты от лишних пробелов
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", attrs)
            if (attrs != "") {
                print "- **" column "** - `" type "`" attrs
            } else {
                print "- **" column "** - `" type "`"
            }
        }
        ' "$TABLES_FILE" >> "$output_section"
        
        # Добавляем PRIMARY KEY если есть
        local pks=($(awk -F'|' -v schema="$schema" -v table="$table" '$1 == "PRIMARY_KEY" && $2 == schema && $3 == table {print $5}' "$TABLES_FILE"))
        if [ ${#pks[@]} -gt 0 ]; then
            echo "" >> "$output_section"
            echo "**Primary Key:** \`${pks[0]}\`" >> "$output_section"
        fi
        
        # Добавляем FOREIGN KEY связи если есть
        local fk_info=($(awk -F'|' -v schema="$schema" -v table="$table" '$1 == "FOREIGN_KEY" && $2 == schema && $3 == table {print $4 "|" $5 "|" $6}' "$TABLES_FILE"))
        if [ ${#fk_info[@]} -gt 0 ]; then
            echo "" >> "$output_section"
            echo "**Foreign Keys:**" >> "$output_section"
            for fk_line in "${fk_info[@]}"; do
                IFS='|' read -r constraint_name ref_table ref_columns <<< "$fk_line"
                echo "- **$constraint_name**: → \`$ref_table($ref_columns)\`" >> "$output_section"
            done
        fi
        
        echo "" >> "$output_section"
        echo "---" >> "$output_section"
        echo "" >> "$output_section"
    done
}

# Основная логика генерации
generate_full_architecture() {
    echo -e "${PURPLE}📊 Генерирую полную архитектуру БД...${NC}"
    
    # Создаем заголовок документа
    cat > "$OUTPUT_FILE" << EOF
# Архитектура базы данных Coube

**Дата обновления**: $(date '+%Y-%m-%d %H:%M:%S')  
**Источник**: Автоматически сгенерировано из Flyway миграций

> ⚠️ **Внимание**: Этот файл создается автоматически. Для ручного редактирования используйте \`database-architecture-complete.md\`

## 📊 Обзор схем БД

Система использует **PostgreSQL** с **PostGIS** расширением для геопространственных данных.

EOF

    # Обрабатываем каждую схему
    local schemas=("applications" "user" "dictionaries" "file" "gis" "factoring" "notifications")
    
    for schema in "${schemas[@]}"; do
        if [ -d "$MIGRATIONS_DIR/$schema" ]; then
            echo -e "${BLUE}🔧 Генерирую документацию для схемы: $schema${NC}"
            
            # Создаем секцию для схемы
            echo "---" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            echo "## 🗂️ Схема \`$schema\`" >> "$OUTPUT_FILE"
            echo "" >> "$OUTPUT_FILE"
            
            # Описание схемы
            case "$schema" in
                "applications")
                    echo "**Основная бизнес-логика**: перевозки, контракты, инвойсы, акты, соглашения." >> "$OUTPUT_FILE"
                    ;;
                "user")
                    echo "**Пользователи и организации**: управление доступом, профили, KYC данные." >> "$OUTPUT_FILE"
                    ;;
                "dictionaries")
                    echo "**Справочники**: страны, валюты, типы грузов, методы погрузки." >> "$OUTPUT_FILE"
                    ;;
                "file")
                    echo "**Файлы и подписи**: метаданные файлов, цифровые подписи Kalkan." >> "$OUTPUT_FILE"
                    ;;
                "gis")
                    echo "**Геопространственные данные**: маршруты, координаты (PostGIS)." >> "$OUTPUT_FILE"
                    ;;
                "factoring")
                    echo "**Факторинг**: финансовые услуги, тарифы, выплаты." >> "$OUTPUT_FILE"
                    ;;
                "notifications")
                    echo "**Уведомления**: пуш, SMS, email нотификации." >> "$OUTPUT_FILE"
                    ;;
            esac
            echo "" >> "$OUTPUT_FILE"
            
            # Генерируем простые описания таблиц
            generate_simple_table_descriptions "$schema" "$OUTPUT_FILE"
        fi
    done
    
    # Добавляем footer
    cat >> "$OUTPUT_FILE" << 'EOF'

---

## 📊 Статистика генерации

EOF

    echo "**Всего схем обработано**: $(wc -l < "$SCHEMAS_FILE" 2>/dev/null || echo "0")" >> "$OUTPUT_FILE"
    echo "**Всего таблиц найдено**: $(awk -F'|' '$1=="TABLE" {count++} END {print count+0}' "$TABLES_FILE")" >> "$OUTPUT_FILE"  
    echo "**Всего колонок найдено**: $(awk -F'|' '$1=="COLUMN" {count++} END {print count+0}' "$TABLES_FILE")" >> "$OUTPUT_FILE"
    echo "**Всего Foreign Key найдено**: $(awk -F'|' '$1=="FOREIGN_KEY" {count++} END {print count+0}' "$TABLES_FILE")" >> "$OUTPUT_FILE"
    echo "**Всего Primary Key найдено**: $(awk -F'|' '$1=="PRIMARY_KEY" {count++} END {print count+0}' "$TABLES_FILE")" >> "$OUTPUT_FILE"
    
    cat >> "$OUTPUT_FILE" << 'EOF'

---
*Автоматически сгенерировано скриптом generate-db-architecture.sh*  
*Для обновления запустите: `./generate-db-architecture.sh`*
EOF

    echo -e "${GREEN}✅ Архитектура сгенерирована: $(basename "$OUTPUT_FILE")${NC}"
}

# Очистка временных файлов
cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Проверка аргументов
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << 'EOF'
Скрипт для автоматической генерации полной архитектуры БД из миграций

Использование:
  ./generate-db-architecture.sh        Сгенерировать архитектуру
  ./generate-db-architecture.sh --help Показать справку

Результат:
  - Создается файл database-architecture-auto-generated.md
  - Парсятся все CREATE TABLE и ALTER TABLE statements
  - Извлекаются все колонки с типами и атрибутами  
  - Генерируются диаграммы Mermaid для каждой схемы
  - Создаются описания всех таблиц и связей

Зависимости: awk, sed
EOF
    exit 0
fi

# Основная логика
main() {
    echo -e "${YELLOW}🔄 Инициализация временных файлов...${NC}"
    
    # Создаем временные файлы
    touch "$TABLES_FILE" "$COLUMNS_FILE" "$FOREIGN_KEYS_FILE" "$SCHEMAS_FILE"
    
    echo -e "${YELLOW}🔍 Парсинг SQL миграций...${NC}"
    echo
    
    # Обрабатываем каждую схему
    local schemas=("applications" "user" "dictionaries" "file" "gis" "factoring" "notifications")
    
    for schema in "${schemas[@]}"; do
        process_schema_files "$schema"
    done
    
    echo
    echo -e "${YELLOW}📋 Найдено объектов:${NC}"
    echo -e "   🗂️  Схемы: $(wc -l < "$SCHEMAS_FILE" 2>/dev/null || echo "0")"
    echo -e "   📋 Таблицы: $(awk -F'|' '$1=="TABLE" {count++} END {print count+0}' "$TABLES_FILE")"
    echo -e "   📊 Колонки: $(awk -F'|' '$1=="COLUMN" {count++} END {print count+0}' "$TABLES_FILE")"
    echo -e "   🔑 Primary Keys: $(awk -F'|' '$1=="PRIMARY_KEY" {count++} END {print count+0}' "$TABLES_FILE")"
    echo -e "   🔗 Foreign Keys: $(awk -F'|' '$1=="FOREIGN_KEY" {count++} END {print count+0}' "$TABLES_FILE")"
    echo
    
    # Генерируем финальную архитектуру
    generate_full_architecture
    
    echo
    echo -e "${GREEN}🎉 Генерация завершена!${NC}"
    echo -e "${BLUE}📄 Создан файл: $(basename "$OUTPUT_FILE")${NC}"
    echo -e "${BLUE}💡 Для просмотра: cat $OUTPUT_FILE${NC}"
    echo
}

# Запуск
main "$@"