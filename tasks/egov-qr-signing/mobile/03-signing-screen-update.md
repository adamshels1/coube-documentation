# Mobile Task 3: Обновление экрана подписания

## 📋 Описание

Обновить экран `SigningOrderDetailsScreen` для добавления функционала подписания через eGov Mobile. Интегрировать eGov Sign Service и обработать весь flow подписания.

## 📍 Расположение

**Файл:** `coube-mobile/src/screens/SigningOrderDetailsScreen.tsx`

## 🎯 Функциональность

1. Кнопка "Подписать договор" инициирует подписание через eGov Mobile
2. Показ индикатора загрузки во время создания сессии
3. Автоматическое открытие eGov Mobile
4. Отображение статуса подписания (в процессе, успешно, ошибка)
5. Обновление UI после успешного подписания
6. Обработка возврата из eGov Mobile через deep link

## ✅ Чеклист реализации

### 1. Изучить текущую реализацию

- [ ] Открыть `SigningOrderDetailsScreen.tsx`
- [ ] Найти существующий код подписания (если есть)
- [ ] Понять структуру данных заказа/договора

### 2. Импорты

- [ ] Добавить необходимые импорты:
  ```typescript
  import React, {useState, useEffect, useRef} from 'react';
  import {View, Text, StyleSheet, Alert, ActivityIndicator} from 'react-native';
  import {useNavigation, useRoute, useFocusEffect} from '@react-navigation/native';
  import egovSignService from '@/services/egovSignService';
  import {SigningStatus} from '@/types/signing';
  ```

### 3. Добавить типы

- [ ] Создать типы для подписания:
  ```typescript
  // src/types/signing.ts
  export type SigningStatus =
    | 'idle'
    | 'creating_session'
    | 'opening_egov'
    | 'waiting_signature'
    | 'signed'
    | 'error'
    | 'expired';

  export interface SigningState {
    status: SigningStatus;
    sessionId: string | null;
    error: string | null;
  }
  ```

### 4. State management

- [ ] Добавить state для подписания:
  ```typescript
  const SigningOrderDetailsScreen = () => {
    const navigation = useNavigation();
    const route = useRoute();

    // Данные заказа/договора из route params
    const {orderId, documentId, documentType} = route.params as {
      orderId: string;
      documentId: string;
      documentType: string;
    };

    // State для подписания
    const [signingState, setSigningState] = useState<SigningState>({
      status: 'idle',
      sessionId: null,
      error: null,
    });

    // Ref для остановки polling
    const stopPollingRef = useRef<(() => void) | null>(null);

    // Loading индикатор
    const isLoading =
      signingState.status === 'creating_session' ||
      signingState.status === 'opening_egov';

    const isWaiting = signingState.status === 'waiting_signature';
    const isSigned = signingState.status === 'signed';
    const hasError = signingState.status === 'error';
  };
  ```

### 5. Функция инициации подписания

- [ ] Реализовать обработчик кнопки "Подписать":
  ```typescript
  const handleSignContract = async () => {
    try {
      // Шаг 1: Установить статус "создание сессии"
      setSigningState({
        status: 'creating_session',
        sessionId: null,
        error: null,
      });

      // Шаг 2: Инициировать подписание через eGov Mobile
      const sessionId = await egovSignService.signWithEgovMobile(
        documentId,
        documentType,
      );

      if (!sessionId) {
        // Пользователь отменил или приложение не установлено
        setSigningState({
          status: 'idle',
          sessionId: null,
          error: null,
        });
        return;
      }

      // Шаг 3: eGov Mobile открыто, переключить статус
      setSigningState({
        status: 'opening_egov',
        sessionId,
        error: null,
      });

      // Шаг 4: Запустить polling статуса
      startPolling(sessionId);
    } catch (error) {
      console.error('Error initiating signing:', error);
      setSigningState({
        status: 'error',
        sessionId: null,
        error: 'Не удалось инициировать подписание',
      });
    }
  };
  ```

### 6. Polling статуса

- [ ] Реализовать polling:
  ```typescript
  const startPolling = (sessionId: string) => {
    // Установить статус "ожидание подписания"
    setSigningState(prev => ({
      ...prev,
      status: 'waiting_signature',
    }));

    // Запустить polling
    const stopPolling = egovSignService.startStatusPolling(
      sessionId,
      status => {
        console.log('Signing status update:', status);

        if (status.status === 'SIGNED') {
          // Успешное подписание
          setSigningState({
            status: 'signed',
            sessionId,
            error: null,
          });

          // Остановить polling
          if (stopPollingRef.current) {
            stopPollingRef.current();
            stopPollingRef.current = null;
          }

          // Показать успешное сообщение
          Alert.alert(
            'Успешно',
            'Договор успешно подписан',
            [
              {
                text: 'OK',
                onPress: () => {
                  // Вернуться назад или обновить список
                  navigation.goBack();
                },
              },
            ],
          );
        } else if (status.status === 'ERROR') {
          // Ошибка
          setSigningState({
            status: 'error',
            sessionId,
            error: status.error || 'Ошибка при подписании',
          });

          if (stopPollingRef.current) {
            stopPollingRef.current();
            stopPollingRef.current = null;
          }

          Alert.alert('Ошибка', status.error || 'Ошибка при подписании');
        } else if (status.status === 'EXPIRED') {
          // Истек срок
          setSigningState({
            status: 'expired',
            sessionId,
            error: 'Истек срок действия сессии',
          });

          if (stopPollingRef.current) {
            stopPollingRef.current();
            stopPollingRef.current = null;
          }

          Alert.alert(
            'Время истекло',
            'Истек срок действия сессии подписания. Попробуйте еще раз.',
          );
        }
        // Если PENDING - polling продолжается автоматически
      },
    );

    // Сохранить функцию остановки
    stopPollingRef.current = stopPolling;
  };
  ```

### 7. Cleanup при размонтировании

- [ ] Добавить useEffect для cleanup:
  ```typescript
  useEffect(() => {
    return () => {
      // Остановить polling при размонтировании
      if (stopPollingRef.current) {
        console.log('Stopping polling on unmount');
        stopPollingRef.current();
        stopPollingRef.current = null;
      }
    };
  }, []);
  ```

### 8. Обработка возврата из eGov Mobile

- [ ] Добавить useFocusEffect для обработки возврата:
  ```typescript
  useFocusEffect(
    React.useCallback(() => {
      // Когда пользователь вернулся на экран
      if (signingState.status === 'opening_egov' && signingState.sessionId) {
        console.log('User returned from eGov Mobile, starting polling');
        // Переключить статус на ожидание
        // Polling уже запущен в handleSignContract
        setSigningState(prev => ({
          ...prev,
          status: 'waiting_signature',
        }));
      }
    }, [signingState.status, signingState.sessionId]),
  );
  ```

### 9. UI - индикаторы статуса

- [ ] Добавить отображение статуса:
  ```typescript
  const renderSigningStatus = () => {
    switch (signingState.status) {
      case 'creating_session':
        return (
          <View style={styles.statusContainer}>
            <ActivityIndicator size="large" color="#0066CC" />
            <Text style={styles.statusText}>Создание сессии подписания...</Text>
          </View>
        );

      case 'opening_egov':
        return (
          <View style={styles.statusContainer}>
            <ActivityIndicator size="large" color="#0066CC" />
            <Text style={styles.statusText}>Открытие eGov Mobile...</Text>
          </View>
        );

      case 'waiting_signature':
        return (
          <View style={styles.statusContainer}>
            <ActivityIndicator size="large" color="#0066CC" />
            <Text style={styles.statusText}>Ожидание подписания в eGov Mobile...</Text>
            <Text style={styles.statusSubtext}>
              Подпишите документ в приложении eGov Mobile
            </Text>
          </View>
        );

      case 'signed':
        return (
          <View style={styles.statusContainer}>
            <Text style={styles.successText}>✅ Документ успешно подписан</Text>
          </View>
        );

      case 'error':
        return (
          <View style={styles.statusContainer}>
            <Text style={styles.errorText}>❌ {signingState.error}</Text>
          </View>
        );

      case 'expired':
        return (
          <View style={styles.statusContainer}>
            <Text style={styles.errorText}>⏱️ Истек срок действия сессии</Text>
          </View>
        );

      default:
        return null;
    }
  };
  ```

### 10. UI - кнопка подписания

- [ ] Обновить кнопку "Подписать договор":
  ```typescript
  <TouchableOpacity
    style={[
      styles.signButton,
      (isLoading || isWaiting || isSigned) && styles.signButtonDisabled,
    ]}
    onPress={handleSignContract}
    disabled={isLoading || isWaiting || isSigned}>
    {isLoading ? (
      <ActivityIndicator color="#fff" />
    ) : (
      <Text style={styles.signButtonText}>
        {isSigned ? 'Подписан' : 'Подписать договор'}
      </Text>
    )}
  </TouchableOpacity>
  ```

### 11. UI - кнопка отмены

- [ ] Добавить кнопку отмены подписания:
  ```typescript
  const handleCancelSigning = () => {
    Alert.alert(
      'Отменить подписание?',
      'Вы уверены что хотите отменить процесс подписания?',
      [
        {text: 'Нет', style: 'cancel'},
        {
          text: 'Да, отменить',
          style: 'destructive',
          onPress: () => {
            // Остановить polling
            if (stopPollingRef.current) {
              stopPollingRef.current();
              stopPollingRef.current = null;
            }

            // Сбросить состояние
            setSigningState({
              status: 'idle',
              sessionId: null,
              error: null,
            });
          },
        },
      ],
    );
  };

  // В render:
  {isWaiting && (
    <TouchableOpacity
      style={styles.cancelButton}
      onPress={handleCancelSigning}>
      <Text style={styles.cancelButtonText}>Отменить</Text>
    </TouchableOpacity>
  )}
  ```

### 12. Стили

- [ ] Добавить стили:
  ```typescript
  const styles = StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: '#fff',
      padding: 16,
    },
    statusContainer: {
      padding: 20,
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: '#F5F5F5',
      borderRadius: 8,
      marginVertical: 16,
    },
    statusText: {
      fontSize: 16,
      fontWeight: '600',
      color: '#333',
      marginTop: 12,
      textAlign: 'center',
    },
    statusSubtext: {
      fontSize: 14,
      color: '#666',
      marginTop: 8,
      textAlign: 'center',
    },
    successText: {
      fontSize: 16,
      fontWeight: '600',
      color: '#28A745',
    },
    errorText: {
      fontSize: 16,
      fontWeight: '600',
      color: '#DC3545',
      textAlign: 'center',
    },
    signButton: {
      backgroundColor: '#0066CC',
      paddingVertical: 14,
      paddingHorizontal: 24,
      borderRadius: 8,
      alignItems: 'center',
      marginVertical: 16,
    },
    signButtonDisabled: {
      backgroundColor: '#CCCCCC',
    },
    signButtonText: {
      color: '#fff',
      fontSize: 16,
      fontWeight: '600',
    },
    cancelButton: {
      backgroundColor: '#fff',
      borderWidth: 1,
      borderColor: '#DC3545',
      paddingVertical: 12,
      paddingHorizontal: 24,
      borderRadius: 8,
      alignItems: 'center',
      marginTop: 8,
    },
    cancelButtonText: {
      color: '#DC3545',
      fontSize: 16,
      fontWeight: '600',
    },
  });
  ```

### 13. Обработка ошибок

- [ ] Добавить обработку различных сценариев ошибок:
  ```typescript
  const handleSigningError = (error: any) => {
    let errorMessage = 'Произошла ошибка при подписании';

    if (error.response?.status === 404) {
      errorMessage = 'Документ не найден';
    } else if (error.response?.status === 403) {
      errorMessage = 'Нет прав для подписания документа';
    } else if (error.response?.status === 500) {
      errorMessage = 'Ошибка сервера. Попробуйте позже';
    } else if (error.message) {
      errorMessage = error.message;
    }

    setSigningState({
      status: 'error',
      sessionId: null,
      error: errorMessage,
    });

    Alert.alert('Ошибка', errorMessage);
  };
  ```

### 14. Retry функциональность

- [ ] Добавить возможность повтора:
  ```typescript
  const handleRetry = () => {
    // Сбросить состояние
    setSigningState({
      status: 'idle',
      sessionId: null,
      error: null,
    });

    // Повторить подписание
    handleSignContract();
  };

  // В render для error/expired статусов:
  {(hasError || signingState.status === 'expired') && (
    <TouchableOpacity
      style={styles.retryButton}
      onPress={handleRetry}>
      <Text style={styles.retryButtonText}>Попробовать снова</Text>
    </TouchableOpacity>
  )}
  ```

### 15. Аналитика

- [ ] Добавить tracking событий (опционально):
  ```typescript
  import analytics from '@/services/analytics';

  // В handleSignContract
  analytics.track('signing_initiated', {
    documentId,
    documentType,
    method: 'egov_mobile',
  });

  // При успешном подписании
  analytics.track('signing_completed', {
    documentId,
    documentType,
    sessionId,
  });

  // При ошибке
  analytics.track('signing_error', {
    documentId,
    documentType,
    error: signingState.error,
  });
  ```

### 16. Обновление данных после подписания

- [ ] Обновить данные заказа после подписания:
  ```typescript
  const refreshOrderData = async () => {
    try {
      // Получить обновленные данные заказа
      const {data} = await api.get(`/orders/${orderId}`);

      // Обновить store или state
      // ...
    } catch (error) {
      console.error('Error refreshing order data:', error);
    }
  };

  // Вызвать после успешного подписания
  if (status.status === 'SIGNED') {
    await refreshOrderData();
    // ...
  }
  ```

### 17. Тестирование

- [ ] Написать тесты:
  ```typescript
  // __tests__/SigningOrderDetailsScreen.test.tsx
  import {render, fireEvent, waitFor} from '@testing-library/react-native';
  import SigningOrderDetailsScreen from '../SigningOrderDetailsScreen';

  describe('SigningOrderDetailsScreen', () => {
    it('should render sign button', () => {
      const {getByText} = render(<SigningOrderDetailsScreen />);
      expect(getByText('Подписать договор')).toBeTruthy();
    });

    it('should show loading state when signing', async () => {
      const {getByText, getByTestId} = render(<SigningOrderDetailsScreen />);

      fireEvent.press(getByText('Подписать договор'));

      await waitFor(() => {
        expect(getByText('Создание сессии подписания...')).toBeTruthy();
      });
    });

    // Больше тестов...
  });
  ```

### 18. Документация

- [ ] Добавить комментарии к коду:
  ```typescript
  /**
   * Экран детальной информации о подписании договора
   * Позволяет пользователю подписать договор через eGov Mobile
   *
   * Flow:
   * 1. Пользователь нажимает "Подписать договор"
   * 2. Создается сессия подписания на backend
   * 3. Открывается eGov Mobile через deep link
   * 4. Пользователь подписывает документ в eGov Mobile
   * 5. Приложение проверяет статус подписания (polling)
   * 6. При успешном подписании обновляется UI
   */
  ```

## 📚 Требования

### UX Flow
1. ✅ Кнопка "Подписать" четко видна
2. ✅ Индикатор загрузки показывается во время операции
3. ✅ Статус подписания понятен пользователю
4. ✅ Возможность отменить процесс
5. ✅ Повторная попытка при ошибке
6. ✅ Автоматическое обновление после успешного подписания

### Error Handling
- ✅ Обработка всех возможных ошибок
- ✅ Понятные сообщения об ошибках
- ✅ Возможность retry

### Performance
- ✅ Cleanup polling при размонтировании
- ✅ Не блокировать UI во время операций
- ✅ Оптимизация re-renders

## 🔗 Зависимости

**Зависит от:**
- Mobile Task 1: Deep Linking Config (для возврата из eGov Mobile)
- Mobile Task 2: eGov Sign Service (использование сервиса)
- Backend Task 1: EgovSignController (API endpoints)

**Необходимо для:**
- Полноценная работа подписания в mobile приложении

## ⚠️ Важные замечания

1. **Polling Cleanup**: Обязательно останавливать polling при размонтировании
2. **Deep Link Return**: Обрабатывать возврат из eGov Mobile через useFocusEffect
3. **User Experience**: Пользователь должен понимать что происходит на каждом шаге
4. **Error Recovery**: Всегда давать возможность повторить попытку
5. **Network Errors**: Обрабатывать offline режим

## 📊 Критерии приемки

- [ ] Кнопка "Подписать договор" работает
- [ ] Создание сессии инициируется корректно
- [ ] eGov Mobile открывается автоматически
- [ ] Polling статуса работает
- [ ] UI обновляется при изменении статуса
- [ ] Показываются корректные индикаторы загрузки
- [ ] Обработка успешного подписания работает
- [ ] Обработка ошибок реализована
- [ ] Кнопка отмены работает
- [ ] Retry функционал работает
- [ ] Cleanup при размонтировании
- [ ] Возврат из eGov Mobile обрабатывается
- [ ] UI соответствует дизайну приложения
- [ ] Тесты написаны и проходят

---

**Приоритет:** 🔴 Высокий
**Оценка:** 4-6 часов
**Assignee:** Mobile Developer
**Зависит от:** Mobile Task 1, 2; Backend Task 1
