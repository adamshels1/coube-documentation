# Mobile Task 4: API Client для eGov подписания

## 📋 Описание

Создать или обновить API клиент для взаимодействия с backend endpoints для eGov подписания. Обеспечить типизацию, обработку ошибок и интеграцию с существующим API слоем.

## 📍 Расположение

**Файлы:**
- `coube-mobile/src/api/egovSign.ts` (новый)
- `coube-mobile/src/api/index.ts` (обновить)
- `coube-mobile/src/types/egovSign.ts` (новый)

## 🎯 Функциональность

1. Создание сессии подписания (`POST /api/v1/egov-sign/init`)
2. Получение статуса сессии (`GET /api/v1/egov-sign/session/{id}/status`)
3. Получение полной информации о сессии (`GET /api/v1/egov-sign/session/{id}`)
4. Типизация всех request/response
5. Обработка ошибок и retry логики

## ✅ Чеклист реализации

### 1. Создать типы для eGov подписания

- [ ] Создать `src/types/egovSign.ts`:
  ```typescript
  /**
   * Типы для eGov Mobile подписания
   */

  // Типы документов
  export type DocumentType = 'agreement' | 'invoice' | 'act' | 'registry';

  // Статусы сессии
  export type SessionStatus = 'PENDING' | 'SIGNED' | 'EXPIRED' | 'ERROR';

  // Request для создания сессии
  export interface InitSessionRequest {
    documentId: string;
    documentType: DocumentType;
  }

  // Response с QR кодом
  export interface InitSessionResponse {
    sessionId: string;
    qrCode: string;
    expiresAt: string; // ISO 8601
  }

  // Response со статусом сессии
  export interface SessionStatusResponse {
    status: SessionStatus;
    error?: string;
  }

  // Полная информация о сессии
  export interface SessionInfo {
    sessionId: string;
    documentId: string;
    documentType: DocumentType;
    status: SessionStatus;
    createdAt: string; // ISO 8601
    expiresAt: string; // ISO 8601
    signedAt?: string; // ISO 8601
    error?: string;
  }

  // Ошибка API
  export interface EgovSignApiError {
    message: string;
    code?: string;
    details?: any;
  }
  ```

### 2. Создать API клиент

- [ ] Создать `src/api/egovSign.ts`:
  ```typescript
  import {AxiosResponse} from 'axios';
  import {apiClient} from './apiClient'; // Существующий axios instance
  import {
    InitSessionRequest,
    InitSessionResponse,
    SessionStatusResponse,
    SessionInfo,
    EgovSignApiError,
  } from '@/types/egovSign';

  /**
   * API клиент для eGov подписания
   */
  class EgovSignApi {
    private readonly baseUrl = '/api/v1/egov-sign';

    /**
     * Создать сессию подписания
     * @param documentId - ID документа
     * @param documentType - Тип документа
     * @returns Данные сессии с QR кодом
     */
    async initSession(
      documentId: string,
      documentType: string,
    ): Promise<InitSessionResponse> {
      try {
        const request: InitSessionRequest = {
          documentId,
          documentType: documentType as any,
        };

        const response: AxiosResponse<InitSessionResponse> =
          await apiClient.post(`${this.baseUrl}/init`, request);

        return response.data;
      } catch (error) {
        throw this.handleError(error, 'Failed to initialize signing session');
      }
    }

    /**
     * Получить статус сессии подписания
     * @param sessionId - UUID сессии
     * @returns Статус сессии
     */
    async getSessionStatus(
      sessionId: string,
    ): Promise<SessionStatusResponse> {
      try {
        const response: AxiosResponse<SessionStatusResponse> =
          await apiClient.get(`${this.baseUrl}/session/${sessionId}/status`);

        return response.data;
      } catch (error) {
        throw this.handleError(error, 'Failed to get session status');
      }
    }

    /**
     * Получить полную информацию о сессии
     * @param sessionId - UUID сессии
     * @returns Полная информация о сессии
     */
    async getSessionInfo(sessionId: string): Promise<SessionInfo> {
      try {
        const response: AxiosResponse<SessionInfo> = await apiClient.get(
          `${this.baseUrl}/session/${sessionId}`,
        );

        return response.data;
      } catch (error) {
        throw this.handleError(error, 'Failed to get session info');
      }
    }

    /**
     * Обработка ошибок API
     */
    private handleError(error: any, defaultMessage: string): Error {
      if (error.response) {
        // Ошибка от сервера
        const apiError: EgovSignApiError = error.response.data;
        const message = apiError.message || defaultMessage;

        console.error('EgovSignApi error:', {
          status: error.response.status,
          message,
          details: apiError.details,
        });

        return new Error(message);
      } else if (error.request) {
        // Нет ответа от сервера
        console.error('EgovSignApi network error:', error.request);
        return new Error('Нет соединения с сервером');
      } else {
        // Другая ошибка
        console.error('EgovSignApi error:', error.message);
        return new Error(error.message || defaultMessage);
      }
    }
  }

  // Singleton instance
  export const egovSignApi = new EgovSignApi();

  export default egovSignApi;
  ```

### 3. Интегрировать в общий API

- [ ] Обновить `src/api/index.ts`:
  ```typescript
  import {egovSignApi} from './egovSign';

  export const api = {
    // ... существующие API
    auth: authApi,
    orders: ordersApi,
    documents: documentsApi,

    // Новый API для eGov подписания
    egovSign: egovSignApi,
  };

  export default api;
  ```

### 4. Добавить retry логику (опционально)

- [ ] Создать retry wrapper:
  ```typescript
  // src/api/utils/retry.ts
  export interface RetryOptions {
    maxRetries: number;
    retryDelay: number;
    shouldRetry?: (error: any) => boolean;
  }

  export const defaultRetryOptions: RetryOptions = {
    maxRetries: 3,
    retryDelay: 1000,
    shouldRetry: (error: any) => {
      // Retry только для network errors и 5xx
      return (
        !error.response ||
        (error.response.status >= 500 && error.response.status < 600)
      );
    },
  };

  export async function withRetry<T>(
    fn: () => Promise<T>,
    options: Partial<RetryOptions> = {},
  ): Promise<T> {
    const opts = {...defaultRetryOptions, ...options};
    let lastError: any;

    for (let attempt = 0; attempt <= opts.maxRetries; attempt++) {
      try {
        return await fn();
      } catch (error) {
        lastError = error;

        const shouldRetry = opts.shouldRetry
          ? opts.shouldRetry(error)
          : defaultRetryOptions.shouldRetry!(error);

        if (!shouldRetry || attempt === opts.maxRetries) {
          throw error;
        }

        console.log(
          `Retry attempt ${attempt + 1}/${opts.maxRetries} after ${opts.retryDelay}ms`,
        );

        await new Promise(resolve => setTimeout(resolve, opts.retryDelay));
      }
    }

    throw lastError;
  }
  ```

- [ ] Использовать retry в API:
  ```typescript
  import {withRetry} from './utils/retry';

  async initSession(
    documentId: string,
    documentType: string,
  ): Promise<InitSessionResponse> {
    return withRetry(async () => {
      const request: InitSessionRequest = {documentId, documentType: documentType as any};
      const response = await apiClient.post(`${this.baseUrl}/init`, request);
      return response.data;
    });
  }
  ```

### 5. Добавить interceptors для логирования

- [ ] Настроить interceptors в `apiClient`:
  ```typescript
  // src/api/apiClient.ts
  import axios from 'axios';

  export const apiClient = axios.create({
    baseURL: process.env.API_BASE_URL || 'https://api.coube.kz',
    timeout: 30000,
    headers: {
      'Content-Type': 'application/json',
    },
  });

  // Request interceptor
  apiClient.interceptors.request.use(
    config => {
      // Добавить auth token
      const token = getAuthToken(); // Получить из store/AsyncStorage
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }

      if (__DEV__) {
        console.log('API Request:', {
          method: config.method?.toUpperCase(),
          url: config.url,
          data: config.data,
        });
      }

      return config;
    },
    error => {
      console.error('Request interceptor error:', error);
      return Promise.reject(error);
    },
  );

  // Response interceptor
  apiClient.interceptors.response.use(
    response => {
      if (__DEV__) {
        console.log('API Response:', {
          status: response.status,
          url: response.config.url,
          data: response.data,
        });
      }
      return response;
    },
    error => {
      if (__DEV__) {
        console.error('API Error:', {
          status: error.response?.status,
          url: error.config?.url,
          data: error.response?.data,
        });
      }

      // Обработка 401 (unauthorized)
      if (error.response?.status === 401) {
        // Redirect to login или refresh token
        handleUnauthorized();
      }

      return Promise.reject(error);
    },
  );
  ```

### 6. Добавить кэширование (опционально)

- [ ] Создать простой кэш для session info:
  ```typescript
  // src/api/egovSign.ts
  class EgovSignApi {
    private sessionCache: Map<string, {data: SessionInfo; timestamp: number}> =
      new Map();
    private readonly cacheTtl = 5000; // 5 секунд

    async getSessionInfo(
      sessionId: string,
      useCache: boolean = true,
    ): Promise<SessionInfo> {
      // Проверить кэш
      if (useCache) {
        const cached = this.sessionCache.get(sessionId);
        if (cached && Date.now() - cached.timestamp < this.cacheTtl) {
          console.log('Using cached session info');
          return cached.data;
        }
      }

      // Запросить с сервера
      const response = await apiClient.get(
        `${this.baseUrl}/session/${sessionId}`,
      );

      // Сохранить в кэш
      this.sessionCache.set(sessionId, {
        data: response.data,
        timestamp: Date.now(),
      });

      return response.data;
    }

    clearCache() {
      this.sessionCache.clear();
    }
  }
  ```

### 7. Тестирование API клиента

- [ ] Написать unit-тесты:
  ```typescript
  // __tests__/api/egovSign.test.ts
  import MockAdapter from 'axios-mock-adapter';
  import {apiClient} from '@/api/apiClient';
  import egovSignApi from '@/api/egovSign';

  describe('EgovSignApi', () => {
    let mock: MockAdapter;

    beforeEach(() => {
      mock = new MockAdapter(apiClient);
    });

    afterEach(() => {
      mock.restore();
    });

    describe('initSession', () => {
      it('should create signing session', async () => {
        const mockResponse = {
          sessionId: '123e4567-e89b-12d3-a456-426614174000',
          qrCode: 'mobileSign:https://api.test.com/...',
          expiresAt: '2024-01-01T12:30:00.000Z',
        };

        mock
          .onPost('/api/v1/egov-sign/init')
          .reply(200, mockResponse);

        const result = await egovSignApi.initSession('doc123', 'agreement');

        expect(result).toEqual(mockResponse);
        expect(result.sessionId).toBeTruthy();
        expect(result.qrCode).toContain('mobileSign:');
      });

      it('should handle errors', async () => {
        mock
          .onPost('/api/v1/egov-sign/init')
          .reply(500, {message: 'Server error'});

        await expect(
          egovSignApi.initSession('doc123', 'agreement'),
        ).rejects.toThrow('Server error');
      });
    });

    describe('getSessionStatus', () => {
      it('should return session status', async () => {
        const mockResponse = {status: 'PENDING'};

        mock
          .onGet('/api/v1/egov-sign/session/123/status')
          .reply(200, mockResponse);

        const result = await egovSignApi.getSessionStatus('123');

        expect(result.status).toBe('PENDING');
      });
    });
  });
  ```

### 8. Добавить TypeScript strict mode

- [ ] Убедиться что типы строгие:
  ```typescript
  // tsconfig.json
  {
    "compilerOptions": {
      "strict": true,
      "noImplicitAny": true,
      "strictNullChecks": true
    }
  }
  ```

### 9. Обработка сетевых ошибок

- [ ] Добавить проверку сети:
  ```typescript
  import NetInfo from '@react-native-community/netinfo';

  class EgovSignApi {
    private async checkNetworkConnection(): Promise<boolean> {
      const state = await NetInfo.fetch();
      return state.isConnected ?? false;
    }

    async initSession(
      documentId: string,
      documentType: string,
    ): Promise<InitSessionResponse> {
      // Проверить подключение к интернету
      const isConnected = await this.checkNetworkConnection();
      if (!isConnected) {
        throw new Error('Нет подключения к интернету');
      }

      // ... остальной код
    }
  }
  ```

### 10. Документация API

- [ ] Добавить JSDoc комментарии:
  ```typescript
  /**
   * EgovSignApi - API клиент для работы с eGov Mobile подписанием
   *
   * @example
   * ```typescript
   * // Создать сессию
   * const session = await api.egovSign.initSession('doc123', 'agreement');
   *
   * // Проверить статус
   * const status = await api.egovSign.getSessionStatus(session.sessionId);
   *
   * if (status.status === 'SIGNED') {
   *   console.log('Document signed!');
   * }
   * ```
   */
  ```

### 11. Environment variables

- [ ] Настроить env переменные:
  ```typescript
  // .env
  API_BASE_URL=https://api.coube.kz
  API_TIMEOUT=30000

  // .env.development
  API_BASE_URL=https://dev-api.coube.kz
  API_TIMEOUT=30000

  // Использование
  import Config from 'react-native-config';

  export const apiClient = axios.create({
    baseURL: Config.API_BASE_URL,
    timeout: parseInt(Config.API_TIMEOUT || '30000', 10),
  });
  ```

### 12. Error codes mapping

- [ ] Создать маппинг error codes:
  ```typescript
  // src/api/utils/errorCodes.ts
  export const ERROR_CODES = {
    SESSION_NOT_FOUND: 'SESSION_NOT_FOUND',
    SESSION_EXPIRED: 'SESSION_EXPIRED',
    DOCUMENT_NOT_FOUND: 'DOCUMENT_NOT_FOUND',
    UNAUTHORIZED: 'UNAUTHORIZED',
    NETWORK_ERROR: 'NETWORK_ERROR',
  } as const;

  export const ERROR_MESSAGES: Record<string, string> = {
    [ERROR_CODES.SESSION_NOT_FOUND]: 'Сессия подписания не найдена',
    [ERROR_CODES.SESSION_EXPIRED]: 'Истек срок действия сессии',
    [ERROR_CODES.DOCUMENT_NOT_FOUND]: 'Документ не найден',
    [ERROR_CODES.UNAUTHORIZED]: 'Требуется авторизация',
    [ERROR_CODES.NETWORK_ERROR]: 'Ошибка сети',
  };

  export function getErrorMessage(code?: string): string {
    return code ? ERROR_MESSAGES[code] || 'Неизвестная ошибка' : 'Неизвестная ошибка';
  }
  ```

### 13. Интеграция с React Query (опционально)

- [ ] Настроить React Query hooks:
  ```typescript
  // src/hooks/useEgovSign.ts
  import {useQuery, useMutation} from '@tanstack/react-query';
  import egovSignApi from '@/api/egovSign';

  export function useInitSession() {
    return useMutation({
      mutationFn: ({documentId, documentType}: {documentId: string; documentType: string}) =>
        egovSignApi.initSession(documentId, documentType),
    });
  }

  export function useSessionStatus(sessionId: string, enabled: boolean = true) {
    return useQuery({
      queryKey: ['egovSign', 'status', sessionId],
      queryFn: () => egovSignApi.getSessionStatus(sessionId),
      enabled,
      refetchInterval: 3000, // Polling каждые 3 секунды
    });
  }
  ```

## 📚 Требования

### TypeScript
- ✅ Все типы четко определены
- ✅ Нет использования `any` без необходимости
- ✅ Strict mode enabled

### Error Handling
- ✅ Обработка network errors
- ✅ Обработка server errors (4xx, 5xx)
- ✅ Понятные сообщения об ошибках

### Logging
- ✅ Логирование запросов в dev режиме
- ✅ Логирование ошибок
- ✅ Не логировать sensitive данные

### Testing
- ✅ Unit тесты для всех методов
- ✅ Mocking axios requests
- ✅ Coverage > 80%

## 🔗 Зависимости

**Зависит от:**
- Backend Task 1: EgovSignController (API endpoints)
- Существующий API клиент (axios)

**Необходимо для:**
- Mobile Task 2: eGov Sign Service (использование API)
- Mobile Task 3: Signing Screen Update (API вызовы)

## ⚠️ Важные замечания

1. **Authorization**: Все запросы требуют Bearer token
2. **Timeout**: Установить адекватный timeout (30 секунд)
3. **Retry**: Retry только для network errors и 5xx
4. **Cache**: Кэшировать только неизменяемые данные
5. **Types**: Использовать строгую типизацию

## 📊 Критерии приемки

- [ ] Типы созданы в `src/types/egovSign.ts`
- [ ] API клиент создан в `src/api/egovSign.ts`
- [ ] Интегрирован в `src/api/index.ts`
- [ ] Метод `initSession` работает
- [ ] Метод `getSessionStatus` работает
- [ ] Метод `getSessionInfo` работает
- [ ] Error handling реализован
- [ ] Interceptors настроены
- [ ] Retry логика работает (опционально)
- [ ] Unit тесты написаны и проходят
- [ ] JSDoc документация добавлена
- [ ] TypeScript strict mode

---

**Приоритет:** 🔴 Высокий (блокирует Mobile Task 2, 3)
**Оценка:** 3-4 часа
**Assignee:** Mobile Developer
**Зависит от:** Backend Task 1
