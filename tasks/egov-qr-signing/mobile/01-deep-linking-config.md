# Mobile Task 1: Конфигурация Deep Linking для Android и iOS

## 📋 Описание

Настроить deep linking для открытия eGov Mobile приложения и обработки возврата после подписания документа.

## 📍 Расположение

- **Android**: `coube-mobile/android/app/src/main/AndroidManifest.xml`
- **iOS**: `coube-mobile/ios/coubemobile/Info.plist`
- **React Native**: `coube-mobile/src/navigation/LinkingConfiguration.ts`

## 🎯 Функциональность

1. **Исходящий deep link**: Открыть eGov Mobile для подписания
   - Android: `https://mgovsign.page.link/?link={encoded_url}&apn=kz.mobile.mgov`
   - iOS: `https://mgovsign.page.link/?link={encoded_url}&isi=1476128386&ibi=kz.egov.mobile`

2. **Входящий deep link**: Принять callback от eGov Mobile после подписания
   - Schema: `coube://` или `coubeapp://`
   - Example: `coube://sign-callback?sessionId={id}&status=success`

## ✅ Чеклист реализации

### 1. Android - Конфигурация AndroidManifest.xml

- [ ] Открыть `android/app/src/main/AndroidManifest.xml`

- [ ] Добавить intent-filter для deep links в главную Activity:
  ```xml
  <activity
    android:name=".MainActivity"
    android:label="@string/app_name"
    android:configChanges="keyboard|keyboardHidden|orientation|screenSize|uiMode"
    android:launchMode="singleTask"
    android:windowSoftInputMode="adjustResize">

    <!-- Existing intent-filter -->
    <intent-filter>
      <action android:name="android.intent.action.MAIN" />
      <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>

    <!-- Deep Linking: Custom scheme -->
    <intent-filter>
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="coube" />
      <data android:scheme="coubeapp" />
    </intent-filter>

    <!-- Deep Linking: HTTPS domain (опционально для production) -->
    <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data
        android:scheme="https"
        android:host="coube.kz"
        android:pathPrefix="/sign-callback" />
    </intent-filter>
  </activity>
  ```

- [ ] Добавить queries для eGov Mobile (Android 11+):
  ```xml
  <queries>
    <!-- eGov Mobile app -->
    <package android:name="kz.mobile.mgov" />

    <!-- Browsers for opening deep links -->
    <intent>
      <action android:name="android.intent.action.VIEW" />
      <data android:scheme="https" />
    </intent>
  </queries>
  ```

### 2. iOS - Конфигурация Info.plist

- [ ] Открыть `ios/coubemobile/Info.plist`

- [ ] Добавить URL Types для custom scheme:
  ```xml
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>kz.coube.mobile</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>coube</string>
        <string>coubeapp</string>
      </array>
    </dict>
  </array>
  ```

- [ ] Добавить LSApplicationQueriesSchemes для eGov Mobile:
  ```xml
  <key>LSApplicationQueriesSchemes</key>
  <array>
    <string>egovmobile</string>
    <string>https</string>
  </array>
  ```

- [ ] Добавить Associated Domains (опционально для Universal Links):
  ```xml
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:coube.kz</string>
  </array>
  ```

### 3. React Native - Конфигурация Linking

- [ ] Создать/обновить `src/navigation/LinkingConfiguration.ts`:
  ```typescript
  import {LinkingOptions} from '@react-navigation/native';
  import * as Linking from 'expo-linking';

  export const linking: LinkingOptions<any> = {
    prefixes: [
      'coube://',
      'coubeapp://',
      'https://coube.kz',
    ],

    config: {
      screens: {
        // Главные screens
        Home: 'home',

        // Callback от eGov Mobile после подписания
        SignCallback: {
          path: 'sign-callback',
          parse: {
            sessionId: (sessionId: string) => sessionId,
            status: (status: string) => status,
          },
        },

        // Другие screens...
      },
    },

    // Обработчик для неизвестных deep links
    async getInitialURL() {
      const url = await Linking.getInitialURL();
      return url;
    },

    subscribe(listener) {
      // Listen to incoming links from deep linking
      const onReceiveURL = ({url}: {url: string}) => {
        listener(url);
      };

      const subscription = Linking.addEventListener('url', onReceiveURL);

      return () => {
        subscription.remove();
      };
    },
  };
  ```

### 4. Применить конфигурацию в Navigation

- [ ] Обновить `src/navigation/index.tsx` или главный навигатор:
  ```typescript
  import {NavigationContainer} from '@react-navigation/native';
  import {linking} from './LinkingConfiguration';

  export function Navigation() {
    return (
      <NavigationContainer linking={linking}>
        {/* Your navigators */}
      </NavigationContainer>
    );
  }
  ```

### 5. Создать экран SignCallback (обработчик возврата)

- [ ] Создать `src/screens/SignCallbackScreen.tsx`:
  ```typescript
  import React, {useEffect} from 'react';
  import {View, Text, ActivityIndicator} from 'react-native';
  import {useNavigation, useRoute} from '@react-navigation/native';
  import {egovSignApi} from '@/api/egovSign';

  export const SignCallbackScreen = () => {
    const navigation = useNavigation();
    const route = useRoute();

    // Получить параметры из deep link
    const {sessionId, status} = route.params as {
      sessionId?: string;
      status?: string;
    };

    useEffect(() => {
      handleSignCallback();
    }, []);

    const handleSignCallback = async () => {
      try {
        if (!sessionId) {
          console.error('No sessionId in callback');
          navigation.goBack();
          return;
        }

        // Проверить статус сессии на сервере
        const response = await egovSignApi.getSessionStatus(sessionId);

        if (response.data.status === 'SIGNED') {
          // Успешное подписание
          // TODO: Показать success screen или вернуться к документу
          navigation.navigate('SigningSuccess', {
            documentId: response.data.documentId,
            documentType: response.data.documentType,
          });
        } else {
          // Ошибка или другой статус
          navigation.navigate('SigningError', {
            error: 'Подписание не завершено',
          });
        }
      } catch (error) {
        console.error('Error handling sign callback:', error);
        navigation.goBack();
      }
    };

    return (
      <View style={{flex: 1, justifyContent: 'center', alignItems: 'center'}}>
        <ActivityIndicator size="large" />
        <Text>Обработка подписания...</Text>
      </View>
    );
  };
  ```

### 6. Тестирование Deep Links

- [ ] **Android**:
  ```bash
  # Тест custom scheme
  adb shell am start -W -a android.intent.action.VIEW \
    -d "coube://sign-callback?sessionId=test123&status=success" \
    kz.coube.mobile

  # Тест HTTPS
  adb shell am start -W -a android.intent.action.VIEW \
    -d "https://coube.kz/sign-callback?sessionId=test123" \
    kz.coube.mobile
  ```

- [ ] **iOS**:
  ```bash
  xcrun simctl openurl booted "coube://sign-callback?sessionId=test123&status=success"
  ```

- [ ] **React Native Debugger**:
  ```javascript
  // В консоли
  Linking.openURL('coube://sign-callback?sessionId=test123&status=success');
  ```

### 7. Обработка ошибок

- [ ] Обработать случай когда eGov Mobile не установлен:
  ```typescript
  import {Linking, Alert} from 'react-native';

  const openEgovMobile = async (deepLink: string) => {
    const canOpen = await Linking.canOpenURL(deepLink);

    if (!canOpen) {
      Alert.alert(
        'eGov Mobile не установлен',
        'Для подписания документов установите приложение eGov Mobile',
        [
          {text: 'Отмена', style: 'cancel'},
          {
            text: 'Установить',
            onPress: () => {
              const storeUrl = Platform.OS === 'ios'
                ? 'https://apps.apple.com/kz/app/egov-mobile/id1476128386'
                : 'https://play.google.com/store/apps/details?id=kz.mobile.mgov';
              Linking.openURL(storeUrl);
            }
          }
        ]
      );
      return;
    }

    await Linking.openURL(deepLink);
  };
  ```

### 8. Добавить в React Native Router

- [ ] Зарегистрировать SignCallbackScreen в навигаторе:
  ```typescript
  <Stack.Screen
    name="SignCallback"
    component={SignCallbackScreen}
    options={{
      headerShown: false,
      presentation: 'transparentModal',
    }}
  />
  ```

### 9. Логирование

- [ ] Добавить логирование deep link событий:
  ```typescript
  Linking.addEventListener('url', (event) => {
    console.log('Received deep link:', event.url);
    // Можно отправить в analytics
  });
  ```

### 10. Документация

- [ ] Создать README для deep linking:
  - Форматы поддерживаемых ссылок
  - Примеры использования
  - Troubleshooting

## 📚 Требования из документации eGov Mobile

### Формат Dynamic Link (согласно документации):

**Android:**
```
https://mgovsign.page.link/?link={URL_ENCODED_API_1}&apn=kz.mobile.mgov
```

**iOS:**
```
https://mgovsign.page.link/?link={URL_ENCODED_API_1}&isi=1476128386&ibi=kz.egov.mobile
```

**Компоненты:**
- `https://mgovsign.page.link` - фиксированный URL префикс
- `?link={API_URL}` - URL-encoded API №1
- `&apn=kz.mobile.mgov` - Android package name
- `&isi=1476128386` - iOS App Store ID
- `&ibi=kz.egov.mobile` - iOS Bundle ID

### URL Encoding
❗ **ВАЖНО**: Необходимо кодировать параметры API URL:
- `&` → `%26`
- `=` → `%3D`
- `?` → `%3F`

## 🔗 Зависимости

**Библиотеки:**
- `@react-navigation/native` (уже установлена)
- `react-native-linking` (встроенная)

**Зависит от:**
- Настроенная навигация React Navigation

**Необходимо для:**
- Mobile Task 2: eGov Sign Service (использование deep links)
- Mobile Task 3: Signing Screen Update

## ⚠️ Важные замечания

1. **Android 12+**: Требуется `android:exported="true"` для MainActivity
2. **iOS 14+**: Требуется LSApplicationQueriesSchemes для canOpenURL
3. **URL Encoding**: Обязательно кодировать параметры в dynamic link
4. **Testing**: Тестировать на реальных устройствах, не только симуляторах

## 📊 Критерии приемки

- [ ] AndroidManifest.xml настроен с intent-filters
- [ ] Info.plist настроен с URL schemes
- [ ] LinkingConfiguration создан и применен
- [ ] SignCallbackScreen создан и зарегистрирован
- [ ] Deep links работают на Android
- [ ] Deep links работают на iOS
- [ ] Обработка возврата от eGov Mobile работает
- [ ] Обработка случая "приложение не установлено"
- [ ] Тесты проходят на физических устройствах

---

**Приоритет:** 🔴 Высокий (блокирует другие mobile задачи)
**Оценка:** 3-4 часа
**Assignee:** Mobile Developer
**Должно быть выполнено первым в мобильном**
