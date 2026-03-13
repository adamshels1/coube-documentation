# Добавление авторизации/регистрации через Email

## Проблема

WhatsApp API иногда отваливается и коды авторизации не доставляются пользователям. Нужна альтернатива.

## Решение

Добавить возможность выбора способа верификации при входе и регистрации:
- **WhatsApp** (текущий, через телефон)
- **Email** (новый, альтернативный способ)

Пользователь **выбирает один из двух способов** и вводит либо телефон, либо email.

### UX Flow - Авторизация

```
┌──────────────────────────────────┐
│  Вход в Coube                   │
│                                  │
│  Выберите способ входа:          │
│  ┌────────────┐  ┌────────────┐ │
│  │ WhatsApp ✓│  │   Email    │ │
│  └────────────┘  └────────────┘ │
│                                  │
│  Телефон: +7 777 123 4567       │
│                                  │
│  [Получить код]                  │
└──────────────────────────────────┘

     ИЛИ

┌──────────────────────────────────┐
│  Вход в Coube                   │
│                                  │
│  Выберите способ входа:          │
│  ┌────────────┐  ┌────────────┐ │
│  │ WhatsApp  │  │  Email ✓   │ │
│  └────────────┘  └────────────┘ │
│                                  │
│  Email: ali@example.com          │
│                                  │
│  [Получить код]                  │
└──────────────────────────────────┘
```

### UX Flow - Регистрация

```
┌──────────────────────────────────┐
│  Регистрация в Coube            │
│                                  │
│  Выберите способ регистрации:    │
│  ┌────────────┐  ┌────────────┐ │
│  │ WhatsApp ✓│  │   Email    │ │
│  └────────────┘  └────────────┘ │
│                                  │
│  Имя: Али                        │
│  Фамилия: Касымов                │
│  Телефон: +7 777 123 4567       │
│                                  │
│  [Зарегистрироваться]            │
└──────────────────────────────────┘

     ИЛИ

┌──────────────────────────────────┐
│  Регистрация в Coube            │
│                                  │
│  Выберите способ регистрации:    │
│  ┌────────────┐  ┌────────────┐ │
│  │ WhatsApp  │  │  Email ✓   │ │
│  └────────────┘  └────────────┘ │
│                                  │
│  Имя: Али                        │
│  Фамилия: Касымов                │
│  Email: ali@example.com          │
│                                  │
│  [Зарегистрироваться]            │
└──────────────────────────────────┘
```

---

## Backend задачи

### 1. Database Schema

**Файл миграции:** `V1.XX__add_email_otp_channel.sql`

```sql
-- Добавить поле email в users.employee (если еще нет)
ALTER TABLE users.employee
ADD COLUMN IF NOT EXISTS email VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_employee_email ON users.employee(email);

-- Расширить таблицу OTP кодов
ALTER TABLE auth.otp_code
ADD COLUMN channel VARCHAR(20) NOT NULL DEFAULT 'whatsapp',  -- 'whatsapp' | 'email'
ADD COLUMN delivery_status VARCHAR(20) DEFAULT 'pending';    -- 'pending' | 'sent' | 'failed'

CREATE INDEX idx_otp_code_channel ON auth.otp_code(channel);
```

### 2. API Changes

#### Отправка OTP кода

**Endpoint:** `POST /api/auth/send-otp`

**Request (WhatsApp):**
```json
{
  "channel": "whatsapp",
  "phone": "+77771234567"
}
```

**Request (Email):**
```json
{
  "channel": "email",
  "email": "ali@example.com"
}
```

**Response:**
```json
{
  "success": true,
  "channel": "email",
  "maskedDestination": "a***@example.com",
  "expiresAt": "2026-01-27T12:10:00Z"
}
```

**Errors:**
- `400 INVALID_REQUEST` - не указан phone или email в зависимости от канала
- `404 USER_NOT_FOUND` - пользователь не найден
- `429 RATE_LIMIT_EXCEEDED` - превышен лимит запросов

#### Верификация кода

**Endpoint:** `POST /api/auth/verify-otp`

**Request (WhatsApp):**
```json
{
  "channel": "whatsapp",
  "phone": "+77771234567",
  "code": "123456"
}
```

**Request (Email):**
```json
{
  "channel": "email",
  "email": "ali@example.com",
  "code": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  "user": { ... }
}
```

#### Регистрация

**Endpoint:** `POST /api/auth/register`

**Request (WhatsApp):**
```json
{
  "channel": "whatsapp",
  "phone": "+77771234567",
  "firstName": "Али",
  "lastName": "Касымов"
}
```

**Request (Email):**
```json
{
  "channel": "email",
  "email": "ali@example.com",
  "firstName": "Али",
  "lastName": "Касымов"
}
```

**Response:** Отправляет OTP код на выбранный канал
```json
{
  "success": true,
  "channel": "email",
  "maskedDestination": "a***@example.com",
  "expiresAt": "2026-01-27T12:10:00Z"
}
```

После получения кода пользователь вызывает `POST /api/auth/verify-otp` для завершения регистрации.

### 3. Что нужно сделать

**Архитектура:**
- Рефакторить WhatsApp логику в multi-channel (Strategy pattern)
- Создать `OtpChannelStrategy` interface
- Реализовать `EmailChannelStrategy` и `WhatsAppChannelStrategy`
- Поддержка идентификации пользователя как по phone, так и по email

**Основные классы:**

```java
// Service для отправки OTP
MultiChannelOtpService.sendOtp(channel, identifier)
  // identifier = phone или email в зависимости от channel
  → findUserByIdentifier(channel, identifier)
  → generateOtpCode()
  → selectChannel(channel)
  → emailService.send() или whatsAppService.send()
  → save to DB

// Email отправка
EmailChannelStrategy.send(email, code)
  → использовать существующий EmailService
  → отправить HTML письмо с кодом

// WhatsApp отправка (существующий)
WhatsAppChannelStrategy.send(phone, code)
  → использовать существующий WhatsAppService
  → отправить сообщение с кодом
```

**Поиск пользователя:**
```java
// При авторизации
if (channel == "whatsapp") {
  user = employeeRepository.findByPhone(phone);
} else if (channel == "email") {
  user = employeeRepository.findByEmail(email);
}

// При регистрации - создать нового пользователя
if (channel == "whatsapp") {
  user = new Employee(phone, firstName, lastName);
} else if (channel == "email") {
  user = new Employee(email, firstName, lastName);
}
```

**Rate Limiting:**
- 3 запроса в 10 минут на identifier (phone или email) + channel
- Использовать Bucket4j

**Email шаблон:**
```html
<h2>Код подтверждения Coube</h2>
<p>Ваш код для входа: <strong style="font-size:32px">123456</strong></p>
<p>Код действителен 10 минут.</p>
<p>⚠️ Никому не сообщайте этот код!</p>
```

**Конфигурация (application.yml):**
```yaml
app:
  auth:
    otp:
      length: 6
      ttl-minutes: 10
    channels:
      whatsapp:
        enabled: ${WHATSAPP_ENABLED:true}
      email:
        enabled: ${EMAIL_OTP_ENABLED:true}
        from: noreply@coube.kz
    rate-limit:
      requests-per-window: 3
      window-minutes: 10
```

**Зависимости:**
```gradle
// Rate limiting
implementation 'com.github.vladimir-bukhtoyarov:bucket4j-core:8.1.0'

// Email уже есть в проекте (Spring Mail)
```

---

## Frontend задачи

### 1. Компоненты

**Создать:** `src/components/auth/AuthChannelSelector.vue`

```vue
<template>
  <div class="auth-channel-selector">
    <label>{{ $t('auth.selectMethod') }}</label>

    <div class="channel-buttons">
      <button
        :class="{ active: channel === 'whatsapp' }"
        @click="selectChannel('whatsapp')">
        <icon-whatsapp />
        WhatsApp
      </button>

      <button
        :class="{ active: channel === 'email' }"
        @click="selectChannel('email')">
        <icon-email />
        Email
      </button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'

const emit = defineEmits<{
  'channel-changed': [channel: 'whatsapp' | 'email']
}>()

const channel = ref<'whatsapp' | 'email'>('whatsapp')

const selectChannel = (selected: 'whatsapp' | 'email') => {
  channel.value = selected
  emit('channel-changed', selected)
}
</script>
```

**Обновить:** `src/components/auth/LoginForm.vue`

```vue
<template>
  <div class="login-form">
    <h2>{{ $t('auth.login') }}</h2>

    <!-- Выбор способа входа -->
    <auth-channel-selector @channel-changed="onChannelChange" />

    <!-- Поле ввода в зависимости от выбранного канала -->
    <phone-input
      v-if="selectedChannel === 'whatsapp'"
      v-model="phone"
      :placeholder="$t('auth.enterPhone')" />

    <email-input
      v-else
      v-model="email"
      :placeholder="$t('auth.enterEmail')" />

    <button @click="sendOtp">
      {{ $t('auth.getCode') }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores/authStore'
import { useRouter } from 'vue-router'

const authStore = useAuthStore()
const router = useRouter()

const selectedChannel = ref<'whatsapp' | 'email'>('whatsapp')
const phone = ref('')
const email = ref('')

const onChannelChange = (channel: 'whatsapp' | 'email') => {
  selectedChannel.value = channel
}

const sendOtp = async () => {
  try {
    const identifier = selectedChannel.value === 'whatsapp' ? phone.value : email.value

    await authStore.sendOtp({
      channel: selectedChannel.value,
      identifier
    })

    // Сохранить данные для экрана верификации
    sessionStorage.setItem('otpChannel', selectedChannel.value)
    sessionStorage.setItem('otpIdentifier', identifier)

    router.push('/auth/verify-otp')
  } catch (error) {
    console.error('Failed to send OTP:', error)
  }
}
</script>
```

**Создать:** `src/components/auth/RegisterForm.vue`

```vue
<template>
  <div class="register-form">
    <h2>{{ $t('auth.register') }}</h2>

    <!-- Выбор способа регистрации -->
    <auth-channel-selector @channel-changed="onChannelChange" />

    <!-- Общие поля -->
    <input
      v-model="firstName"
      :placeholder="$t('auth.firstName')" />

    <input
      v-model="lastName"
      :placeholder="$t('auth.lastName')" />

    <!-- Поле ввода в зависимости от выбранного канала -->
    <phone-input
      v-if="selectedChannel === 'whatsapp'"
      v-model="phone"
      :placeholder="$t('auth.enterPhone')" />

    <email-input
      v-else
      v-model="email"
      :placeholder="$t('auth.enterEmail')" />

    <button @click="register">
      {{ $t('auth.registerButton') }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { useAuthStore } from '@/stores/authStore'
import { useRouter } from 'vue-router'

const authStore = useAuthStore()
const router = useRouter()

const selectedChannel = ref<'whatsapp' | 'email'>('whatsapp')
const firstName = ref('')
const lastName = ref('')
const phone = ref('')
const email = ref('')

const onChannelChange = (channel: 'whatsapp' | 'email') => {
  selectedChannel.value = channel
}

const register = async () => {
  try {
    await authStore.register({
      channel: selectedChannel.value,
      firstName: firstName.value,
      lastName: lastName.value,
      ...(selectedChannel.value === 'whatsapp'
        ? { phone: phone.value }
        : { email: email.value })
    })

    // Сохранить данные для экрана верификации
    const identifier = selectedChannel.value === 'whatsapp' ? phone.value : email.value
    sessionStorage.setItem('otpChannel', selectedChannel.value)
    sessionStorage.setItem('otpIdentifier', identifier)

    router.push('/auth/verify-otp')
  } catch (error) {
    console.error('Registration failed:', error)
  }
}
</script>
```

### 2. Store (Pinia)

**Обновить:** `src/stores/authStore.ts`

```typescript
import { defineStore } from 'pinia'
import { authApi } from '@/api/auth'

interface SendOtpRequest {
  channel: 'whatsapp' | 'email'
  identifier: string // phone или email
}

interface RegisterRequest {
  channel: 'whatsapp' | 'email'
  firstName: string
  lastName: string
  phone?: string
  email?: string
}

interface VerifyOtpRequest {
  channel: 'whatsapp' | 'email'
  identifier: string
  code: string
}

export const useAuthStore = defineStore('auth', () => {
  const sendOtp = async (data: SendOtpRequest) => {
    const payload = data.channel === 'whatsapp'
      ? { channel: 'whatsapp', phone: data.identifier }
      : { channel: 'email', email: data.identifier }

    const response = await authApi.sendOtp(payload)

    return {
      success: response.success,
      channel: response.channel,
      maskedDestination: response.maskedDestination,
      expiresAt: response.expiresAt
    }
  }

  const register = async (data: RegisterRequest) => {
    const response = await authApi.register(data)
    return response
  }

  const verifyOtp = async (data: VerifyOtpRequest) => {
    const payload = data.channel === 'whatsapp'
      ? { channel: 'whatsapp', phone: data.identifier, code: data.code }
      : { channel: 'email', email: data.identifier, code: data.code }

    const response = await authApi.verifyOtp(payload)

    // Сохранить токены и пользователя
    localStorage.setItem('accessToken', response.accessToken)
    localStorage.setItem('refreshToken', response.refreshToken)

    return response
  }

  return { sendOtp, register, verifyOtp }
})
```

### 3. API Client

**Обновить:** `src/api/auth.ts`

```typescript
export const authApi = {
  async sendOtp(data: {
    channel: 'whatsapp' | 'email'
    phone?: string
    email?: string
  }) {
    return api.post('/api/auth/send-otp', data)
  },

  async register(data: {
    channel: 'whatsapp' | 'email'
    firstName: string
    lastName: string
    phone?: string
    email?: string
  }) {
    return api.post('/api/auth/register', data)
  },

  async verifyOtp(data: {
    channel: 'whatsapp' | 'email'
    phone?: string
    email?: string
    code: string
  }) {
    return api.post('/api/auth/verify-otp', data)
  }
}
```

### 4. Локализация

**Добавить в:** `src/i18n/locales/ru.json`

```json
{
  "auth": {
    "login": "Вход в систему",
    "register": "Регистрация",
    "selectMethod": "Выберите способ:",
    "whatsapp": "WhatsApp",
    "email": "Email",
    "enterPhone": "Введите номер телефона",
    "enterEmail": "Введите email",
    "firstName": "Имя",
    "lastName": "Фамилия",
    "getCode": "Получить код",
    "registerButton": "Зарегистрироваться",
    "verifyCode": "Введите код",
    "codeSentTo": "Код отправлен на {destination}",
    "codeSentWhatsApp": "Код отправлен в WhatsApp на номер {phone}",
    "codeSentEmail": "Код отправлен на email {email}",
    "checkSpam": "Не получили письмо? Проверьте папку «Спам»",
    "resendCode": "Отправить код повторно",
    "verifyButton": "Подтвердить"
  }
}
```

**en.json:**
```json
{
  "auth": {
    "login": "Login",
    "register": "Sign Up",
    "selectMethod": "Select method:",
    "whatsapp": "WhatsApp",
    "email": "Email",
    "enterPhone": "Enter phone number",
    "enterEmail": "Enter email",
    "firstName": "First Name",
    "lastName": "Last Name",
    "getCode": "Get Code",
    "registerButton": "Sign Up",
    "verifyCode": "Enter code",
    "codeSentTo": "Code sent to {destination}",
    "codeSentWhatsApp": "Code sent via WhatsApp to {phone}",
    "codeSentEmail": "Code sent to email {email}",
    "checkSpam": "Didn't receive email? Check your Spam folder",
    "resendCode": "Resend code",
    "verifyButton": "Verify"
  }
}
```

**kk.json:**
```json
{
  "auth": {
    "login": "Жүйеге кіру",
    "register": "Тіркелу",
    "selectMethod": "Әдісті таңдаңыз:",
    "whatsapp": "WhatsApp",
    "email": "Email",
    "enterPhone": "Телефон нөмірін енгізіңіз",
    "enterEmail": "Email енгізіңіз",
    "firstName": "Аты",
    "lastName": "Тегі",
    "getCode": "Код алу",
    "registerButton": "Тіркелу",
    "verifyCode": "Кодты енгізіңіз",
    "codeSentTo": "Код жіберілді {destination}",
    "codeSentWhatsApp": "Код WhatsApp арқылы жіберілді {phone}",
    "codeSentEmail": "Код email-ге жіберілді {email}",
    "checkSpam": "Хат келмеді ме? «Спам» қалтасын тексеріңіз",
    "resendCode": "Кодты қайта жіберу",
    "verifyButton": "Растау"
  }
}
```

**zh.json:**
```json
{
  "auth": {
    "login": "登录",
    "register": "注册",
    "selectMethod": "选择方式：",
    "whatsapp": "WhatsApp",
    "email": "邮箱",
    "enterPhone": "输入电话号码",
    "enterEmail": "输入邮箱",
    "firstName": "名字",
    "lastName": "姓氏",
    "getCode": "获取验证码",
    "registerButton": "注册",
    "verifyCode": "输入验证码",
    "codeSentTo": "验证码已发送至 {destination}",
    "codeSentWhatsApp": "验证码已通过 WhatsApp 发送至 {phone}",
    "codeSentEmail": "验证码已发送至邮箱 {email}",
    "checkSpam": "没收到邮件？请检查垃圾邮件文件夹",
    "resendCode": "重新发送验证码",
    "verifyButton": "验证"
  }
}
```

**Обновить:** `src/components/auth/VerifyOtpForm.vue`

```vue
<template>
  <div class="verify-otp-form">
    <h2>{{ $t('auth.verifyCode') }}</h2>

    <p v-if="channel === 'whatsapp'">
      {{ $t('auth.codeSentWhatsApp', { phone: maskedIdentifier }) }}
    </p>
    <p v-else>
      {{ $t('auth.codeSentEmail', { email: maskedIdentifier }) }}
    </p>

    <p v-if="channel === 'email'" class="hint">
      {{ $t('auth.checkSpam') }}
    </p>

    <input
      v-model="code"
      type="text"
      :placeholder="$t('auth.verifyCode')"
      maxlength="6"
      pattern="[0-9]*"
      inputmode="numeric" />

    <button @click="verify">
      {{ $t('auth.verifyButton') }}
    </button>

    <button @click="resend" class="resend-btn">
      {{ $t('auth.resendCode') }}
    </button>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useAuthStore } from '@/stores/authStore'
import { useRouter } from 'vue-router'

const authStore = useAuthStore()
const router = useRouter()

const channel = ref<'whatsapp' | 'email'>('whatsapp')
const identifier = ref('')
const maskedIdentifier = ref('')
const code = ref('')

onMounted(() => {
  // Получить данные из sessionStorage
  channel.value = sessionStorage.getItem('otpChannel') as 'whatsapp' | 'email'
  identifier.value = sessionStorage.getItem('otpIdentifier') || ''
  maskedIdentifier.value = maskIdentifier(identifier.value, channel.value)
})

const maskIdentifier = (value: string, ch: 'whatsapp' | 'email') => {
  if (ch === 'email') {
    const [name, domain] = value.split('@')
    return `${name[0]}***@${domain}`
  } else {
    return `+***${value.slice(-4)}`
  }
}

const verify = async () => {
  try {
    await authStore.verifyOtp({
      channel: channel.value,
      identifier: identifier.value,
      code: code.value
    })

    // Очистить sessionStorage
    sessionStorage.removeItem('otpChannel')
    sessionStorage.removeItem('otpIdentifier')

    router.push('/dashboard')
  } catch (error) {
    console.error('Verification failed:', error)
  }
}

const resend = async () => {
  try {
    await authStore.sendOtp({
      channel: channel.value,
      identifier: identifier.value
    })
  } catch (error) {
    console.error('Failed to resend OTP:', error)
  }
}
</script>
```

### 5. Стили

```scss
.auth-channel-selector {
  margin: 20px 0;

  .channel-buttons {
    display: flex;
    gap: 12px;

    button {
      flex: 1;
      padding: 12px;
      border: 2px solid #e5e7eb;
      border-radius: 8px;
      background: white;
      cursor: pointer;
      transition: all 0.2s;

      &.active {
        border-color: #2563eb;
        background: #eff6ff;
      }

      &:hover:not(:disabled) {
        border-color: #2563eb;
      }

      &:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
    }
  }
}

.verify-otp-form {
  max-width: 400px;
  margin: 0 auto;
  padding: 24px;

  input {
    width: 100%;
    padding: 12px;
    margin: 16px 0;
    font-size: 24px;
    text-align: center;
    letter-spacing: 8px;
    border: 2px solid #e5e7eb;
    border-radius: 8px;

    &:focus {
      outline: none;
      border-color: #2563eb;
    }
  }

  .hint {
    margin-top: 8px;
    font-size: 14px;
    color: #6b7280;
  }

  .resend-btn {
    margin-top: 12px;
    background: transparent;
    color: #2563eb;
    border: none;
    text-decoration: underline;
    cursor: pointer;
  }
}
```

---

## Mobile задачи (React Native)

### 1. Компоненты

**Создать:** `src/components/auth/AuthChannelSelector.tsx`

```typescript
import React from 'react'
import { View, TouchableOpacity, Text, StyleSheet } from 'react-native'

interface Props {
  selectedChannel: 'whatsapp' | 'email'
  onChannelChange: (channel: 'whatsapp' | 'email') => void
}

export const AuthChannelSelector: React.FC<Props> = ({
  selectedChannel,
  onChannelChange
}) => {
  return (
    <View style={styles.container}>
      <Text style={styles.label}>Выберите способ:</Text>

      <View style={styles.buttons}>
        <TouchableOpacity
          style={[
            styles.button,
            selectedChannel === 'whatsapp' && styles.buttonActive
          ]}
          onPress={() => onChannelChange('whatsapp')}>
          <Text style={styles.buttonText}>WhatsApp</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[
            styles.button,
            selectedChannel === 'email' && styles.buttonActive
          ]}
          onPress={() => onChannelChange('email')}>
          <Text style={styles.buttonText}>Email</Text>
        </TouchableOpacity>
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  container: {
    marginVertical: 20
  },
  label: {
    fontSize: 16,
    marginBottom: 12
  },
  buttons: {
    flexDirection: 'row',
    gap: 12
  },
  button: {
    flex: 1,
    padding: 12,
    borderWidth: 2,
    borderColor: '#e5e7eb',
    borderRadius: 8,
    backgroundColor: 'white',
    alignItems: 'center'
  },
  buttonActive: {
    borderColor: '#2563eb',
    backgroundColor: '#eff6ff'
  },
  buttonText: {
    fontSize: 14,
    fontWeight: '600'
  }
})
```

**Обновить:** `src/screens/auth/LoginScreen.tsx`

```typescript
import React, { useState } from 'react'
import { View, TextInput, Button } from 'react-native'
import { AuthChannelSelector } from '@/components/auth/AuthChannelSelector'
import { useAuthStore } from '@/stores/authStore'
import { useNavigation } from '@react-navigation/native'

export const LoginScreen = () => {
  const navigation = useNavigation()
  const { sendOtp } = useAuthStore()

  const [selectedChannel, setSelectedChannel] = useState<'whatsapp' | 'email'>('whatsapp')
  const [phone, setPhone] = useState('')
  const [email, setEmail] = useState('')

  const handleSendOtp = async () => {
    try {
      const identifier = selectedChannel === 'whatsapp' ? phone : email

      await sendOtp({
        channel: selectedChannel,
        identifier
      })

      // Сохранить данные для экрана верификации
      // В React Native можно использовать AsyncStorage или передать через навигацию
      navigation.navigate('VerifyOtp', {
        channel: selectedChannel,
        identifier
      })
    } catch (error) {
      console.error('Failed to send OTP:', error)
    }
  }

  return (
    <View>
      <AuthChannelSelector
        selectedChannel={selectedChannel}
        onChannelChange={setSelectedChannel}
      />

      {selectedChannel === 'whatsapp' ? (
        <TextInput
          value={phone}
          onChangeText={setPhone}
          placeholder="Введите номер телефона"
          keyboardType="phone-pad"
        />
      ) : (
        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="Введите email"
          keyboardType="email-address"
          autoCapitalize="none"
        />
      )}

      <Button title="Получить код" onPress={handleSendOtp} />
    </View>
  )
}
```

**Создать:** `src/screens/auth/RegisterScreen.tsx`

```typescript
import React, { useState } from 'react'
import { View, TextInput, Button } from 'react-native'
import { AuthChannelSelector } from '@/components/auth/AuthChannelSelector'
import { useAuthStore } from '@/stores/authStore'
import { useNavigation } from '@react-navigation/native'

export const RegisterScreen = () => {
  const navigation = useNavigation()
  const { register } = useAuthStore()

  const [selectedChannel, setSelectedChannel] = useState<'whatsapp' | 'email'>('whatsapp')
  const [firstName, setFirstName] = useState('')
  const [lastName, setLastName] = useState('')
  const [phone, setPhone] = useState('')
  const [email, setEmail] = useState('')

  const handleRegister = async () => {
    try {
      await register({
        channel: selectedChannel,
        firstName,
        lastName,
        ...(selectedChannel === 'whatsapp' ? { phone } : { email })
      })

      const identifier = selectedChannel === 'whatsapp' ? phone : email

      navigation.navigate('VerifyOtp', {
        channel: selectedChannel,
        identifier
      })
    } catch (error) {
      console.error('Registration failed:', error)
    }
  }

  return (
    <View>
      <AuthChannelSelector
        selectedChannel={selectedChannel}
        onChannelChange={setSelectedChannel}
      />

      <TextInput
        value={firstName}
        onChangeText={setFirstName}
        placeholder="Имя"
      />

      <TextInput
        value={lastName}
        onChangeText={setLastName}
        placeholder="Фамилия"
      />

      {selectedChannel === 'whatsapp' ? (
        <TextInput
          value={phone}
          onChangeText={setPhone}
          placeholder="Введите номер телефона"
          keyboardType="phone-pad"
        />
      ) : (
        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="Введите email"
          keyboardType="email-address"
          autoCapitalize="none"
        />
      )}

      <Button title="Зарегистрироваться" onPress={handleRegister} />
    </View>
  )
}
```

### 2. Store (Zustand)

**Обновить:** `src/stores/authStore.ts`

```typescript
import { create } from 'zustand'
import { authApi } from '@/api/auth'

interface AuthState {
  sendOtp: (data: {
    channel: 'whatsapp' | 'email'
    identifier: string
  }) => Promise<void>

  register: (data: {
    channel: 'whatsapp' | 'email'
    firstName: string
    lastName: string
    phone?: string
    email?: string
  }) => Promise<void>

  verifyOtp: (data: {
    channel: 'whatsapp' | 'email'
    identifier: string
    code: string
  }) => Promise<void>
}

export const useAuthStore = create<AuthState>((set) => ({
  sendOtp: async (data) => {
    const payload = data.channel === 'whatsapp'
      ? { channel: 'whatsapp', phone: data.identifier }
      : { channel: 'email', email: data.identifier }

    await authApi.sendOtp(payload)
  },

  register: async (data) => {
    await authApi.register(data)
  },

  verifyOtp: async (data) => {
    const payload = data.channel === 'whatsapp'
      ? { channel: 'whatsapp', phone: data.identifier, code: data.code }
      : { channel: 'email', email: data.identifier, code: data.code }

    const response = await authApi.verifyOtp(payload)

    // Сохранить токены
    await AsyncStorage.setItem('accessToken', response.accessToken)
    await AsyncStorage.setItem('refreshToken', response.refreshToken)
  }
}))
```

### 3. API Client

**Обновить:** `src/api/auth.ts`

```typescript
import { api } from './client'

export const authApi = {
  async sendOtp(data: {
    channel: 'whatsapp' | 'email'
    phone?: string
    email?: string
  }) {
    return api.post('/api/auth/send-otp', data)
  },

  async register(data: {
    channel: 'whatsapp' | 'email'
    firstName: string
    lastName: string
    phone?: string
    email?: string
  }) {
    return api.post('/api/auth/register', data)
  },

  async verifyOtp(data: {
    channel: 'whatsapp' | 'email'
    phone?: string
    email?: string
    code: string
  }) {
    return api.post('/api/auth/verify-otp', data)
  }
}
```

### 4. Локализация

Аналогично Frontend - добавить переводы в `src/i18n/` для всех языков (ru, en, kk, zh).

---

## Timeline

- **Backend**: 2-3 дня
  - DB миграция (1 час)
  - Multi-channel архитектура (1 день)
  - Email отправка + тесты (1 день)

- **Frontend**: 1-2 дня
  - UI компоненты (4 часа)
  - Store + API (2 часа)
  - Локализация (1 час)

- **Mobile**: 1-2 дня
  - Аналогично фронтенду

- **Тестирование**: 1 день

**Итого**: ~1 неделя

---

## Важные замечания

### База данных

1. **Уникальность данных:**
   - `email` должен быть уникальным в таблице `users.employee`
   - `phone` уже является уникальным
   - Пользователь может иметь ЛИБО phone, ЛИБО email (или оба, но хотя бы один обязателен)

2. **Индексы:**
   - Добавить индекс на `email` для быстрого поиска
   - Проверить производительность поиска пользователей

3. **Миграция существующих пользователей:**
   - Все текущие пользователи имеют только `phone`
   - При добавлении `email` в профиль - обновить запись
   - Валидация: если пользователь регистрируется через email, phone может быть NULL

### Безопасность

1. **Rate Limiting:**
   - Ограничение по IP адресу
   - Ограничение по identifier (phone/email)
   - Защита от brute-force атак на OTP коды

2. **Валидация:**
   - Email валидация (формат, существование домена)
   - Phone валидация (формат, длина)
   - OTP код: только цифры, длина 6 символов

3. **Email отправка:**
   - Использовать SMTP с TLS
   - Добавить SPF/DKIM записи для coube.kz
   - Мониторинг bounce rate и spam reports

### Логика работы

1. **Авторизация:**
   - Пользователь выбирает WhatsApp ИЛИ Email
   - Вводит соответствующий идентификатор (phone или email)
   - Получает OTP код
   - Вводит код и авторизуется

2. **Регистрация:**
   - Аналогично авторизации
   - Дополнительно вводит имя и фамилию
   - После верификации создается новый пользователь

3. **Переключение каналов:**
   - Если пользователь зарегистрировался через WhatsApp, он может потом добавить email в профиле
   - И наоборот
   - Оба канала работают независимо

## Чеклист перед деплоем

**Backend:**
- [ ] Миграция применена (добавлено поле `email`, индексы, таблица `auth.otp_code` обновлена)
- [ ] Email отправка работает (SMTP настроен)
- [ ] Rate limiting работает (Bucket4j интегрирован)
- [ ] Валидация email и phone работает
- [ ] Поиск пользователя по email и phone работает
- [ ] Регистрация через email и phone работает
- [ ] Тесты проходят (unit + integration)

**Frontend:**
- [ ] `AuthChannelSelector` компонент создан
- [ ] `LoginForm` обновлен (выбор канала, условный рендер полей)
- [ ] `RegisterForm` создан
- [ ] `VerifyOtpForm` обновлен (работает с обоими каналами)
- [ ] `authStore` обновлен (sendOtp, register, verifyOtp)
- [ ] API клиент обновлен
- [ ] Все переводы добавлены (ru, en, kk, zh)
- [ ] Responsive на всех устройствах
- [ ] UI/UX тестирование пройдено

**Mobile:**
- [ ] `AuthChannelSelector` компонент создан
- [ ] `LoginScreen` обновлен
- [ ] `RegisterScreen` создан
- [ ] `authStore` (Zustand) обновлен
- [ ] API клиент обновлен
- [ ] iOS/Android тестирование пройдено
- [ ] Переводы добавлены (ru, en, kk, zh)

**Infrastructure:**
- [ ] SMTP конфигурация проверена
- [ ] SPF/DKIM записи настроены для coube.kz
- [ ] Email шаблоны созданы и протестированы
- [ ] Мониторинг email доставки настроен
- [ ] Алерты на превышение rate limit настроены
- [ ] Логирование работает

**Тестирование:**
- [ ] E2E тесты: регистрация через WhatsApp
- [ ] E2E тесты: регистрация через Email
- [ ] E2E тесты: авторизация через WhatsApp
- [ ] E2E тесты: авторизация через Email
- [ ] Тест: переключение между каналами
- [ ] Тест: повторная отправка кода
- [ ] Тест: истечение срока действия кода
- [ ] Тест: неправильный код
- [ ] Тест: rate limiting

---

**Создано**: 2026-01-27
**Обновлено**: 2026-01-27
**Статус**: 📋 Ready to Start
**Приоритет**: 🔥 High (критичный для бизнеса из-за нестабильности WhatsApp API)
