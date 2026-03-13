# Mobile Task 2: eGov Sign Service

## 📋 Описание

Создать сервис для формирования deep links для открытия eGov Mobile и обработки процесса подписания документов.

## 📍 Расположение

**Файл:** `coube-mobile/src/services/egovSignService.ts`

## 🎯 Функциональность

1. Генерация Dynamic Links для eGov Mobile (Android и iOS)
2. URL encoding параметров
3. Открытие eGov Mobile приложения
4. Проверка наличия установленного приложения
5. Интеграция с backend API для создания сессий

## ✅ Чеклист реализации

### 1. Создать файл сервиса

- [ ] Создать `src/services/egovSignService.ts`

### 2. Импорты и типы

- [ ] Добавить необходимые импорты:
  ```typescript
  import {Platform, Linking, Alert} from 'react-native';
  import {api} from '@/api';

  // Типы
  interface EgovSignSessionResponse {
    sessionId: string;
    qrCode: string;
    expiresAt: string;
  }

  interface DynamicLinkParams {
    apiUrl: string;
    platform: 'android' | 'ios';
  }
  ```

### 3. Константы

- [ ] Определить константы для eGov Mobile:
  ```typescript
  const EGOV_MOBILE = {
    // Dynamic Link prefix
    DYNAMIC_LINK_BASE: 'https://mgovsign.page.link',

    // Android
    ANDROID_PACKAGE: 'kz.mobile.mgov',

    // iOS
    IOS_APP_STORE_ID: '1476128386',
    IOS_BUNDLE_ID: 'kz.egov.mobile',

    // App Store URLs
    ANDROID_STORE_URL:
      'https://play.google.com/store/apps/details?id=kz.mobile.mgov',
    IOS_STORE_URL: 'https://apps.apple.com/kz/app/egov-mobile/id1476128386',
  };
  ```

### 4. URL Encoding функция

- [ ] Реализовать функцию для правильного encoding:
  ```typescript
  /**
   * URL-encode параметров для eGov Mobile Dynamic Link
   * ВАЖНО: Кодировать & → %26, = → %3D, ? → %3F
   */
  const encodeEgovUrl = (url: string): string => {
    return encodeURIComponent(url)
      .replace(/\(/g, '%28')
      .replace(/\)/g, '%29')
      .replace(/!/g, '%21')
      .replace(/~/g, '%7E')
      .replace(/'/g, '%27')
      .replace(/\*/g, '%2A');
  };
  ```

### 5. Генерация Dynamic Link

- [ ] Создать функцию для генерации Dynamic Link:
  ```typescript
  /**
   * Генерирует Dynamic Link для eGov Mobile
   * @param apiUrl - URL API #1 от backend
   * @param platform - Платформа (android или ios)
   */
  const generateDynamicLink = ({
    apiUrl,
    platform,
  }: DynamicLinkParams): string => {
    const encodedApiUrl = encodeEgovUrl(apiUrl);

    if (platform === 'android') {
      return `${EGOV_MOBILE.DYNAMIC_LINK_BASE}/?link=${encodedApiUrl}&apn=${EGOV_MOBILE.ANDROID_PACKAGE}`;
    } else {
      return `${EGOV_MOBILE.DYNAMIC_LINK_BASE}/?link=${encodedApiUrl}&isi=${EGOV_MOBILE.IOS_APP_STORE_ID}&ibi=${EGOV_MOBILE.IOS_BUNDLE_ID}`;
    }
  };
  ```

### 6. Проверка установки eGov Mobile

- [ ] Реализовать проверку установленного приложения:
  ```typescript
  /**
   * Проверяет, установлено ли приложение eGov Mobile
   */
  const isEgovMobileInstalled = async (): Promise<boolean> => {
    try {
      // Для Android и iOS используем Dynamic Link
      // который автоматически откроет App Store если не установлено
      const testUrl = generateDynamicLink({
        apiUrl: 'test',
        platform: Platform.OS as 'android' | 'ios',
      });

      const canOpen = await Linking.canOpenURL(testUrl);
      return canOpen;
    } catch (error) {
      console.error('Error checking eGov Mobile installation:', error);
      return false;
    }
  };
  ```

### 7. Показ диалога установки

- [ ] Создать функцию для предложения установки:
  ```typescript
  /**
   * Показывает диалог с предложением установить eGov Mobile
   */
  const showInstallDialog = (): Promise<boolean> => {
    return new Promise(resolve => {
      Alert.alert(
        'eGov Mobile не установлен',
        'Для подписания документов необходимо установить приложение eGov Mobile',
        [
          {
            text: 'Отмена',
            style: 'cancel',
            onPress: () => resolve(false),
          },
          {
            text: 'Установить',
            onPress: async () => {
              const storeUrl =
                Platform.OS === 'ios'
                  ? EGOV_MOBILE.IOS_STORE_URL
                  : EGOV_MOBILE.ANDROID_STORE_URL;

              try {
                await Linking.openURL(storeUrl);
                resolve(false);
              } catch (error) {
                console.error('Error opening store:', error);
                resolve(false);
              }
            },
          },
        ],
      );
    });
  };
  ```

### 8. Главная функция подписания

- [ ] Реализовать основную функцию `signWithEgovMobile`:
  ```typescript
  /**
   * Инициирует процесс подписания через eGov Mobile
   * @param documentId - ID документа
   * @param documentType - Тип документа (agreement, invoice, act, registry)
   * @returns sessionId или null если отменено
   */
  export const signWithEgovMobile = async (
    documentId: string,
    documentType: string,
  ): Promise<string | null> => {
    try {
      // Шаг 1: Создать сессию на backend
      console.log('Creating signing session...', {documentId, documentType});

      const {data} = await api.post<EgovSignSessionResponse>(
        '/api/v1/egov-sign/init',
        {
          documentId,
          documentType,
        },
      );

      const {sessionId, qrCode} = data;

      console.log('Session created:', {sessionId});

      // Шаг 2: Извлечь API URL из QR кода
      // QR код содержит: mobileSign:{API_URL}
      const apiUrl = qrCode.replace('mobileSign:', '');

      console.log('API URL:', apiUrl);

      // Шаг 3: Сгенерировать Dynamic Link
      const dynamicLink = generateDynamicLink({
        apiUrl,
        platform: Platform.OS as 'android' | 'ios',
      });

      console.log('Dynamic Link:', dynamicLink);

      // Шаг 4: Проверить, можно ли открыть ссылку
      const canOpen = await Linking.canOpenURL(dynamicLink);

      if (!canOpen) {
        console.warn('Cannot open eGov Mobile');
        const shouldContinue = await showInstallDialog();
        if (!shouldContinue) {
          return null;
        }
      }

      // Шаг 5: Открыть eGov Mobile
      console.log('Opening eGov Mobile...');
      await Linking.openURL(dynamicLink);

      // Вернуть sessionId для последующего polling
      return sessionId;
    } catch (error) {
      console.error('Error signing with eGov Mobile:', error);

      Alert.alert(
        'Ошибка',
        'Не удалось инициировать подписание. Попробуйте еще раз.',
      );

      return null;
    }
  };
  ```

### 9. Функция проверки статуса сессии

- [ ] Добавить функцию для polling статуса:
  ```typescript
  /**
   * Проверяет статус сессии подписания
   */
  export const checkSigningStatus = async (
    sessionId: string,
  ): Promise<{
    status: 'PENDING' | 'SIGNED' | 'EXPIRED' | 'ERROR';
    error?: string;
  }> => {
    try {
      const {data} = await api.get<{
        status: 'PENDING' | 'SIGNED' | 'EXPIRED' | 'ERROR';
        error?: string;
      }>(`/api/v1/egov-sign/session/${sessionId}/status`);

      return data;
    } catch (error) {
      console.error('Error checking signing status:', error);
      return {
        status: 'ERROR',
        error: 'Failed to check status',
      };
    }
  };
  ```

### 10. Polling с автоматическим завершением

- [ ] Создать функцию для автоматического polling:
  ```typescript
  /**
   * Запускает polling статуса сессии подписания
   * @param sessionId - ID сессии
   * @param onStatusChange - Callback при изменении статуса
   * @param interval - Интервал проверки в мс (по умолчанию 3000)
   * @param maxAttempts - Максимальное количество попыток (по умолчанию 600 = 30 минут)
   * @returns Функция для остановки polling
   */
  export const startStatusPolling = (
    sessionId: string,
    onStatusChange: (status: {
      status: 'PENDING' | 'SIGNED' | 'EXPIRED' | 'ERROR';
      error?: string;
    }) => void,
    interval: number = 3000,
    maxAttempts: number = 600,
  ): (() => void) => {
    let attempts = 0;
    let timeoutId: NodeJS.Timeout;

    const poll = async () => {
      attempts++;

      if (attempts > maxAttempts) {
        console.warn('Max polling attempts reached');
        onStatusChange({status: 'EXPIRED'});
        return;
      }

      const status = await checkSigningStatus(sessionId);
      onStatusChange(status);

      // Продолжить polling только если статус PENDING
      if (status.status === 'PENDING') {
        timeoutId = setTimeout(poll, interval);
      }
    };

    // Запустить первый poll
    poll();

    // Вернуть функцию для остановки
    return () => {
      if (timeoutId) {
        clearTimeout(timeoutId);
      }
    };
  };
  ```

### 11. Экспорт всех функций

- [ ] Экспортировать публичное API:
  ```typescript
  export const egovSignService = {
    signWithEgovMobile,
    checkSigningStatus,
    startStatusPolling,
    isEgovMobileInstalled,
  };

  export default egovSignService;
  ```

### 12. Логирование

- [ ] Добавить подробное логирование для debugging:
  ```typescript
  // В начале файла
  const DEBUG = __DEV__;

  const log = (message: string, data?: any) => {
    if (DEBUG) {
      console.log(`[EgovSignService] ${message}`, data || '');
    }
  };

  const logError = (message: string, error?: any) => {
    console.error(`[EgovSignService] ${message}`, error || '');
  };
  ```

### 13. Обработка ошибок сети

- [ ] Добавить обработку различных ошибок:
  ```typescript
  const handleApiError = (error: any): string => {
    if (error.response) {
      // Ошибка от сервера
      return error.response.data?.message || 'Ошибка сервера';
    } else if (error.request) {
      // Нет ответа от сервера
      return 'Нет соединения с сервером';
    } else {
      // Другая ошибка
      return error.message || 'Неизвестная ошибка';
    }
  };
  ```

### 14. Тестирование

- [ ] Написать unit-тесты:
  ```typescript
  // __tests__/egovSignService.test.ts
  import {encodeEgovUrl, generateDynamicLink} from '../egovSignService';

  describe('egovSignService', () => {
    describe('encodeEgovUrl', () => {
      it('should encode special characters', () => {
        const url = 'https://api.com?session=123&type=agreement';
        const encoded = encodeEgovUrl(url);
        expect(encoded).toContain('%3F'); // ?
        expect(encoded).toContain('%3D'); // =
        expect(encoded).toContain('%26'); // &
      });
    });

    describe('generateDynamicLink', () => {
      it('should generate Android dynamic link', () => {
        const link = generateDynamicLink({
          apiUrl: 'https://api.test.com',
          platform: 'android',
        });
        expect(link).toContain('apn=kz.mobile.mgov');
      });

      it('should generate iOS dynamic link', () => {
        const link = generateDynamicLink({
          apiUrl: 'https://api.test.com',
          platform: 'ios',
        });
        expect(link).toContain('isi=1476128386');
        expect(link).toContain('ibi=kz.egov.mobile');
      });
    });
  });
  ```

### 15. Интеграция с API клиентом

- [ ] Убедиться что API endpoints настроены в `src/api/index.ts`:
  ```typescript
  // src/api/index.ts
  export const api = {
    // ... существующие методы

    egovSign: {
      initSession: (documentId: string, documentType: string) =>
        api.post('/api/v1/egov-sign/init', {documentId, documentType}),

      getSessionStatus: (sessionId: string) =>
        api.get(`/api/v1/egov-sign/session/${sessionId}/status`),
    },
  };
  ```

### 16. Документация

- [ ] Создать JSDoc комментарии для всех функций
- [ ] Добавить примеры использования:
  ```typescript
  /**
   * Пример использования:
   *
   * ```typescript
   * // Инициировать подписание
   * const sessionId = await egovSignService.signWithEgovMobile('123', 'agreement');
   *
   * if (sessionId) {
   *   // Запустить polling
   *   const stopPolling = egovSignService.startStatusPolling(
   *     sessionId,
   *     (status) => {
   *       if (status.status === 'SIGNED') {
   *         console.log('Document signed!');
   *       }
   *     }
   *   );
   *
   *   // Остановить polling при необходимости
   *   // stopPolling();
   * }
   * ```
   */
  ```

## 📚 Требования

### URL Encoding
- ✅ Правильное кодирование специальных символов
- ✅ Поддержка всех параметров eGov Mobile

### Platform Support
- ✅ Корректная генерация ссылок для Android
- ✅ Корректная генерация ссылок для iOS
- ✅ Fallback на App Store если приложение не установлено

### Error Handling
- ✅ Обработка ошибок сети
- ✅ Обработка отсутствия eGov Mobile
- ✅ Timeout для polling
- ✅ Понятные сообщения об ошибках

### Logging
- ✅ Подробное логирование в dev режиме
- ✅ Отслеживание каждого шага процесса

## 🔗 Зависимости

**Зависит от:**
- Mobile Task 1: Deep Linking Config (для callback)
- Backend Task 1: EgovSignController (API endpoints)

**Необходимо для:**
- Mobile Task 3: Signing Screen Update (использование сервиса)
- Mobile Task 4: API Client (интеграция)

## ⚠️ Важные замечания

1. **URL Encoding**: Обязательно использовать правильное кодирование для eGov Mobile
2. **Dynamic Links**: Формат должен точно соответствовать документации eGov
3. **Platform Detection**: Разные параметры для Android и iOS
4. **Error Recovery**: Пользователь должен иметь возможность повторить попытку
5. **Polling Limits**: Защита от бесконечного polling
6. **Deep Link Return**: После подписания eGov Mobile вернет в приложение через `coube://sign-callback`

## 📊 Критерии приемки

- [ ] Сервис создан в `src/services/egovSignService.ts`
- [ ] URL encoding работает корректно
- [ ] Dynamic Links генерируются правильно для Android и iOS
- [ ] Открытие eGov Mobile работает
- [ ] Проверка установки приложения работает
- [ ] Диалог установки показывается когда нужно
- [ ] Функция `signWithEgovMobile` инициирует подписание
- [ ] Polling статуса работает с автоматическим завершением
- [ ] Обработка ошибок реализована
- [ ] Логирование работает в dev режиме
- [ ] Unit-тесты написаны и проходят
- [ ] JSDoc документация добавлена
- [ ] Код соответствует TypeScript best practices

---

**Приоритет:** 🔴 Высокий (блокирует Mobile Task 3)
**Оценка:** 4-5 часов
**Assignee:** Mobile Developer
**Зависит от:** Mobile Task 1; Backend Task 1
