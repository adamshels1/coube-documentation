# Frontend Task 2: Компонент отображения QR кода для подписания

## 📋 Описание

Создать компонент модального окна для отображения QR кода, который пользователь сканирует в приложении eGov Mobile для подписания документа.

## 📍 Расположение

**Файл:** `coube-frontend/src/components/QRSignModal/QRSignModal.vue`

## 🎯 Функциональность

Модальное окно:
1. Показывает QR код с URL для eGov Mobile
2. Отображает инструкцию по подписанию
3. Показывает статус подписания (ожидание / подписано / ошибка)
4. Выполняет polling для проверки статуса сессии
5. Автоматически закрывается после успешного подписания
6. Показывает таймер обратного отсчета (30 минут)

## ✅ Чеклист реализации

### 1. Установка зависимостей

- [ ] Установить библиотеку для генерации QR кодов:
  ```bash
  npm install qrcode.vue
  # или
  npm install vue-qrcode
  ```

### 2. Создание компонента

- [ ] Создать `QRSignModal.vue`:
  ```vue
  <template>
    <div class="qr-sign-modal" @click.self="handleClose">
      <div class="qr-modal-card">
        <!-- Заголовок -->
        <div class="qr-modal-header">
          <h2>{{ t('qrSign.modal.title') }}</h2>
          <button class="close-btn" @click="handleClose">×</button>
        </div>

        <!-- Контент -->
        <div class="qr-modal-body">
          <!-- Инструкция -->
          <div class="instruction">
            <div class="step">
              <span class="step-number">1</span>
              <span class="step-text">{{ t('qrSign.modal.step1') }}</span>
            </div>
            <div class="step">
              <span class="step-number">2</span>
              <span class="step-text">{{ t('qrSign.modal.step2') }}</span>
            </div>
            <div class="step">
              <span class="step-number">3</span>
              <span class="step-text">{{ t('qrSign.modal.step3') }}</span>
            </div>
          </div>

          <!-- QR Код -->
          <div class="qr-code-container" v-if="status === 'pending'">
            <qrcode-vue
              :value="qrCodeContent"
              :size="300"
              level="H"
              render-as="svg"
            />
            <div class="qr-timer">
              <base-icon :icon="ClockIcon" />
              <span>{{ formattedTimeLeft }}</span>
            </div>
          </div>

          <!-- Статус: Ожидание -->
          <div class="status-waiting" v-if="status === 'pending'">
            <dots-loader />
            <p>{{ t('qrSign.modal.waiting') }}</p>
          </div>

          <!-- Статус: Успешно -->
          <div class="status-success" v-if="status === 'signed'">
            <base-icon :icon="CheckCircleIcon" color="success" :size="64" />
            <p>{{ t('qrSign.modal.success') }}</p>
          </div>

          <!-- Статус: Ошибка -->
          <div class="status-error" v-if="status === 'error'">
            <base-icon :icon="ErrorCircleIcon" color="danger" :size="64" />
            <p>{{ errorMessage || t('qrSign.modal.error') }}</p>
            <base-button @click="handleRetry">
              {{ t('qrSign.modal.retry') }}
            </base-button>
          </div>

          <!-- Статус: Истекло -->
          <div class="status-expired" v-if="status === 'expired'">
            <base-icon :icon="ClockExpiredIcon" color="warning" :size="64" />
            <p>{{ t('qrSign.modal.expired') }}</p>
            <base-button @click="handleRetry">
              {{ t('qrSign.modal.createNew') }}
            </base-button>
          </div>
        </div>

        <!-- Футер -->
        <div class="qr-modal-footer">
          <base-button color="gray" outlined @click="handleClose">
            {{ t('actions.cancel') }}
          </base-button>
        </div>
      </div>
    </div>
  </template>

  <script setup lang="ts">
  import { ref, onMounted, onUnmounted, computed } from 'vue';
  import QrcodeVue from 'qrcode.vue';
  import { useI18n } from 'vue-i18n';
  import api from '@/api';
  import { BaseButton } from '@/components/BaseButton';
  import { BaseIcon } from '@/components/BaseIcon';
  import { DotsLoader } from '@/components/DotsLoader';
  import CheckCircleIcon from '@/icons/check-circle.svg';
  import ErrorCircleIcon from '@/icons/error-circle.svg';
  import ClockIcon from '@/icons/clock.svg';
  import ClockExpiredIcon from '@/icons/clock-expired.svg';

  const { t } = useI18n();

  // Props
  const props = defineProps<{
    sessionId: string;
    qrCodeContent: string;
    expiresAt: string; // ISO 8601
  }>();

  // Emits
  const emit = defineEmits<{
    (e: 'close'): void;
    (e: 'success'): void;
    (e: 'retry'): void;
  }>();

  // State
  const status = ref<'pending' | 'signed' | 'error' | 'expired'>('pending');
  const errorMessage = ref<string>('');
  const timeLeft = ref<number>(0);

  // Polling
  let pollingInterval: number | null = null;
  let timerInterval: number | null = null;

  // Computed
  const formattedTimeLeft = computed(() => {
    const minutes = Math.floor(timeLeft.value / 60);
    const seconds = timeLeft.value % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  });

  // Methods
  const checkStatus = async () => {
    try {
      const { data } = await api.egovSign.getSessionStatus(props.sessionId);

      if (data.status === 'SIGNED') {
        status.value = 'signed';
        stopPolling();
        setTimeout(() => {
          emit('success');
          emit('close');
        }, 2000);
      } else if (data.status === 'ERROR') {
        status.value = 'error';
        errorMessage.value = data.errorMessage || '';
        stopPolling();
      } else if (data.status === 'EXPIRED') {
        status.value = 'expired';
        stopPolling();
      }
    } catch (error) {
      console.error('Error checking session status:', error);
    }
  };

  const startPolling = () => {
    // Проверять статус каждые 3 секунды
    pollingInterval = window.setInterval(checkStatus, 3000);
  };

  const stopPolling = () => {
    if (pollingInterval) {
      clearInterval(pollingInterval);
      pollingInterval = null;
    }
    if (timerInterval) {
      clearInterval(timerInterval);
      timerInterval = null;
    }
  };

  const updateTimer = () => {
    const now = new Date().getTime();
    const expiresTime = new Date(props.expiresAt).getTime();
    const diff = Math.floor((expiresTime - now) / 1000);

    if (diff <= 0) {
      status.value = 'expired';
      stopPolling();
      timeLeft.value = 0;
    } else {
      timeLeft.value = diff;
    }
  };

  const startTimer = () => {
    updateTimer();
    timerInterval = window.setInterval(updateTimer, 1000);
  };

  const handleClose = () => {
    stopPolling();
    emit('close');
  };

  const handleRetry = () => {
    stopPolling();
    emit('retry');
  };

  // Lifecycle
  onMounted(() => {
    startPolling();
    startTimer();
  });

  onUnmounted(() => {
    stopPolling();
  });
  </script>
  ```

### 3. Стилизация

- [ ] Создать стили для модального окна:
  ```scss
  <style lang="scss" scoped>
  .qr-sign-modal {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
  }

  .qr-modal-card {
    background: #ffffff;
    border-radius: 16px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.25);
    max-width: 600px;
    width: 100%;
    max-height: 90vh;
    overflow-y: auto;
  }

  .qr-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 24px;
    border-bottom: 1px solid #e5e7eb;

    h2 {
      font-size: 20px;
      font-weight: 600;
      margin: 0;
    }

    .close-btn {
      width: 32px;
      height: 32px;
      border: none;
      background: transparent;
      font-size: 28px;
      cursor: pointer;
      color: #6b7280;

      &:hover {
        color: #111827;
      }
    }
  }

  .qr-modal-body {
    padding: 32px 24px;
  }

  .instruction {
    margin-bottom: 32px;

    .step {
      display: flex;
      align-items: flex-start;
      gap: 12px;
      margin-bottom: 16px;

      .step-number {
        width: 28px;
        height: 28px;
        border-radius: 50%;
        background: var(--primary-color);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 600;
        font-size: 14px;
        flex-shrink: 0;
      }

      .step-text {
        font-size: 15px;
        line-height: 28px;
      }
    }
  }

  .qr-code-container {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 24px;
    background: #f9fafb;
    border-radius: 12px;
    margin-bottom: 24px;

    .qr-timer {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      background: white;
      border-radius: 20px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
      font-size: 16px;
      font-weight: 600;
    }
  }

  .status-waiting {
    text-align: center;

    p {
      margin-top: 16px;
      font-size: 16px;
      color: #6b7280;
    }
  }

  .status-success,
  .status-error,
  .status-expired {
    text-align: center;
    padding: 32px;

    p {
      margin: 16px 0 24px;
      font-size: 18px;
      font-weight: 500;
    }
  }

  .qr-modal-footer {
    padding: 16px 24px;
    border-top: 1px solid #e5e7eb;
    display: flex;
    justify-content: flex-end;
  }
  </style>
  ```

### 4. Добавить переводы

- [ ] В `coube-frontend/src/locales/ru.json`:
  ```json
  {
    "qrSign": {
      "modal": {
        "title": "Подписание через QR код",
        "step1": "Откройте приложение eGov Mobile на вашем телефоне",
        "step2": "Отсканируйте QR код ниже",
        "step3": "Подпишите документ в приложении eGov Mobile",
        "waiting": "Ожидание подписания...",
        "success": "Документ успешно подписан!",
        "error": "Ошибка при подписании документа",
        "expired": "Время сессии истекло",
        "retry": "Повторить попытку",
        "createNew": "Создать новый QR код"
      }
    }
  }
  ```

- [ ] Добавить переводы в `kk.json`, `en.json`, `zh.json`

### 5. Создать API сервис

- [ ] Создать/обновить `coube-frontend/src/api/egovSign.ts`:
  ```typescript
  import { request } from '@/api/utils';

  export const egovSign = {
    initSession: (documentId: string, documentType: string) =>
      request('post', 'v1/egov-sign/init', {
        body: { documentId, documentType }
      }),

    getSessionStatus: (sessionId: string) =>
      request('get', `v1/egov-sign/session/${sessionId}/status`, {}),
  };

  export default egovSign;
  ```

- [ ] Добавить в `coube-frontend/src/api/index.ts`:
  ```typescript
  import egovSign from './egovSign';

  export default {
    // ... другие API
    egovSign,
  };
  ```

### 6. Типы TypeScript

- [ ] Создать `coube-frontend/src/types/interfaces/egovSign.ts`:
  ```typescript
  export interface EgovSignSession {
    sessionId: string;
    apiUrl: string;
    qrCode: string;
    expiresAt: string;
  }

  export interface EgovSessionStatus {
    sessionId: string;
    status: 'PENDING' | 'SIGNED' | 'EXPIRED' | 'ERROR';
    documentId: string;
    documentType: string;
    createdAt: string;
    expiresAt: string;
    signedAt?: string;
    errorMessage?: string;
  }
  ```

### 7. Обработка событий

- [ ] Добавить обработчики для событий:
  - `@close` - закрытие модалки
  - `@success` - успешное подписание
  - `@retry` - повторная попытка (создание новой сессии)

### 8. Оптимизация

- [ ] Остановить polling при закрытии модалки
- [ ] Очистить интервалы в `onUnmounted`
- [ ] Добавить debounce для повторных попыток
- [ ] Кэшировать QR код (опционально)

### 9. Тестирование

- [ ] Проверить генерацию QR кода
- [ ] Проверить polling статуса
- [ ] Проверить таймер обратного отсчета
- [ ] Проверить автозакрытие после успешного подписания
- [ ] Проверить обработку ошибок
- [ ] Проверить обработку истечения сессии
- [ ] Проверить responsive дизайн
- [ ] Проверить accessibility

### 10. Документация

- [ ] Добавить JSDoc комментарии к компоненту
- [ ] Описать props и emits
- [ ] Добавить примеры использования

## 📚 Требования

### QR Код
- ✅ Размер: 300x300px
- ✅ Error correction level: H (высокий)
- ✅ Формат: SVG (масштабируемый)
- ✅ Содержимое: `mobileSign:https://api.coube.kz/api/v1/egov-sign/session/{sessionId}`

### Polling
- ✅ Интервал: 3 секунды
- ✅ Остановка при: SIGNED, ERROR, EXPIRED
- ✅ Очистка при закрытии модалки

### Таймер
- ✅ Обратный отсчет от 30 минут
- ✅ Обновление каждую секунду
- ✅ Формат: MM:SS

### UX
- ✅ Инструкции пошагово
- ✅ Визуальная индикация статуса
- ✅ Автозакрытие через 2 секунды после успеха
- ✅ Возможность повторить попытку

## 🔗 Зависимости

**Библиотеки:**
- `qrcode.vue` или `vue-qrcode`

**Зависит от:**
- Task 1: Select Sign Method (выбор метода)
- Backend Task 1: EgovSignController (API для создания сессии и проверки статуса)

**Необходимо для:**
- Task 4: Contract Integration (показ модалки при подписании)

## ⚠️ Важные замечания

1. **Memory leaks**: Обязательно очищать интервалы в `onUnmounted`
2. **Error handling**: Обрабатывать ошибки сети при polling
3. **Accessibility**: Добавить aria-labels для статусов
4. **Mobile**: Проверить на мобильных устройствах

## 📊 Критерии приемки

- [ ] QR код отображается корректно и сканируется в eGov Mobile
- [ ] Polling работает и обновляет статус
- [ ] Таймер показывает оставшееся время
- [ ] Автозакрытие после успешного подписания
- [ ] Обработка всех статусов (pending, signed, error, expired)
- [ ] Переводы на всех языках
- [ ] Responsive дизайн
- [ ] Нет memory leaks
- [ ] Код покрыт комментариями

---

**Приоритет:** 🔴 Высокий
**Оценка:** 4-5 часов
**Assignee:** Frontend Developer
**Зависит от:** Frontend Task 1, Backend Task 1
