# Frontend Task 3: Интеграция QR подписания в контракты

## 📋 Описание

Интегрировать QR подписание в существующий компонент подписания контрактов `ContractResponsesItem.vue`, добавив поддержку выбора метода подписания (NCLayer или QR код).

## 📍 Расположение

**Файл:** `coube-frontend/src/components/ContractDetails/ContractResponsesItem.vue`

## 🎯 Функциональность

При нажатии кнопки "Подписать контракт":
1. Открывается модалка выбора метода подписания
2. Пользователь выбирает: "Через файл ключа" или "Через QR код"
3. В зависимости от выбора:
   - **NCLayer**: Используется существующая логика
   - **QR код**: Создается сессия подписания и показывается QR код

## ✅ Чеклист реализации

### 1. Изучить существующую реализацию

- [ ] Открыть `ContractResponsesItem.vue`
- [ ] Найти методы `sendContract()` и `signContract()`
- [ ] Понять текущий flow подписания через NCLayer

### 2. Добавить состояние для метода подписания

- [ ] Добавить ref для хранения выбранного метода:
  ```typescript
  const selectedSignMethod = ref<'nclayer' | 'qr' | null>(null);
  const showMethodSelector = ref(false);
  const showQRModal = ref(false);
  const qrSessionData = ref<{
    sessionId: string;
    qrCode: string;
    expiresAt: string;
  } | null>(null);
  ```

### 3. Обновить метод sendContract для выбора способа

- [ ] Изменить логику кнопки "Подписать":
  ```typescript
  const initiateContractSigning = () => {
    // Показать модалку выбора метода
    showMethodSelector.value = true;
  };

  const handleMethodSelected = (method: 'nclayer' | 'qr') => {
    selectedSignMethod.value = method;
    showMethodSelector.value = false;

    if (method === 'nclayer') {
      sendContractViaNCLayer();
    } else if (method === 'qr') {
      sendContractViaQR();
    }
  };
  ```

### 4. Создать метод для QR подписания

- [ ] Реализовать `sendContractViaQR`:
  ```typescript
  const sendContractViaQR = async () => {
    try {
      isLoadButton.value = true;

      // Создать сессию подписания
      const { data } = await api.egovSign.initSession(
        props.responseItem.id.toString(),
        'agreement'
      );

      // Сохранить данные сессии
      qrSessionData.value = {
        sessionId: data.sessionId,
        qrCode: data.qrCode,
        expiresAt: data.expiresAt
      };

      // Показать QR модалку
      showQRModal.value = true;

    } catch (error) {
      console.error('Error initiating QR signing:', error);
      toast.error(t('contract.errors.qrInitFailed'));
    } finally {
      isLoadButton.value = false;
    }
  };
  ```

### 5. Обработать успешное QR подписание

- [ ] Добавить обработчик `handleQRSuccess`:
  ```typescript
  const handleQRSuccess = () => {
    // Закрыть QR модалку
    showQRModal.value = false;
    qrSessionData.value = null;

    // Показать уведомление
    toast.success(t('contract.toasts.qrSignSuccess'));

    // Обновить данные контракта
    emit('refresh');
  };
  ```

### 6. Обработать повторную попытку QR подписания

- [ ] Добавить обработчик `handleQRRetry`:
  ```typescript
  const handleQRRetry = async () => {
    // Закрыть текущую QR модалку
    showQRModal.value = false;
    qrSessionData.value = null;

    // Создать новую сессию
    await sendContractViaQR();
  };
  ```

### 7. Рефакторинг существующего NCLayer метода

- [ ] Переименовать `sendContract` в `sendContractViaNCLayer`:
  ```typescript
  const sendContractViaNCLayer = async () => {
    // Существующий код подписания через NCLayer
    try {
      isLoadButton.value = true;

      // Шаг 1: Получить PDF договора
      const { data: contractData } = await api.request<{ file: string }>(
        'get',
        `v1/customer/agreements/responses/${props.responseItem.id}/contract`,
        {}
      );

      // ... остальной код NCLayer
    } catch (error) {
      // ...
    }
  };
  ```

### 8. Обновить шаблон

- [ ] Обновить кнопку "Подписать":
  ```vue
  <!-- Для статуса EXECUTOR_ACCEPTED -->
  <base-button
    color="success"
    size="small"
    :loading="isLoadButton"
    :disabled="isLoadButton"
    @click.stop="initiateContractSigning"
  >
    {{ t('transportationResponseItem.confirmAndSendContract') }}
  </base-button>
  ```

- [ ] Добавить модалку выбора метода:
  ```vue
  <!-- Модалка выбора метода подписания -->
  <base-modal v-if="showMethodSelector" @close="showMethodSelector = false">
    <select-sign-method
      @method-selected="handleMethodSelected"
      @close="showMethodSelector = false"
    />
  </base-modal>
  ```

- [ ] Добавить QR модалку:
  ```vue
  <!-- QR модалка -->
  <qr-sign-modal
    v-if="showQRModal && qrSessionData"
    :session-id="qrSessionData.sessionId"
    :qr-code-content="qrSessionData.qrCode"
    :expires-at="qrSessionData.expiresAt"
    @close="showQRModal = false"
    @success="handleQRSuccess"
    @retry="handleQRRetry"
  />
  ```

### 9. Импорты

- [ ] Добавить импорты компонентов:
  ```typescript
  import SelectSignMethod from '@/components/ModalContent/SelectSignMethod/SelectSignMethodBody/SelectSignMethodBody.vue';
  import QRSignModal from '@/components/QRSignModal/QRSignModal.vue';
  import BaseModal from '@/components/BaseModal/BaseModal.vue';
  ```

### 10. Переводы

- [ ] Добавить новые ключи в `ru.json`:
  ```json
  {
    "contract": {
      "errors": {
        "qrInitFailed": "Не удалось создать QR код для подписания"
      },
      "toasts": {
        "qrSignSuccess": "Документ успешно подписан через eGov Mobile"
      }
    }
  }
  ```

- [ ] Добавить переводы в `kk.json`, `en.json`, `zh.json`

### 11. Обработка ошибок

- [ ] Обработать ошибки создания сессии:
  ```typescript
  try {
    // ...
  } catch (error) {
    let errorMessage = t('contract.errors.qrInitFailed');

    if (error instanceof Error) {
      errorMessage = error.message;
    } else if (typeof error === 'object' && error && 'message' in error) {
      errorMessage = (error as { message: string }).message;
    }

    toast.error(errorMessage);
    isLoadButton.value = false;
  }
  ```

### 12. Обновить для других типов документов

- [ ] Применить аналогичные изменения для подписания:
  - Счетов-фактур (InvoiceSign.vue)
  - Актов (ActSign.vue)
  - Реестров (RegistrySign.vue)

- [ ] Обобщить логику в composable (опционально):
  ```typescript
  // coube-frontend/src/composables/useDocumentSigning.ts
  export function useDocumentSigning(documentId: string, documentType: string) {
    const selectedMethod = ref<'nclayer' | 'qr' | null>(null);
    // ...

    return {
      initiateS igning,
      signViaNCLayer,
      signViaQR,
      // ...
    };
  }
  ```

### 13. Тестирование

- [ ] Протестировать выбор метода NCLayer (работает как раньше)
- [ ] Протестировать выбор метода QR код
- [ ] Протестировать создание QR сессии
- [ ] Протестировать отображение QR модалки
- [ ] Протестировать успешное подписание через QR
- [ ] Протестировать повторную попытку
- [ ] Протестировать обработку ошибок
- [ ] Протестировать отмену подписания

### 14. Edge cases

- [ ] Что если пользователь закрыл QR модалку?
  - Сессия остается активной, можно показать снова
- [ ] Что если истекло время сессии?
  - Показать кнопку "Создать новый QR код"
- [ ] Что если пользователь переключился на другой документ?
  - Закрыть все модалки, очистить состояние
- [ ] Что если подписание уже в процессе?
  - Заблокировать кнопку, показать индикатор загрузки

## 📚 Требования

### UX Flow
1. Клик "Подписать" → Модалка выбора метода
2. Выбор "QR код" → Создание сессии → Показ QR модалки
3. Подписание в eGov Mobile → Polling → Автозакрытие → Обновление UI

### Обратная совместимость
- ✅ NCLayer метод должен работать как раньше
- ✅ Существующие тесты не должны сломаться

### Performance
- ✅ Не создавать сессию до выбора метода
- ✅ Переиспользовать сессию при повторном открытии модалки
- ✅ Очищать данные сессии после закрытия

## 🔗 Зависимости

**Зависит от:**
- Frontend Task 1: Select Sign Method
- Frontend Task 2: QR Sign Modal
- Backend Task 1: EgovSignController

**Необходимо для:**
- Полноценная работа QR подписания в продакшене

## ⚠️ Важные замечания

1. **Не ломать NCLayer**: Существующий метод должен работать
2. **Типизация**: Использовать TypeScript интерфейсы
3. **Cleanup**: Очищать данные сессии при размонтировании компонента
4. **Loading states**: Показывать индикатор загрузки во время создания сессии

## 📊 Критерии приемки

- [ ] Кнопка "Подписать" открывает модалку выбора метода
- [ ] Выбор "Через файл ключа" работает как раньше (NCLayer)
- [ ] Выбор "Через QR код" создает сессию и показывает QR модалку
- [ ] QR модалка отображается с корректными данными
- [ ] Успешное подписание через QR обновляет UI
- [ ] Повторная попытка создает новую сессию
- [ ] Обработка ошибок работает корректно
- [ ] Переводы на всех языках
- [ ] Код покрыт комментариями
- [ ] Существующие тесты проходят

---

**Приоритет:** 🔴 Высокий
**Оценка:** 3-4 часа
**Assignee:** Frontend Developer
**Зависит от:** Frontend Task 1, 2; Backend Task 1
