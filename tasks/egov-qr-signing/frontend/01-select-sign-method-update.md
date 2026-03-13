# Frontend Task 1: Обновление компонента выбора метода подписания

## 📋 Описание

Обновить существующий компонент `SelectSignMethodBody` для добавления второй опции подписания - "Через QR код" (помимо существующей "Через файл ключа").

## 📍 Расположение

**Файл:** `coube-frontend/src/components/ModalContent/SelectSignMethod/SelectSignMethodBody/SelectSignMethodBody.vue`

## 🎯 Функциональность

Пользователь может выбрать один из двух методов подписания:
1. **Через файл ключа** (существующий) - использует NCLayer
2. **Через QR код** (новый) - использует eGov Mobile

При переключении метода, состояние сохраняется в store и передается родительскому компоненту.

## ✅ Чеклист реализации

### 1. Изучить текущую реализацию

- [ ] Открыть `SelectSignMethodBody.vue`
- [ ] Понять текущую логику с `isSignedEds` toggle
- [ ] Изучить использование `modalStore.setModalState()`

### 2. Обновить тип переключателя

**Текущая версия:**
```vue
<base-toggle v-model:checked="isSignedEds" :label="toggleLabel" />
```

**Новая версия** - заменить на radio buttons или select:

- [ ] Добавить новый ref для выбранного метода:
  ```typescript
  const signMethod = ref<'nclayer' | 'qr'>('nclayer');
  ```

- [ ] Создать radio group компонент:
  ```vue
  <div class="sign-method-selector">
    <div class="method-option">
      <input
        type="radio"
        id="method-nclayer"
        value="nclayer"
        v-model="signMethod"
      />
      <label for="method-nclayer">
        <div class="method-icon">
          <base-icon :icon="KeyIcon" />
        </div>
        <div class="method-info">
          <div class="method-title">{{ t('modal.selectSignMethod.nclayer.title') }}</div>
          <div class="method-description">{{ t('modal.selectSignMethod.nclayer.description') }}</div>
        </div>
      </label>
    </div>

    <div class="method-option">
      <input
        type="radio"
        id="method-qr"
        value="qr"
        v-model="signMethod"
      />
      <label for="method-qr">
        <div class="method-icon">
          <base-icon :icon="QrCodeIcon" />
        </div>
        <div class="method-info">
          <div class="method-title">{{ t('modal.selectSignMethod.qr.title') }}</div>
          <div class="method-description">{{ t('modal.selectSignMethod.qr.description') }}</div>
        </div>
      </label>
    </div>
  </div>
  ```

### 3. Обновить watch для синхронизации с store

- [ ] Заменить существующий watch:
  ```typescript
  watch(
    () => signMethod.value,
    (newValue) => {
      modalStore.setModalState(EModalName.SELECT_SIGN_METHOD, {
        signMethod: newValue,
      });
    }
  );
  ```

### 4. Добавить иконки

- [ ] Импортировать иконки:
  ```typescript
  import KeyIcon from '@/icons/key.svg'; // или использовать существующую
  import QrCodeIcon from '@/icons/qr-code.svg';
  ```

- [ ] Если иконок нет, создать SVG или использовать из библиотеки

### 5. Добавить переводы

- [ ] В `coube-frontend/src/locales/ru.json`:
  ```json
  {
    "modal": {
      "selectSignMethod": {
        "title": "Выберите способ подписания",
        "subtitle": "Выберите удобный для вас способ подписания документа",
        "nclayer": {
          "title": "Через файл ключа",
          "description": "Подписание с использованием ключа ЭЦП на компьютере (NCLayer)"
        },
        "qr": {
          "title": "Через QR код",
          "description": "Подписание через приложение eGov Mobile на телефоне"
        }
      }
    }
  }
  ```

- [ ] Добавить аналогичные переводы в `kk.json`, `en.json`, `zh.json`

### 6. Стилизация

- [ ] Обновить стили для radio group:
  ```scss
  .sign-method-selector {
    display: flex;
    flex-direction: column;
    gap: 16px;
    width: 100%;
  }

  .method-option {
    position: relative;

    input[type="radio"] {
      position: absolute;
      opacity: 0;
      cursor: pointer;

      &:checked + label {
        border-color: var(--primary-color);
        background-color: var(--primary-light);
      }
    }

    label {
      display: flex;
      align-items: center;
      gap: 16px;
      padding: 20px;
      border: 2px solid var(--gray-200);
      border-radius: 8px;
      cursor: pointer;
      transition: all 0.2s ease;

      &:hover {
        border-color: var(--primary-color);
        background-color: var(--gray-50);
      }
    }

    .method-icon {
      width: 48px;
      height: 48px;
      display: flex;
      align-items: center;
      justify-content: center;
      background-color: var(--gray-100);
      border-radius: 8px;
    }

    .method-info {
      flex: 1;
      text-align: left;

      .method-title {
        font-size: 16px;
        font-weight: 600;
        margin-bottom: 4px;
      }

      .method-description {
        font-size: 14px;
        color: var(--gray-600);
      }
    }
  }
  ```

### 7. Обновить логику обработки выбора

- [ ] Убедиться что выбранный метод передается в родительский компонент:
  ```typescript
  const emit = defineEmits<{
    (e: 'methodSelected', method: 'nclayer' | 'qr'): void;
  }>();

  watch(signMethod, (newMethod) => {
    emit('methodSelected', newMethod);
  });
  ```

### 8. Обратная совместимость

- [ ] Сохранить поддержку старого `isSignedEds` для совместимости:
  ```typescript
  // Для старых компонентов
  const isSignedEds = computed({
    get: () => signMethod.value === 'nclayer',
    set: (value) => {
      signMethod.value = value ? 'nclayer' : 'qr';
    }
  });
  ```

### 9. Тестирование

- [ ] Проверить отображение обоих методов
- [ ] Проверить переключение между методами
- [ ] Проверить сохранение выбора в store
- [ ] Проверить переводы на всех языках (ru, kk, en, zh)
- [ ] Проверить responsive дизайн (мобильная версия)
- [ ] Проверить accessibility (keyboard navigation)

### 10. Интеграция с модальным окном

- [ ] Убедиться что модальное окно корректно получает выбранный метод
- [ ] Проверить что при открытии модалки сохраняется последний выбор

## 📚 Требования

### UX/UI
- ✅ Визуально различимые опции
- ✅ Активное состояние четко видно
- ✅ Hover эффект для лучшей интерактивности
- ✅ Иконки для визуальной идентификации методов
- ✅ Описание для каждого метода

### Доступность
- ✅ Правильные aria-labels
- ✅ Keyboard navigation (Tab, Enter, Space)
- ✅ Focus states

### i18n
- ✅ Все тексты переведены на 4 языка (ru, kk, en, zh)

## 🔗 Зависимости

**Зависит от:**
- Существующий компонент `SelectSignMethodBody.vue`
- Modal store (`useModalStore`)

**Необходимо для:**
- Task 2: QR Sign Modal (показ QR кода)
- Task 4: Contract Integration (выбор метода подписания)

## ⚠️ Важные замечания

1. **Не ломать существующую функциональность** - метод "Через файл ключа" должен продолжать работать
2. **Default метод** - по умолчанию выбран "Через файл ключа" (для обратной совместимости)
3. **Сохранение выбора** - последний выбранный метод сохраняется в localStorage (опционально)

## 📊 Критерии приемки

- [ ] Отображаются два метода подписания: NCLayer и QR код
- [ ] Переключение между методами работает корректно
- [ ] Выбранный метод сохраняется в modal store
- [ ] Стилизация соответствует дизайну приложения
- [ ] Переводы на всех языках корректны
- [ ] Responsive дизайн работает на мобильных устройствах
- [ ] Keyboard navigation работает
- [ ] Существующая функциональность не сломана
- [ ] Код покрыт комментариями

---

**Приоритет:** 🟡 Средний
**Оценка:** 2-3 часа
**Assignee:** Frontend Developer
