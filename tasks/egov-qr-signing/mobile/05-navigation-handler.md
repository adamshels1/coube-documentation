# Mobile Task 5: Navigation Handler для post-signing

## 📋 Описание

Обработать возврат из eGov Mobile после подписания и реализовать навигацию пользователя на правильный экран в зависимости от результата подписания.

## 📍 Расположение

**Файлы:**
- `coube-mobile/src/navigation/LinkingConfiguration.ts` (обновить)
- `coube-mobile/src/screens/SignCallbackScreen.tsx` (создать/обновить)
- `coube-mobile/src/navigation/types.ts` (обновить)

## 🎯 Функциональность

1. Обработка deep link от eGov Mobile: `coube://sign-callback?sessionId={id}&status={status}`
2. Проверка статуса подписания на backend
3. Навигация на соответствующий экран:
   - **Успешное подписание** → SigningSuccess screen
   - **Ошибка** → SigningError screen
   - **Expired** → Возврат на предыдущий экран
4. Обновление данных в приложении
5. Показ уведомлений пользователю

## ✅ Чеклист реализации

### 1. Обновить типы навигации

- [ ] Обновить `src/navigation/types.ts`:
  ```typescript
  export type RootStackParamList = {
    // ... существующие screens
    Home: undefined;
    SigningOrderDetails: {
      orderId: string;
      documentId: string;
      documentType: string;
    };

    // Новые screens для подписания
    SignCallback: {
      sessionId?: string;
      status?: string;
    };
    SigningSuccess: {
      documentId: string;
      documentType: string;
      orderId?: string;
    };
    SigningError: {
      error: string;
      sessionId?: string;
    };
  };
  ```

### 2. Обновить Linking Configuration

- [ ] Обновить `src/navigation/LinkingConfiguration.ts`:
  ```typescript
  import {LinkingOptions} from '@react-navigation/native';
  import * as Linking from 'expo-linking';
  import {RootStackParamList} from './types';

  export const linking: LinkingOptions<RootStackParamList> = {
    prefixes: [
      'coube://',
      'coubeapp://',
      'https://coube.kz',
    ],

    config: {
      screens: {
        Home: 'home',
        SigningOrderDetails: {
          path: 'orders/:orderId/sign',
          parse: {
            orderId: (orderId: string) => orderId,
          },
        },

        // Callback от eGov Mobile
        SignCallback: {
          path: 'sign-callback',
          parse: {
            sessionId: (sessionId: string) => sessionId,
            status: (status: string) => status,
          },
        },

        // Success экран
        SigningSuccess: {
          path: 'signing/success',
          parse: {
            documentId: (documentId: string) => documentId,
            documentType: (documentType: string) => documentType,
          },
        },

        // Error экран
        SigningError: {
          path: 'signing/error',
          parse: {
            error: (error: string) => decodeURIComponent(error),
          },
        },
      },
    },

    async getInitialURL() {
      // Проверить deep link при запуске приложения
      const url = await Linking.getInitialURL();
      console.log('Initial URL:', url);
      return url;
    },

    subscribe(listener) {
      // Слушать входящие deep links
      const onReceiveURL = ({url}: {url: string}) => {
        console.log('Received deep link:', url);
        listener(url);
      };

      const subscription = Linking.addEventListener('url', onReceiveURL);

      return () => {
        subscription.remove();
      };
    },
  };
  ```

### 3. Создать SignCallbackScreen

- [ ] Создать `src/screens/SignCallbackScreen.tsx`:
  ```typescript
  import React, {useEffect, useState} from 'react';
  import {View, Text, ActivityIndicator, StyleSheet} from 'react-native';
  import {useNavigation, useRoute, RouteProp} from '@react-navigation/native';
  import {StackNavigationProp} from '@react-navigation/stack';
  import {RootStackParamList} from '@/navigation/types';
  import egovSignApi from '@/api/egovSign';

  type SignCallbackRouteProp = RouteProp<RootStackParamList, 'SignCallback'>;
  type SignCallbackNavigationProp = StackNavigationProp<
    RootStackParamList,
    'SignCallback'
  >;

  export const SignCallbackScreen = () => {
    const navigation = useNavigation<SignCallbackNavigationProp>();
    const route = useRoute<SignCallbackRouteProp>();

    const [isProcessing, setIsProcessing] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const {sessionId, status} = route.params || {};

    useEffect(() => {
      handleCallback();
    }, []);

    const handleCallback = async () => {
      try {
        console.log('Processing sign callback:', {sessionId, status});

        // Валидация параметров
        if (!sessionId) {
          console.error('No sessionId in callback');
          navigation.replace('SigningError', {
            error: 'Отсутствует идентификатор сессии',
          });
          return;
        }

        // Получить полную информацию о сессии с сервера
        const sessionInfo = await egovSignApi.getSessionInfo(sessionId);

        console.log('Session info:', sessionInfo);

        // Обработать статус
        switch (sessionInfo.status) {
          case 'SIGNED':
            // Успешное подписание
            console.log('Document signed successfully');
            navigation.replace('SigningSuccess', {
              documentId: sessionInfo.documentId,
              documentType: sessionInfo.documentType,
            });
            break;

          case 'PENDING':
            // Еще в процессе (пользователь вернулся слишком рано)
            console.log('Signing still in progress');
            navigation.replace('SigningError', {
              error: 'Подписание еще не завершено. Пожалуйста, завершите подписание в eGov Mobile.',
              sessionId,
            });
            break;

          case 'EXPIRED':
            // Истек срок
            console.log('Session expired');
            navigation.replace('SigningError', {
              error: 'Истек срок действия сессии подписания',
            });
            break;

          case 'ERROR':
            // Ошибка
            console.error('Signing error:', sessionInfo.error);
            navigation.replace('SigningError', {
              error: sessionInfo.error || 'Произошла ошибка при подписании',
            });
            break;

          default:
            console.error('Unknown session status:', sessionInfo.status);
            navigation.replace('SigningError', {
              error: 'Неизвестный статус подписания',
            });
        }
      } catch (error) {
        console.error('Error handling sign callback:', error);
        setError('Не удалось обработать результат подписания');

        // Показать экран ошибки
        setTimeout(() => {
          navigation.replace('SigningError', {
            error: 'Не удалось проверить статус подписания',
          });
        }, 2000);
      } finally {
        setIsProcessing(false);
      }
    };

    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#0066CC" />
        <Text style={styles.text}>
          {error || 'Обработка результата подписания...'}
        </Text>
      </View>
    );
  };

  const styles = StyleSheet.create({
    container: {
      flex: 1,
      justifyContent: 'center',
      alignItems: 'center',
      backgroundColor: '#fff',
      padding: 20,
    },
    text: {
      marginTop: 16,
      fontSize: 16,
      color: '#333',
      textAlign: 'center',
    },
  });
  ```

### 4. Создать SigningSuccessScreen

- [ ] Создать `src/screens/SigningSuccessScreen.tsx`:
  ```typescript
  import React, {useEffect} from 'react';
  import {View, Text, StyleSheet, TouchableOpacity} from 'react-native';
  import {useNavigation, useRoute, RouteProp} from '@react-navigation/native';
  import {StackNavigationProp} from '@react-navigation/stack';
  import {RootStackParamList} from '@/navigation/types';

  type SigningSuccessRouteProp = RouteProp<RootStackParamList, 'SigningSuccess'>;
  type SigningSuccessNavigationProp = StackNavigationProp<
    RootStackParamList,
    'SigningSuccess'
  >;

  export const SigningSuccessScreen = () => {
    const navigation = useNavigation<SigningSuccessNavigationProp>();
    const route = useRoute<SigningSuccessRouteProp>();

    const {documentId, documentType, orderId} = route.params;

    useEffect(() => {
      // Можно отправить событие в analytics
      console.log('Signing success:', {documentId, documentType});
    }, []);

    const handleContinue = () => {
      // Вернуться к списку заказов или на главную
      navigation.reset({
        index: 0,
        routes: [{name: 'Home'}],
      });
    };

    const handleViewDocument = () => {
      // Перейти к просмотру документа (если есть такой экран)
      navigation.navigate('DocumentDetails', {
        documentId,
        documentType,
      } as any);
    };

    return (
      <View style={styles.container}>
        <View style={styles.iconContainer}>
          <Text style={styles.icon}>✅</Text>
        </View>

        <Text style={styles.title}>Документ успешно подписан</Text>

        <Text style={styles.description}>
          Ваш документ был успешно подписан через eGov Mobile
        </Text>

        <View style={styles.infoContainer}>
          <InfoRow label="Тип документа" value={getDocumentTypeName(documentType)} />
          <InfoRow label="ID документа" value={documentId} />
        </View>

        <TouchableOpacity
          style={styles.primaryButton}
          onPress={handleContinue}>
          <Text style={styles.primaryButtonText}>Вернуться на главную</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.secondaryButton}
          onPress={handleViewDocument}>
          <Text style={styles.secondaryButtonText}>Просмотреть документ</Text>
        </TouchableOpacity>
      </View>
    );
  };

  const InfoRow = ({label, value}: {label: string; value: string}) => (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}:</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );

  const getDocumentTypeName = (type: string): string => {
    const types: Record<string, string> = {
      agreement: 'Договор',
      invoice: 'Счет-фактура',
      act: 'Акт',
      registry: 'Реестр',
    };
    return types[type] || type;
  };

  const styles = StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: '#fff',
      padding: 24,
      justifyContent: 'center',
    },
    iconContainer: {
      alignItems: 'center',
      marginBottom: 24,
    },
    icon: {
      fontSize: 80,
    },
    title: {
      fontSize: 24,
      fontWeight: 'bold',
      color: '#28A745',
      textAlign: 'center',
      marginBottom: 12,
    },
    description: {
      fontSize: 16,
      color: '#666',
      textAlign: 'center',
      marginBottom: 32,
    },
    infoContainer: {
      backgroundColor: '#F8F9FA',
      borderRadius: 8,
      padding: 16,
      marginBottom: 32,
    },
    infoRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      paddingVertical: 8,
    },
    infoLabel: {
      fontSize: 14,
      color: '#666',
    },
    infoValue: {
      fontSize: 14,
      fontWeight: '600',
      color: '#333',
    },
    primaryButton: {
      backgroundColor: '#0066CC',
      paddingVertical: 14,
      borderRadius: 8,
      alignItems: 'center',
      marginBottom: 12,
    },
    primaryButtonText: {
      color: '#fff',
      fontSize: 16,
      fontWeight: '600',
    },
    secondaryButton: {
      backgroundColor: '#fff',
      borderWidth: 1,
      borderColor: '#0066CC',
      paddingVertical: 14,
      borderRadius: 8,
      alignItems: 'center',
    },
    secondaryButtonText: {
      color: '#0066CC',
      fontSize: 16,
      fontWeight: '600',
    },
  });
  ```

### 5. Создать SigningErrorScreen

- [ ] Создать `src/screens/SigningErrorScreen.tsx`:
  ```typescript
  import React from 'react';
  import {View, Text, StyleSheet, TouchableOpacity} from 'react-native';
  import {useNavigation, useRoute, RouteProp} from '@react-navigation/native';
  import {StackNavigationProp} from '@react-navigation/stack';
  import {RootStackParamList} from '@/navigation/types';

  type SigningErrorRouteProp = RouteProp<RootStackParamList, 'SigningError'>;
  type SigningErrorNavigationProp = StackNavigationProp<
    RootStackParamList,
    'SigningError'
  >;

  export const SigningErrorScreen = () => {
    const navigation = useNavigation<SigningErrorNavigationProp>();
    const route = useRoute<SigningErrorRouteProp>();

    const {error, sessionId} = route.params;

    const handleRetry = () => {
      // Вернуться на экран подписания для повторной попытки
      navigation.goBack();
    };

    const handleGoHome = () => {
      navigation.reset({
        index: 0,
        routes: [{name: 'Home'}],
      });
    };

    return (
      <View style={styles.container}>
        <View style={styles.iconContainer}>
          <Text style={styles.icon}>❌</Text>
        </View>

        <Text style={styles.title}>Ошибка подписания</Text>

        <Text style={styles.errorMessage}>{error}</Text>

        {sessionId && (
          <Text style={styles.sessionId}>ID сессии: {sessionId}</Text>
        )}

        <TouchableOpacity style={styles.retryButton} onPress={handleRetry}>
          <Text style={styles.retryButtonText}>Попробовать снова</Text>
        </TouchableOpacity>

        <TouchableOpacity style={styles.homeButton} onPress={handleGoHome}>
          <Text style={styles.homeButtonText}>Вернуться на главную</Text>
        </TouchableOpacity>
      </View>
    );
  };

  const styles = StyleSheet.create({
    container: {
      flex: 1,
      backgroundColor: '#fff',
      padding: 24,
      justifyContent: 'center',
    },
    iconContainer: {
      alignItems: 'center',
      marginBottom: 24,
    },
    icon: {
      fontSize: 80,
    },
    title: {
      fontSize: 24,
      fontWeight: 'bold',
      color: '#DC3545',
      textAlign: 'center',
      marginBottom: 12,
    },
    errorMessage: {
      fontSize: 16,
      color: '#666',
      textAlign: 'center',
      marginBottom: 16,
    },
    sessionId: {
      fontSize: 12,
      color: '#999',
      textAlign: 'center',
      marginBottom: 32,
    },
    retryButton: {
      backgroundColor: '#0066CC',
      paddingVertical: 14,
      borderRadius: 8,
      alignItems: 'center',
      marginBottom: 12,
    },
    retryButtonText: {
      color: '#fff',
      fontSize: 16,
      fontWeight: '600',
    },
    homeButton: {
      backgroundColor: '#fff',
      borderWidth: 1,
      borderColor: '#999',
      paddingVertical: 14,
      borderRadius: 8,
      alignItems: 'center',
    },
    homeButtonText: {
      color: '#666',
      fontSize: 16,
      fontWeight: '600',
    },
  });
  ```

### 6. Зарегистрировать screens в навигаторе

- [ ] Обновить `src/navigation/index.tsx`:
  ```typescript
  import {createStackNavigator} from '@react-navigation/stack';
  import {NavigationContainer} from '@react-navigation/native';
  import {linking} from './LinkingConfiguration';
  import {RootStackParamList} from './types';

  // Импорты screens
  import {SignCallbackScreen} from '@/screens/SignCallbackScreen';
  import {SigningSuccessScreen} from '@/screens/SigningSuccessScreen';
  import {SigningErrorScreen} from '@/screens/SigningErrorScreen';

  const Stack = createStackNavigator<RootStackParamList>();

  export function Navigation() {
    return (
      <NavigationContainer linking={linking}>
        <Stack.Navigator>
          {/* Существующие screens */}
          <Stack.Screen name="Home" component={HomeScreen} />

          {/* Подписание screens */}
          <Stack.Screen
            name="SignCallback"
            component={SignCallbackScreen}
            options={{
              headerShown: false,
              presentation: 'transparentModal',
            }}
          />

          <Stack.Screen
            name="SigningSuccess"
            component={SigningSuccessScreen}
            options={{
              headerShown: false,
              gestureEnabled: false,
            }}
          />

          <Stack.Screen
            name="SigningError"
            component={SigningErrorScreen}
            options={{
              headerShown: false,
              gestureEnabled: false,
            }}
          />
        </Stack.Navigator>
      </NavigationContainer>
    );
  }
  ```

### 7. Добавить уведомления

- [ ] Интегрировать с системой уведомлений:
  ```typescript
  // src/services/notifications.ts
  import {Alert} from 'react-native';
  // или import PushNotification from 'react-native-push-notification';

  export const showSigningSuccessNotification = (documentType: string) => {
    Alert.alert(
      'Успешно подписано',
      `Ваш ${getDocumentTypeName(documentType)} был успешно подписан`,
    );

    // Или push notification если приложение в фоне
    // PushNotification.localNotification({
    //   title: 'Успешно подписано',
    //   message: `Ваш ${getDocumentTypeName(documentType)} был успешно подписан`,
    // });
  };
  ```

### 8. Обновление данных после подписания

- [ ] Интегрировать с store/cache:
  ```typescript
  // В SignCallbackScreen
  import {useDispatch} from 'react-redux';
  import {refreshDocuments} from '@/store/documentsSlice';

  const dispatch = useDispatch();

  const handleCallback = async () => {
    // ...
    if (sessionInfo.status === 'SIGNED') {
      // Обновить данные в store
      dispatch(refreshDocuments());

      // Или invalidate cache если используете React Query
      // queryClient.invalidateQueries(['documents']);

      navigation.replace('SigningSuccess', {...});
    }
  };
  ```

### 9. Аналитика

- [ ] Добавить tracking событий:
  ```typescript
  import analytics from '@/services/analytics';

  // В SignCallbackScreen
  const handleCallback = async () => {
    const sessionInfo = await egovSignApi.getSessionInfo(sessionId);

    // Track событие
    analytics.track('signing_callback_received', {
      sessionId,
      status: sessionInfo.status,
      documentType: sessionInfo.documentType,
    });

    if (sessionInfo.status === 'SIGNED') {
      analytics.track('signing_success', {
        sessionId,
        documentId: sessionInfo.documentId,
        documentType: sessionInfo.documentType,
      });
    } else if (sessionInfo.status === 'ERROR') {
      analytics.track('signing_error', {
        sessionId,
        error: sessionInfo.error,
      });
    }
  };
  ```

### 10. Обработка edge cases

- [ ] Обработать различные сценарии:
  ```typescript
  // Пользователь вернулся в приложение без завершения подписания
  if (sessionInfo.status === 'PENDING') {
    Alert.alert(
      'Подписание не завершено',
      'Вы не завершили подписание в eGov Mobile. Хотите вернуться?',
      [
        {text: 'Отмена', style: 'cancel', onPress: () => navigation.goBack()},
        {
          text: 'Открыть eGov Mobile',
          onPress: async () => {
            // Повторно открыть eGov Mobile
            const apiUrl = await getApiUrlFromSession(sessionId);
            await Linking.openURL(apiUrl);
          },
        },
      ],
    );
  }
  ```

### 11. Тестирование deep links

- [ ] Протестировать все сценарии:
  ```bash
  # Success
  npx uri-scheme open "coube://sign-callback?sessionId=123&status=success" --ios

  # Error
  npx uri-scheme open "coube://sign-callback?sessionId=123&status=error" --android

  # Без параметров
  npx uri-scheme open "coube://sign-callback" --ios
  ```

### 12. Документация

- [ ] Создать README для navigation:
  ```markdown
  # Navigation для eGov Подписания

  ## Deep Links

  - `coube://sign-callback` - Callback от eGov Mobile

  ## Screens

  - **SignCallbackScreen** - Обработка callback
  - **SigningSuccessScreen** - Успешное подписание
  - **SigningErrorScreen** - Ошибка подписания

  ## Flow

  1. User signs in eGov Mobile
  2. eGov Mobile redirects to `coube://sign-callback?sessionId=XXX`
  3. App opens SignCallbackScreen
  4. Check session status on backend
  5. Navigate to Success or Error screen
  ```

## 📚 Требования

### UX Flow
- ✅ Плавная навигация между экранами
- ✅ Понятные сообщения пользователю
- ✅ Невозможность вернуться назад с Success/Error экранов (gestureEnabled: false)
- ✅ Автоматическое обновление данных

### Error Handling
- ✅ Обработка отсутствия sessionId
- ✅ Обработка некорректного статуса
- ✅ Обработка ошибок сети
- ✅ Retry функциональность

### Analytics
- ✅ Tracking всех событий подписания
- ✅ Логирование ошибок

## 🔗 Зависимости

**Зависит от:**
- Mobile Task 1: Deep Linking Config (конфигурация deep links)
- Mobile Task 4: API Client (проверка статуса сессии)
- Backend Task 1: EgovSignController (API endpoints)

**Необходимо для:**
- Завершение mobile flow подписания

## ⚠️ Важные замечания

1. **Navigation Reset**: Использовать `navigation.reset()` для Success/Error экранов
2. **Presentation Mode**: SignCallbackScreen должен быть modal или transparentModal
3. **Gesture Disable**: Отключить swipe back на Success/Error экранах
4. **Data Refresh**: Обновлять данные после успешного подписания
5. **Deep Link Validation**: Всегда проверять наличие required параметров

## 📊 Критерии приемки

- [ ] Типы навигации обновлены
- [ ] LinkingConfiguration настроен для sign-callback
- [ ] SignCallbackScreen создан и обрабатывает callback
- [ ] SigningSuccessScreen создан и показывает success
- [ ] SigningErrorScreen создан и показывает ошибки
- [ ] Все screens зарегистрированы в навигаторе
- [ ] Deep links работают на Android и iOS
- [ ] Навигация корректная для всех статусов
- [ ] Данные обновляются после подписания
- [ ] Analytics события отправляются
- [ ] Обработка edge cases реализована
- [ ] Тесты написаны и проходят
- [ ] Документация создана

---

**Приоритет:** 🔴 Высокий (завершает mobile flow)
**Оценка:** 3-4 часа
**Assignee:** Mobile Developer
**Зависит от:** Mobile Task 1, 4; Backend Task 1
