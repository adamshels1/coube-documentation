# Задача: Импорт заявок из Excel в черновик

## Описание

Реализовать на фронтенде возможность загрузки Excel-файла (`.xlsx`) с данными заявок и сохранение каждой строки как черновик заявки через существующий API.

Шаблон Excel: `shablon_importa_zayavok.xlsx` (в этой же папке).

---

## Текущее состояние

- В `TransportationCreateForm.vue` (строка 165) уже есть **заблокированная кнопка**:
  ```html
  <base-button color="success" size="small" class="action-button" disabled>
    Загрузить из Excel2
  </base-button>
  ```
- Библиотека для парсинга Excel **не установлена**
- API для сохранения черновиков **уже работает**: `POST /api/v1/customer/create-drafts`

---

## Что нужно сделать

### 1. Установить библиотеку

```bash
npm install xlsx
```

### 2. Активировать кнопку "Загрузить из Excel"

**Файл:** `src/components/TransportationCreateForm/TransportationCreateForm.vue`

- Убрать атрибут `disabled`
- Переименовать текст кнопки в `Загрузить из Excel`
- По нажатию — открывать `<input type="file" accept=".xlsx,.xls" />` (скрытый)

### 3. Создать утилиту парсинга Excel

**Создать файл:** `src/utils/excelImport.ts`

Утилита должна:
1. Принять `File` объект
2. Распарсить Excel через библиотеку `xlsx`
3. Читать лист "Заявки" (первый лист)
4. Пропустить строку заголовков (строка 1)
5. Для каждой строки данных — смаппить колонки на поля формы

### 4. Маппинг колонок Excel -> поля формы

Колонки Excel соответствуют полям формы следующим образом:

| # | Колонка Excel | Поле формы | Тип | Примечание |
|---|---|---|---|---|
| A | № | — | number | Порядковый номер, игнорировать |
| B | Тип груза | `cargoType` | select(id) | Маппить name_ru -> id из справочника |
| C | Тип кузова ТС | `bodyType` | select(id) | Маппить name_ru -> id из справочника |
| D | Грузоподъемность ТС (тонн) | `capacityValue` | select(id) | Маппить capacity_value -> id из справочника |
| E | Стоимость перевозки (тенге) | `cargoPrice` | number | |
| F | Тариф перевозки | `tariffType` | select(code) | Маппить русское название -> code |
| G | Дни отсрочки оплаты | `paymentDelayId` | select(id) | Маппить payment_delay_value -> id из справочника |
| H | Страхование груза | `insuranceService` | string | "Да" -> "yes", "Нет" -> "no" |
| I | Дата/время погрузки | `routePoints[0].dateTime` | string | Формат: `YYYY-MM-DD HH:MM` |
| J | Адрес погрузки | `routePoints[0].address` | string | |
| K | Вес погрузки (тонн) | `routePoints[0].weight` | number | |
| L | Объем погрузки (м3) | `routePoints[0].volume` | number | |
| M | БИН грузоотправителя | `routePoints[0].bin` | string | 12 цифр, необязательное |
| N | Контактное лицо (погрузка) | `routePoints[0].contactName` | string | Необязательное |
| O | Телефон (погрузка) | `routePoints[0].contactPhone` | string | Необязательное |
| P | Дата/время разгрузки | `routePoints[1].dateTime` | string | Формат: `YYYY-MM-DD HH:MM` |
| Q | Адрес разгрузки | `routePoints[1].address` | string | |
| R | Вес разгрузки (тонн) | `routePoints[1].weight` | number | |
| S | Объем разгрузки (м3) | `routePoints[1].volume` | number | |
| T | БИН грузополучателя | `routePoints[1].bin` | string | 12 цифр, необязательное |
| U | Контактное лицо (разгрузка) | `routePoints[1].contactName` | string | Необязательное |
| V | Телефон (разгрузка) | `routePoints[1].contactPhone` | string | Необязательное |
| W | Комментарий | `routePoints[0].commentary` | string | Необязательное |

### 5. Маппинг справочников (name_ru -> id/code)

Для корректного маппинга текстовых значений из Excel в ID/коды формы, нужно использовать **уже загруженные справочники** из `useDirectoriesStore()`.

#### Тип груза (cargo_type)

| id | name_ru |
|----|---------|
| 1 | Автомашины, сельхозтехника и запчасти к ним |
| 2 | Природные ресурсы (камень, руды и т. п.) |
| 3 | Черные и цветные металлы |
| 4 | Строительные материалы |
| 5 | Алкоголь, табак |
| 6 | Медицинское оборудование |
| 7 | Компьютеры, оргтехника и компоненты к ним |
| 8 | Грузы, требующие температурного режима |
| 9 | Мебель |
| 10 | Фармацевтическая продукция |
| 11 | Полиграфические и канцелярские товары |
| 12 | Продукты питания, не скоропортящиеся |
| 13 | Оборудование для производства |
| 14 | Бытовая химия/косметика |
| 15 | Одежда, обувь |
| 16 | Товары народного потребления (ТНП) |
| 26 | Металлические изделия |
| 27 | Бытовая техника |
| 28 | Битум |

#### Тип кузова ТС (vehicle_body_type)

| id | name_ru |
|----|---------|
| 1 | Тентованный и шторный |
| 2 | Рефрижераторный (-18) |
| 3 | Изотермический |
| 4 | Промтоварный фургон |
| 5 | Автовоз |
| 6 | Контейнеровоз |
| 7 | Бортовой |
| 8 | Цистерна |
| 12 | Трал |
| 13 | Рефрижератор (+2 +4) |

#### Грузоподъемность ТС (capacity_value, unit=TONN)

| id | capacity_value (тонн) |
|----|----------------------|
| 1 | 0.7 |
| 2 | 1 |
| 3 | 1.5 |
| 4 | 2 |
| 5 | 3 |
| 6 | 5 |
| 7 | 7 |
| 8 | 10 |
| 9 | 20 |
| 21 | 25 |
| 22 | 26.5 |
| 23 | 27 |

#### Тариф перевозки (enum TariffType)

| code | name_ru |
|------|---------|
| FREIGHT | Фрахт |
| BY_WORK_TIME | По времени работы |
| BY_CARGO_WEIGHT | По весу груза |
| BY_CARGO_VOLUME | По объему груза |

#### Дни отсрочки оплаты (payment_delay_value, type=STANDARD)

| id | payment_delay_value (дней) |
|----|---------------------------|
| 1 | 0 |
| 7 | 3 |
| 8 | 7 |
| 2 | 14 |
| 9 | 21 |
| 3 | 30 |
| 4 | 45 |
| 5 | 60 |
| 6 | 90 |

---

### 6. Логика сохранения в черновик

Каждая распарсенная строка Excel сохраняется как черновик через существующий API:

```typescript
// API: POST /api/v1/customer/create-drafts
await api.application.saveDraft({
  data: JSON.stringify(draftData),
  type: 'TRANSPORTATION',
});
```

Структура `draftData` (как в `saveDraft()` из `ApplicationsAddPage.vue`):

```typescript
const draftData = {
  // Данные заявки
  cargoType: cargoTypeId,          // number (id из справочника)
  bodyType: bodyTypeId,            // number (id из справочника)
  tariffType: tariffTypeCode,      // string (код: "FREIGHT", "BY_WORK_TIME" и т.д.)
  capacityValue: capacityValueId,  // number (id из справочника)
  cargoPrice: costValue,           // number (в тенге)
  cargoValue: null,                // number | null (стоимость груза, если страхование=Да)

  // Дополнительные услуги
  loaderService: "no",
  escortService: "no",
  insuranceService: "yes" | "no",

  // Маршрут
  routePoints: [
    {
      id: 1,
      type: "loading",
      isExpanded: true,
      dateTime: "2026-03-15T09:00",  // ISO формат
      weight: 26.5,
      weightUnit: "TONS",
      volume: 30,
      volumeUnit: "M3",
      address: "г. Шымкент, ул. Толе би, промзона",
      bin: "123456789012",
      companyName: "",               // Заполнится автоматически по БИН
      contactName: "Иванов И.И.",
      contactPhone: "+77001234567",
      coordinates: [],               // Пустые — геокодинг произойдет при открытии формы
      hasAdditionalConditions: false,
      loadingMethod: { id: 1 },
      loadingTimeMinutes: null,
      commentary: "",
      waybillNumber: "",
    },
    {
      id: 2,
      type: "unloading",
      isExpanded: true,
      dateTime: "2026-03-16T14:00",
      weight: 26.5,
      weightUnit: "TONS",
      volume: 30,
      volumeUnit: "M3",
      address: "г. Караганда, промзона Майкудук",
      bin: "987654321012",
      companyName: "",
      contactName: "Петров П.П.",
      contactPhone: "+77009876543",
      coordinates: [],
      hasAdditionalConditions: false,
      loadingMethod: { id: 1 },
      loadingTimeMinutes: null,
      commentary: "",
      waybillNumber: "",
    },
  ],

  // Стоимость
  downPayment: null,
  paymentDelayId: paymentDelayId,   // number (id из справочника)
  paymentDelay: paymentDelayValue,  // number (количество дней)
  idlePayment: null,
  idlePaymentTimeUnit: "HOUR",
  isNdsEnabled: false,
  isFactoringEnabled: false,

  // Контактное лицо (из текущего пользователя)
  contactPerson: null,              // Будет установлено при открытии формы
};
```

---

### 7. UI/UX

#### Сценарий пользователя:
1. Пользователь нажимает кнопку **"Загрузить из Excel"** на странице создания заявки
2. Открывается файловый диалог (только `.xlsx`, `.xls`)
3. После выбора файла:
   - Показать **спиннер/лоадер**
   - Распарсить Excel
   - Провести **валидацию** каждой строки
4. Показать **превью результата**:
   - Количество найденных заявок
   - Список ошибок (если есть)
   - Таблица с распарсенными данными
5. Кнопка **"Сохранить в черновики"**
6. После сохранения — **toast уведомление** об успехе
7. Редирект на страницу черновиков или остаться на текущей

#### Обработка ошибок:
- Если файл не `.xlsx` — показать ошибку "Неверный формат файла. Загрузите файл в формате .xlsx"
- Если лист "Заявки" не найден — парсить первый лист
- Если обязательное поле пустое — отметить строку красным, показать какое поле пустое
- Если значение не найдено в справочнике — отметить ячейку красным, показать допустимые значения
- Пустые строки — пропускать

---

### 8. Валидация при парсинге

Обязательные поля (если пустое — ошибка строки):
- Тип груза (B)
- Тип кузова ТС (C)
- Грузоподъемность ТС (D)
- Стоимость перевозки (E) — число > 0
- Тариф перевозки (F)
- Дни отсрочки оплаты (G)
- Страхование груза (H)
- Дата/время погрузки (I) — валидный формат даты
- Адрес погрузки (J) — непустая строка
- Вес погрузки (K) — число > 0
- Объем погрузки (L) — число > 0
- Дата/время разгрузки (P) — валидный формат даты
- Адрес разгрузки (Q) — непустая строка
- Вес разгрузки (R) — число > 0
- Объем разгрузки (S) — число > 0

---

### 9. Ключевые файлы для работы

| Файл | Описание |
|------|----------|
| `src/components/TransportationCreateForm/TransportationCreateForm.vue` | Кнопка "Загрузить из Excel" (строка 165) |
| `src/views/Applications/ApplicationsCreate/ApplicationsAddPage.vue` | Основная форма заявки (3859 строк) |
| `src/api/application.ts` | API: `saveDraft()` |
| `src/store/directories.ts` | Стор справочников |
| `src/api/directories.ts` | API справочников |
| `src/types/interfaces/transportationComplete.ts` | Типы для запроса создания заявки |

---

### 10. Важно

- **НДС** — по умолчанию `false` (можно не включать в Excel)
- **Факторинг** — по умолчанию `false`
- **Валюта** — по умолчанию `KZT` (тенге)
- **Единица веса** — по умолчанию `TONS`
- **Единица объема** — по умолчанию `M3`
- **Координаты** — оставить пустыми `[]`, геокодинг произойдет при открытии черновика в форме
- **capacityUnit** — по умолчанию `TONN` (т.к. грузоподъемность в тоннах)
- **Тип перевозки** — всегда `FTL` (магистральные)
- API черновиков **перезаписывает** предыдущий черновик при каждом вызове. Если нужно сохранить несколько заявок — нужно либо создавать каждую как полную заявку, либо доработать бэк для множественных черновиков.
