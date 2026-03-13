# Интеграция поиска адресов с Яндекс.Картами

Универсальная инструкция для реализации автоподсказок адресов (как на официальном сайте Яндекс.Карт) для любого фронтенд-фреймворка.

---

## Обзор

Система использует официальные API Яндекса:
- **Yandex Geosuggest API** - для получения подсказок адресов при вводе
- **Yandex Geocoder API** - для получения точных координат выбранного адреса

---

## 1. API ключи

Вам понадобятся 2 API ключа от Яндекса:

1. **API ключ для Suggest** (подсказки адресов)
2. **API ключ для Geocoder** (геокодирование)

Получить можно здесь: https://developer.tech.yandex.ru/

---

## 2. API для подсказок адресов (Suggest)

### Endpoint
```
GET https://suggest-maps.yandex.ru/v1/suggest
```

### Параметры запроса

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `apikey` | string | Да | Ваш API ключ |
| `text` | string | Да | Текст запроса пользователя (минимум 3 символа) |
| `lang` | string | Нет | Язык ответа (например: `ru_KZ`, `ru_RU`, `en_US`) |
| `results` | number | Нет | Количество результатов (по умолчанию 7, максимум 10) |
| `ll` | string | Нет | Координаты для приоритизации результатов: `долгота,широта` |
| `spn` | string | Нет | Размер области видимости в градусах: `ширина,высота` |
| `types` | string | Нет | Типы объектов: `geo` (адреса), `biz` (организации) |
| `attrs` | string | Нет | Дополнительные атрибуты, например `uri` |

### Пример запроса

```javascript
const API_KEY = 'ваш_api_ключ';
const searchText = 'Абая 150';
const userLat = 43.238; // координаты пользователя
const userLon = 76.945;

const url = `https://suggest-maps.yandex.ru/v1/suggest?` +
  `apikey=${API_KEY}` +
  `&text=${encodeURIComponent(searchText)}` +
  `&lang=ru_KZ` +
  `&results=10` +
  `&ll=${userLon},${userLat}` +
  `&spn=40.0,20.0` +
  `&types=geo,biz` +
  `&attrs=uri`;

const response = await fetch(url);
const data = await response.json();
```

### Формат ответа

```json
{
  "results": [
    {
      "title": {
        "text": "проспект Абая, 150"
      },
      "subtitle": {
        "text": "Алматы, Казахстан"
      },
      "uri": "ymapsbm1://geo?ll=76.945%2C43.238&spn=0.001%2C0.001&text=...",
      "tags": ["street"],
      "distance": {
        "value": 1234,
        "text": "1.2 км"
      }
    }
  ]
}
```

---

## 3. API для геокодирования (Geocoder)

### Endpoint
```
GET https://geocode-maps.yandex.ru/v1
```

### Параметры запроса

| Параметр | Тип | Обязательный | Описание |
|----------|-----|--------------|----------|
| `apikey` | string | Да | Ваш API ключ |
| `geocode` | string | Да* | Адрес для геокодирования ИЛИ координаты `долгота,широта` |
| `uri` | string | Да* | URI объекта (из результатов Suggest) |
| `format` | string | Нет | Формат ответа (по умолчанию `json`) |
| `lang` | string | Нет | Язык ответа |

*Используйте либо `geocode`, либо `uri`

### Пример запроса с URI (рекомендуется)

```javascript
const API_KEY = 'ваш_geocoder_api_ключ';
const uri = 'ymapsbm1://geo?ll=76.945%2C43.238...'; // из результатов Suggest

const url = `https://geocode-maps.yandex.ru/v1?` +
  `apikey=${API_KEY}` +
  `&uri=${encodeURIComponent(uri)}` +
  `&format=json` +
  `&lang=ru_KZ`;

const response = await fetch(url);
const data = await response.json();
```

### Пример запроса с текстом адреса

```javascript
const API_KEY = 'ваш_geocoder_api_ключ';
const address = 'проспект Абая, 150, Алматы, Казахстан';

const url = `https://geocode-maps.yandex.ru/v1?` +
  `apikey=${API_KEY}` +
  `&geocode=${encodeURIComponent(address)}` +
  `&format=json` +
  `&lang=ru_KZ`;

const response = await fetch(url);
const data = await response.json();
```

### Формат ответа

```json
{
  "response": {
    "GeoObjectCollection": {
      "featureMember": [
        {
          "GeoObject": {
            "Point": {
              "pos": "76.945645 43.237163"
            },
            "metaDataProperty": {
              "GeocoderMetaData": {
                "text": "Казахстан, Алматы, проспект Абая, 150",
                "Address": {
                  "formatted": "Алматы, проспект Абая, 150"
                }
              }
            }
          }
        }
      ]
    }
  }
}
```

---

## 4. Логика реализации

### 4.1 Получение геолокации пользователя

```javascript
function getUserLocation(callback) {
  if ('geolocation' in navigator) {
    navigator.geolocation.getCurrentPosition(
      (position) => {
        callback({
          lat: position.coords.latitude,
          lon: position.coords.longitude
        });
      },
      (error) => {
        console.log('Geolocation unavailable:', error.message);
        // Используем координаты по умолчанию (например, Алматы)
        callback({ lat: 43.222, lon: 76.8512 });
      }
    );
  } else {
    callback({ lat: 43.222, lon: 76.8512 });
  }
}
```

### 4.2 Debounce (задержка перед запросом)

Рекомендуется добавить задержку 300мс перед отправкой запроса к API:

```javascript
function debounce(func, delay) {
  let timeoutId;
  return function(...args) {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => func.apply(this, args), delay);
  };
}

// Использование
const debouncedSearch = debounce(fetchSuggestions, 300);
```

### 4.3 Функция поиска подсказок

```javascript
async function fetchSuggestions(searchText, userCoords) {
  // Минимум 3 символа для поиска
  if (!searchText || searchText.length < 3) {
    return [];
  }

  const lat = userCoords?.lat ?? 43.222;
  const lon = userCoords?.lon ?? 76.8512;

  try {
    const url = `https://suggest-maps.yandex.ru/v1/suggest?` +
      `apikey=${SUGGEST_API_KEY}` +
      `&text=${encodeURIComponent(searchText)}` +
      `&lang=ru_KZ` +
      `&results=10` +
      `&ll=${lon},${lat}` +
      `&spn=40.0,20.0` +
      `&types=geo,biz` +
      `&attrs=uri`;

    const response = await fetch(url);
    const data = await response.json();

    return data.results || [];
  } catch (error) {
    console.error('Ошибка запроса к Yandex Suggest API:', error);
    return [];
  }
}
```

### 4.4 Функция геокодирования

```javascript
async function geocodeAddress(addressText, uri = null) {
  try {
    const params = new URLSearchParams({
      apikey: GEOCODER_API_KEY,
      format: 'json',
      lang: 'ru_KZ'
    });

    // Используем URI если он есть (более точные результаты)
    if (uri) {
      params.append('uri', uri);
    } else {
      params.append('geocode', addressText);
    }

    const url = `https://geocode-maps.yandex.ru/v1?${params}`;
    const response = await fetch(url);
    const data = await response.json();

    const geoObject = data.response?.GeoObjectCollection?.featureMember?.[0]?.GeoObject;

    if (geoObject && geoObject.Point) {
      const [lon, lat] = geoObject.Point.pos.split(' ');

      return {
        lat: parseFloat(lat),
        lon: parseFloat(lon),
        fullAddress: geoObject.metaDataProperty?.GeocoderMetaData?.text,
        formattedAddress: geoObject.metaDataProperty?.GeocoderMetaData?.Address?.formatted
      };
    }

    throw new Error('Адрес не найден');
  } catch (error) {
    console.error('Ошибка геокодирования:', error);
    throw error;
  }
}
```

### 4.5 Обработка выбора подсказки

```javascript
async function selectSuggestion(item) {
  // Формируем текст для геокодирования
  let geocodeText = item.title?.text || '';

  // Если есть subtitle, добавляем его
  if (item.subtitle?.text) {
    const subtitleCleaned = item.subtitle.text.replace(/\d+[,.]?\d*\s*км$/i, '').trim();

    if (subtitleCleaned && subtitleCleaned !== geocodeText) {
      geocodeText = `${geocodeText}, ${subtitleCleaned}`;
    }
  }

  // Добавляем "Казахстан" если URI не предоставлен
  if (!item.uri && !geocodeText.toLowerCase().includes('казахстан')) {
    geocodeText = `${geocodeText}, Казахстан`;
  }

  try {
    // Используем URI если доступен (приоритет)
    const result = await geocodeAddress(geocodeText, item.uri);

    console.log('Выбранный адрес:', result);
    // result содержит: { lat, lon, fullAddress, formattedAddress }

    return result;
  } catch (error) {
    console.error('Не удалось получить координаты:', error);
    throw error;
  }
}
```

### 4.6 Подсветка совпадений в результатах

```javascript
function highlightMatch(text, query) {
  const pattern = new RegExp(`(${query})`, 'gi');
  return text.replace(pattern, '<strong>$1</strong>');
}

// Использование в HTML
// <div innerHTML={highlightMatch(item.title.text, searchQuery)} />
```

---

## 5. Псевдокод полной интеграции

```javascript
// 1. При монтировании компонента
onMount(() => {
  getUserLocation((coords) => {
    userCoordinates = coords;
  });
});

// 2. При вводе текста в инпут
function onInputChange(event) {
  const searchText = event.target.value;

  if (searchText.length < 3) {
    suggestions = [];
    showDropdown = false;
    return;
  }

  // Вызываем debounced функцию поиска
  debouncedFetchSuggestions(searchText, userCoordinates);
}

// 3. Debounced функция поиска
const debouncedFetchSuggestions = debounce(async (text, coords) => {
  loading = true;
  suggestions = await fetchSuggestions(text, coords);
  showDropdown = true;
  loading = false;
}, 300);

// 4. При клике на подсказку
async function onSuggestionClick(item) {
  showDropdown = false;
  loading = true;

  try {
    const result = await selectSuggestion(item);

    // Обновляем значение инпута
    inputValue = result.formattedAddress;

    // Сохраняем координаты для дальнейшей работы
    selectedCoordinates = { lat: result.lat, lon: result.lon };

    console.log('Координаты:', selectedCoordinates);
  } catch (error) {
    console.error('Ошибка:', error);
  } finally {
    loading = false;
  }
}
```

---

## 6. UI/UX рекомендации

### Dropdown стили (пример CSS)

```css
.dropdown {
  position: absolute;
  left: 0;
  top: calc(100% + 5px);
  width: 100%;
  max-height: 200px;
  margin: 0;
  padding: 0;
  border: 1px solid #d7d6d6;
  border-radius: 4px;
  list-style: none;
  background-color: #ffffff;
  overflow: auto;
  z-index: 999;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}

.dropdown-item {
  padding: 8px 12px;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.dropdown-item:hover {
  background-color: rgba(45, 156, 219, 0.1);
}

.dropdown-item strong {
  color: #2d9cdb;
}

.dropdown-item--subtitle {
  font-size: 12px;
  color: #666;
}

.dropdown-item--distance {
  font-size: 12px;
  color: #999;
}
```

### Рекомендации:
- Минимум **3 символа** для начала поиска
- Задержка **300мс** (debounce) перед запросом
- Показывать **до 10 результатов**
- **Подсвечивать** совпадения в результатах
- Показывать **индикатор загрузки** во время запроса
- Закрывать dropdown при клике вне элемента

---

## 7. Пример HTML разметки

```html
<div class="address-input-container">
  <!-- Инпут для ввода адреса -->
  <input
    type="text"
    placeholder="Введите адрес..."
    value={inputValue}
    onInput={onInputChange}
  />

  <!-- Dropdown с результатами -->
  {#if showDropdown}
    <ul class="dropdown">
      {#if loading}
        <li class="dropdown-item">Загрузка...</li>
      {:else}
        {#each suggestions as item}
          <li class="dropdown-item" onClick={() => onSuggestionClick(item)}>
            <div class="dropdown-item--main">
              <span innerHTML={highlightMatch(item.title.text, inputValue)}></span>
              {#if item.distance?.text}
                <span class="dropdown-item--distance">{item.distance.text}</span>
              {/if}
            </div>
            {#if item.subtitle?.text}
              <div class="dropdown-item--subtitle"
                   innerHTML={highlightMatch(item.subtitle.text, inputValue)}>
              </div>
            {/if}
          </li>
        {/each}
      {/if}
    </ul>
  {/if}
</div>
```

---

## 8. Частые вопросы (FAQ)

### Q: Сколько стоит использование API?
A: Яндекс предоставляет бесплатный лимит запросов. Подробности на https://yandex.ru/dev/maps/

### Q: Нужно ли использовать оба API ключа?
A: Да, Suggest и Geocoder используют разные ключи.

### Q: Можно ли использовать для других стран кроме Казахстана?
A: Да, измените параметр `lang` и координаты по умолчанию.

### Q: Почему нужно добавлять ", Казахстан" к адресу?
A: Это повышает точность геокодирования для адресов в Казахстане.

### Q: Что такое URI в результатах Suggest?
A: URI - это уникальный идентификатор объекта в Яндекс.Картах, который дает более точные координаты при геокодировании.

---

## 9. Дополнительная информация

- Официальная документация Suggest API: https://yandex.ru/maps-api/docs/suggest-api/
- Официальная документация Geocoder API: https://yandex.ru/dev/maps/geocoder/

---

## 10. Контакты для поддержки

Если у вас есть вопросы по этой интеграции, свяжитесь с нами:
- Email: support@coube.kz
- Документация проекта: https://github.com/your-repo

---

**Версия документа:** 1.0
**Дата обновления:** 2025-01-27
