# Подключение факторинга (Быстрая оплата) в мобильном приложении

## Описание

Реализация подключения факторинга для перевозчиков (роль EXECUTOR) в мобильном приложении.
Аналог кнопки «Подключить» в разделе «Моя компания» на веб-фронтенде (`OrganizationContainer.vue`).

**Главное правило:** если перевозчик уже подключил факторинг — кнопку не показывать.

---

## Пользовательский сценарий

```
MyCompanyScreen
  └── Блок «Быстрая оплата»
        ├── [не подключён]     → кнопка «Подключить»
        ├── [pending]          → «В процессе подтверждения»
        ├── [approved]         → кнопка «Подписать заявку»
        └── [active / signed]  → «Быстрая оплата доступна»

Нажатие «Подключить» / «Подписать заявку»:
  1. Проверить KBe, KNP, банковские реквизиты
  2. POST /v1/factoring/executor/initiate
  3. GET  /v1/factoring/executor/contract/base64  → PDF + agreementId
  4. Открыть FactoringOnboardingScreen (просмотр PDF)
  5. Нажать «Подписать» → signWithEgovMobile(agreementId, 'factoring-agreement')
  6. Polling статуса → при SIGNED показать успех → goBack()
```

---

## Статусы MOST онбординга

| Статус | Что показывать |
|--------|----------------|
| `not_registered` | Кнопка «Подключить» |
| `pending` | «В процессе подтверждения» (без кнопки) |
| `approved` | Кнопка «Подписать заявку» |
| `active` | «Быстрая оплата доступна» |

Дополнительно: если `isFactoringContractSigned = true` — тоже показывать «Доступна» (независимо от статуса).

---

## Затрагиваемые файлы

| Файл | Изменение |
|------|-----------|
| `src/api/index.ts` | Добавить 5 API функций |
| `src/api/types.ts` | Добавить типы |
| `src/types/egovSign.ts` | Добавить `'factoring-agreement'` в `DocumentType` |
| `src/screens/MyCompanyScreen.tsx` | Добавить блок «Быстрая оплата» |
| `src/screens/FactoringOnboardingScreen.tsx` | Создать новый экран |
| `src/navigation/stacks/RootStack.tsx` | Зарегистрировать экран |
| `src/navigation/types.ts` | Добавить тип параметров маршрута |
| `src/translations/ru-RU.json` | Переводы |
| `src/translations/en-US.json` | Переводы |

---

## 1. API (`src/api/index.ts` + `src/api/types.ts`)

### Новые типы

```typescript
// src/api/types.ts
export type MostOnboardingStatus = 'not_registered' | 'pending' | 'approved' | 'active';

export interface MostOnboardingStatusResponse {
  status: MostOnboardingStatus;
}

export interface FactoringContractBase64Response {
  originalFileBase64: string; // base64 PDF договора
  agreementId: number;        // ID для eGov подписания (уточнить у бэка: number или string)
}
```

### Новые API функции

```typescript
// src/api/index.ts

/** Инициировать подключение факторинга */
export const initiateFactoring = () =>
  api.post<void>('/api/v1/factoring/executor/initiate').then(res => res.data);

/** Получить договор в base64 */
export const getFactoringContractBase64 = () =>
  api.get<FactoringContractBase64Response>('/api/v1/factoring/executor/contract/base64')
    .then(res => res.data);

/** Проверить, подписан ли договор */
export const checkFactoringContractSigned = () =>
  api.get<boolean>('/api/v1/factoring/executor/signed').then(res => res.data);

/** Получить статус MOST онбординга */
export const getFactoringMostStatus = () =>
  api.get<MostOnboardingStatusResponse>('/api/v1/factoring/executor/most-status')
    .then(res => res.data);

/** Зарегистрироваться в MOST */
export const registerInMost = () =>
  api.post<void>('/api/v1/factoring/executor/register-most').then(res => res.data);
```

> Эндпоинты для выплат (`claimFactoringPayout`, `sendFactoringPayoutOtp`, etc.) не трогать — они уже есть.

---

## 2. Тип документа для eGov (`src/types/egovSign.ts`)

```typescript
// Добавить 'factoring-agreement' в union
export type DocumentType = 'agreement' | 'invoice' | 'act' | 'registry' | 'factoring-agreement';
```

---

## 3. Блок факторинга в `MyCompanyScreen.tsx`

### Загрузка состояния

```typescript
const [mostStatus, setMostStatus] = useState<MostOnboardingStatus | null>(null);
const [isContractSigned, setIsContractSigned] = useState(false);
const [factoringLoading, setFactoringLoading] = useState(false);

// Загружать при каждом фокусе экрана (чтобы обновлять после возврата с FactoringOnboardingScreen)
useFocusEffect(
  useCallback(() => {
    if (isExecutor) {
      Promise.all([getFactoringMostStatus(), checkFactoringContractSigned()])
        .then(([statusRes, signed]) => {
          setMostStatus(statusRes.status);
          setIsContractSigned(signed);
        })
        .catch(() => {}); // не блокировать UI
    }
  }, [isExecutor]),
);
```

### Условия видимости

```typescript
const showConnectButton = isExecutor && !isContractSigned && mostStatus === 'not_registered';
const showSignButton    = isExecutor && !isContractSigned && mostStatus === 'approved';
const showPending       = isExecutor && mostStatus === 'pending';
const showActive        = isExecutor && (isContractSigned || mostStatus === 'active');
```

### Обработчик нажатия (валидация + запуск флоу)

```typescript
const handleConnectFactoring = async () => {
  // Валидация KBe
  if (!profile?.beneficiaryCode?.trim()) {
    Toast.show({ text1: 'Заполните поле KBe для подключения быстрой оплаты' });
    return;
  }
  // Валидация KNP
  if (!profile?.paymentPurposeCode?.trim()) {
    Toast.show({ text1: 'Заполните поле KNP для подключения быстрой оплаты' });
    return;
  }
  // Валидация банковских реквизитов
  if (!bankRequisites?.length) {
    Toast.show({ text1: 'Добавьте банковские реквизиты' });
    navigation.navigate('bank-details');
    return;
  }
  if (!bankRequisites.some(r => r.isMain)) {
    Toast.show({ text1: 'Установите основные банковские реквизиты' });
    navigation.navigate('bank-details');
    return;
  }

  setFactoringLoading(true);
  try {
    await initiateFactoring();
    const contract = await getFactoringContractBase64();
    navigation.navigate('factoring-onboarding', {
      agreementId: contract.agreementId,
      pdfBase64: contract.originalFileBase64,
    });
  } catch {
    Toast.show({ text1: 'Ошибка при подключении. Проверьте реквизиты.' });
  } finally {
    setFactoringLoading(false);
  }
};
```

### UI блока

```tsx
{isExecutor && (
  <View style={styles.factoringSection}>
    <Text style={styles.sectionTitle}>Быстрая оплата</Text>

    {showActive && (
      <View style={styles.statusRow}>
        {/* иконка галочки */}
        <Text style={styles.statusActiveText}>Быстрая оплата доступна</Text>
      </View>
    )}

    {showPending && (
      <View style={styles.statusRow}>
        {/* иконка часов */}
        <Text style={styles.statusPendingText}>В процессе подтверждения</Text>
      </View>
    )}

    {(showConnectButton || showSignButton) && (
      <>
        <Text style={styles.factoringDescription}>
          {showSignButton
            ? 'Заявка одобрена. Подпишите договор для активации.'
            : 'Получайте деньги за перевозки досрочно'}
        </Text>
        <TouchableOpacity
          style={styles.connectButton}
          onPress={handleConnectFactoring}
          disabled={factoringLoading}>
          {factoringLoading
            ? <ActivityIndicator color="#fff" />
            : <Text style={styles.connectButtonText}>
                {showSignButton ? 'Подписать заявку' : 'Подключить'}
              </Text>
          }
        </TouchableOpacity>
      </>
    )}
  </View>
)}
```

---

## 4. Новый экран `FactoringOnboardingScreen.tsx`

**Паттерн:** повторяет `EgovSignTestScreen.tsx` (уже есть в проекте) — использовать его как основу.

```typescript
// Параметры маршрута
interface Params {
  agreementId: number;  // ID для eGov сессии
  pdfBase64: string;    // base64 PDF для отображения
}
```

### Логика экрана

```typescript
import egovSignService from '@src/services/egovSignService';
import type {SigningState} from '@src/types/egovSign';

const FactoringOnboardingScreen = ({route, navigation}) => {
  const {agreementId, pdfBase64} = route.params;

  const [signingState, setSigningState] = useState<SigningState>({
    status: 'idle',
    sessionId: null,
    error: null,
  });
  const stopPollingRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    return () => { stopPollingRef.current?.(); };
  }, []);

  const handleSign = async () => {
    setSigningState({status: 'creating_session', sessionId: null, error: null});

    // Открывает eGov Mobile через deep link (как в EgovSignTestScreen)
    const sessionId = await egovSignService.signWithEgovMobile(
      agreementId,
      'factoring-agreement',
    );

    if (!sessionId) {
      setSigningState({status: 'idle', sessionId: null, error: null});
      return;
    }

    setSigningState({status: 'waiting_signature', sessionId, error: null});

    const stopPolling = egovSignService.startStatusPolling(sessionId, status => {
      if (status.status === 'SIGNED') {
        stopPollingRef.current?.();
        setSigningState({status: 'signed', sessionId, error: null});
      } else if (status.status === 'ERROR' || status.status === 'EXPIRED') {
        stopPollingRef.current?.();
        setSigningState({
          status: status.status === 'EXPIRED' ? 'expired' : 'error',
          sessionId,
          error: status.error || 'Ошибка подписания',
        });
      }
    });
    stopPollingRef.current = stopPolling;
  };

  const handleCancel = () => {
    stopPollingRef.current?.();
    setSigningState({status: 'idle', sessionId: null, error: null});
  };
};
```

### UI экрана

**`idle` — просмотр PDF + кнопка:**
```tsx
<>
  {/* PDF через WebView с base64 */}
  <WebView
    style={{flex: 1}}
    source={{html: `<html><body style="margin:0">
      <iframe src="data:application/pdf;base64,${pdfBase64}"
        width="100%" height="100%" style="border:none"/>
    </body></html>`}}
    originWhitelist={['*']}
  />
  <View style={styles.footer}>
    <TouchableOpacity onPress={() => Linking.openURL('https://mfomost.kz/coube_offer')}>
      <Text style={styles.linkText}>Ознакомиться с офертой MOST</Text>
    </TouchableOpacity>
    <TouchableOpacity style={styles.primaryButton} onPress={handleSign}>
      <Text style={styles.primaryButtonText}>Подписать через eGov Mobile</Text>
    </TouchableOpacity>
  </View>
</>
```

**`creating_session` / `waiting_signature` — ожидание:**
```tsx
<View style={styles.center}>
  <ActivityIndicator size="large" color="#0066CC" />
  <Text style={styles.statusText}>
    {signingState.status === 'creating_session'
      ? 'Создание сессии...'
      : 'Ожидаем подписания в eGov Mobile...'}
  </Text>
  <TouchableOpacity style={styles.cancelButton} onPress={handleCancel}>
    <Text>Отменить</Text>
  </TouchableOpacity>
</View>
```

**`signed` — успех:**
```tsx
<View style={styles.center}>
  <Text style={styles.successIcon}>✅</Text>
  <Text style={styles.successTitle}>Заявка подписана!</Text>
  <Text style={styles.successText}>Ожидайте рассмотрения заявки</Text>
  <TouchableOpacity style={styles.primaryButton} onPress={() => navigation.goBack()}>
    <Text>Вернуться</Text>
  </TouchableOpacity>
</View>
```

**`error` / `expired` — ошибка:**
```tsx
<View style={styles.center}>
  <Text style={styles.errorIcon}>❌</Text>
  <Text style={styles.errorText}>{signingState.error}</Text>
  <TouchableOpacity onPress={() => setSigningState({status: 'idle', sessionId: null, error: null})}>
    <Text>Попробовать снова</Text>
  </TouchableOpacity>
</View>
```

---

## 5. Навигация

### `src/navigation/types.ts`

```typescript
// Добавить в RootStackParamList:
'factoring-onboarding': {
  agreementId: number;
  pdfBase64: string;
};
```

### `src/navigation/stacks/RootStack.tsx`

```typescript
import FactoringOnboardingScreen from '../../screens/FactoringOnboardingScreen';

// Добавить в Stack.Navigator:
<Stack.Screen
  name="factoring-onboarding"
  component={FactoringOnboardingScreen}
  options={{headerShown: false}}
/>
```

---

## 6. Переводы

### `src/translations/ru-RU.json`

```json
{
  "factoring": {
    "sectionTitle": "Быстрая оплата",
    "statusActive": "Быстрая оплата доступна",
    "statusPending": "В процессе подтверждения",
    "descriptionConnect": "Получайте деньги за перевозки досрочно",
    "descriptionApproved": "Заявка одобрена. Подпишите договор для активации.",
    "buttonConnect": "Подключить",
    "buttonSign": "Подписать заявку",
    "errorKbe": "Заполните поле KBe для подключения быстрой оплаты",
    "errorKnp": "Заполните поле KNP для подключения быстрой оплаты",
    "errorBank": "Добавьте банковские реквизиты для подключения быстрой оплаты",
    "errorMainBank": "Установите основные банковские реквизиты",
    "errorConnect": "Ошибка при подключении. Проверьте реквизиты.",
    "onboarding": {
      "title": "Договор факторинга",
      "offerLink": "Ознакомиться с офертой MOST",
      "buttonSign": "Подписать через eGov Mobile",
      "creatingSession": "Создание сессии...",
      "waitingText": "Ожидаем подписания в eGov Mobile...",
      "buttonCancel": "Отменить",
      "successTitle": "Заявка подписана!",
      "successText": "Ожидайте рассмотрения заявки",
      "buttonBack": "Вернуться",
      "errorTitle": "Ошибка подписания",
      "buttonRetry": "Попробовать снова"
    }
  }
}
```

### `src/translations/en-US.json`

```json
{
  "factoring": {
    "sectionTitle": "Quick Payment",
    "statusActive": "Quick payment is available",
    "statusPending": "Confirmation in progress",
    "descriptionConnect": "Receive payment for transportation early",
    "descriptionApproved": "Application approved. Sign the contract to activate.",
    "buttonConnect": "Connect",
    "buttonSign": "Sign application",
    "errorKbe": "Fill in KBe to connect quick payment",
    "errorKnp": "Fill in KNP to connect quick payment",
    "errorBank": "Add bank details to connect quick payment",
    "errorMainBank": "Set main bank details",
    "errorConnect": "Connection error. Check your details.",
    "onboarding": {
      "title": "Factoring Agreement",
      "offerLink": "Read MOST offer",
      "buttonSign": "Sign via eGov Mobile",
      "creatingSession": "Creating session...",
      "waitingText": "Waiting for signing in eGov Mobile...",
      "buttonCancel": "Cancel",
      "successTitle": "Application signed!",
      "successText": "Your application is under review",
      "buttonBack": "Go back",
      "errorTitle": "Signing error",
      "buttonRetry": "Try again"
    }
  }
}
```

---

## Уточнить у бэкенда

- Тип поля `agreementId` в ответе `GET /v1/factoring/executor/contract/base64` — `number` или `string`?
  Важно для `signWithEgovMobile(agreementId, ...)` который принимает `documentId: number`.
- Нужно ли вызывать `POST /v1/factoring/executor/register-most` перед `initiate`, или бэк делает это автоматически?

---

## Ссылки на существующий код

- Паттерн eGov подписания: `src/screens/EgovSignTestScreen.tsx`
- Сервис подписания: `src/services/egovSignService.ts`
- Типы eGov: `src/types/egovSign.ts`
- Аналог на фронте: `coube-frontend/src/components/Organization/OrganizationContainer/OrganizationContainer.vue`
