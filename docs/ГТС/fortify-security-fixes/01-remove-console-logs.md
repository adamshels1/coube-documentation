# Задача 1: Убрать console.log с приватными данными

**Приоритет:** Critical (Privacy Violation — 8 проблем)
**Риск поломки:** Нулевой
**Компонент:** coube-mobile

## Проблема

Приватные данные (геолокация, данные пользователя) логируются через `console.log` и видны в logcat/консоли устройства.

## Затронутые файлы

### 1. `coube-mobile/src/components/EmulatorSendLocationButton.tsx`
**Строки 39-42:**
```typescript
// БЫЛО:
console.log('Эмулирована отправка геолокации:', locationData);
// ...
console.error('Error sending location:', error);
```
**Исправление:**
```typescript
// СТАЛО:
if (__DEV__) {
  console.log('Эмулирована отправка геолокации:', locationData);
}
// ...
if (__DEV__) {
  console.error('Error sending location:', error);
}
```

### 2. `coube-mobile/src/screens/ProfileScreen.tsx`
**Строка ~74:**
```typescript
// БЫЛО:
console.log('Эмулирована отправка геолокации:', locationData);

// СТАЛО:
if (__DEV__) {
  console.log('Эмулирована отправка геолокации:', locationData);
}
```

### 3. `coube-mobile/src/api/index.ts`
**Строки ~385-400 (функция uploadCourierPhoto):**
```typescript
// БЫЛО:
console.log('  FormData prepared, file:', JSON.stringify(fileData));
console.log('fetch POST', url);
console.log('  headers:', JSON.stringify(Object.keys(headers)));
console.log('Response status:', response.status);
console.log('Response body:', responseText.substring(0, 500));
console.log('Upload successful:', data);

// СТАЛО: обернуть каждый в __DEV__
if (__DEV__) {
  console.log('fetch POST', url);
}
```

### 4. `coube-mobile/src/services/telegram.ts`
**Строки 16, 22:**
```typescript
// БЫЛО:
console.log('Не отправляем сообщение в Telegram: эмулятор/симулятор:\n', message+'\n');
console.log('Sending message to Telegram:', message);

// СТАЛО:
if (__DEV__) {
  console.log('Не отправляем сообщение в Telegram: эмулятор/симулятор');
}
if (__DEV__) {
  console.log('Sending message to Telegram');
}
```

## Альтернативный подход (рекомендуемый)

Добавить babel-plugin для автоматического удаления console.log в production:

**babel.config.js:**
```javascript
module.exports = {
  // ...existing config
  env: {
    production: {
      plugins: ['transform-remove-console'],
    },
  },
};
```

```bash
cd coube-mobile && npm install --save-dev babel-plugin-transform-remove-console
```

## Проверка
- `npm run lint` — без ошибок
- Запуск на эмуляторе — приложение работает
- В release сборке console.log не должно быть в logcat
