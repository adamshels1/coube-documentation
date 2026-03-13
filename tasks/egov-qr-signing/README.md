# Интеграция подписания через eGov Mobile (QR код и Deep Link)

## 📋 Описание проекта

Реализация двух способов подписания документов через мобильное приложение eGov Mobile:
1. **QR подписание** - в веб-интерфейсе показывается QR код, который сканируется в eGov Mobile
2. **Кросс подписание (Deep Link)** - из мобильного приложения Coube открывается eGov Mobile через deep link

## 📚 Документация

Основная документация находится в:
- `coube-documentation/business_analysis/converted/QR sign/Документация_к_QR_и_Кросс_подписанию.md`
- `coube-documentation/business_analysis/converted/QR sign/Smart Bridge.md`

## 🎯 Задачи

### Backend (4 задачи)
1. [✓] `backend/01-egov-sign-controller.md` - API №1: Контроллер метаданных подписания
2. [✓] `backend/02-egov-document-controller.md` - API №2: Контроллер документов
3. [✓] `backend/03-session-service.md` - Сервис управления сессиями
4. [✓] `backend/04-session-entity.md` - Entity и Repository для сессий

### Frontend (4 задачи)
5. [✓] `frontend/01-select-sign-method-update.md` - Обновление выбора метода подписания
6. [✓] `frontend/02-qr-sign-modal.md` - Компонент отображения QR кода
7. [✓] `frontend/03-egov-api-service.md` - API сервис для eGov
8. [✓] `frontend/04-contract-integration.md` - Интеграция с подписанием контрактов

### Mobile (5 задач)
9. [✓] `mobile/01-deep-linking-config.md` - Конфигурация deep linking
10. [✓] `mobile/02-egov-sign-service.md` - Сервис работы с eGov Mobile
11. [✓] `mobile/03-signing-screen-update.md` - Обновление экрана подписания
12. [✓] `mobile/04-api-client.md` - API клиент для мобильного приложения
13. [✓] `mobile/05-navigation-handler.md` - Обработка навигации после подписания

## 🔄 Процесс работы

### QR подписание (Web)
```
1. Пользователь → Нажимает "Подписать" → Выбирает "QR код"
2. Frontend → POST /api/v1/egov-sign/init → Backend создает сессию
3. Frontend → Показывает QR: "mobileSign:https://api.coube.kz/api/v1/egov-sign/session/{sessionId}"
4. Пользователь → Сканирует QR в eGov Mobile
5. eGov Mobile → GET /api/v1/egov-sign/session/{sessionId} → Получает API №1
6. eGov Mobile → GET /api/v1/egov-sign/session/{sessionId}/document → Получает документ (API №2)
7. Пользователь → Подписывает в eGov Mobile
8. eGov Mobile → PUT /api/v1/egov-sign/session/{sessionId}/document → Отправляет подписанный CMS
9. Backend → Проверяет подпись → Сохраняет
10. Frontend → Polling статуса → Обновляет UI
```

### Кросс подписание (Mobile)
```
1. Пользователь → Нажимает "Подписать" в Coube Mobile
2. Mobile → POST /api/v1/egov-sign/init → Backend создает сессию
3. Mobile → Формирует deep link: "https://mgovsign.page.link/?link={API_URL_ENCODED}&apn=kz.mobile.mgov"
4. Mobile → Открывает eGov Mobile через Linking.openURL()
5. eGov Mobile → GET API №1 → GET API №2 → Пользователь подписывает → PUT API №2
6. eGov Mobile → Возвращает в Coube Mobile (через deep link callback)
7. Mobile → Получает статус → Обновляет UI
```

## 📊 API Спецификация

### API №1: Метаданные подписания
**GET** `/api/v1/egov-sign/session/{sessionId}`

Response:
```json
{
  "description": "Подписание договора №123",
  "expiry_date": "2026-01-08T10:00:00.000Z",
  "organisation": {
    "nameRu": "ТОО \"COUBE\"",
    "nameKz": "\"COUBE\" ЖШС",
    "nameEn": "COUBE LLP",
    "bin": "000740000728"
  },
  "document": {
    "uri": "https://api.coube.kz/api/v1/egov-sign/session/{sessionId}/document",
    "auth_type": "Token",
    "auth_token": "eyJhbGciOiJIUzI1NiIs..."
  }
}
```

### API №2: Документы
**GET** `/api/v1/egov-sign/session/{sessionId}/document`

Response:
```json
{
  "signMethod": "CMS_WITH_DATA",
  "version": 1,
  "documentsToSign": [
    {
      "id": 1,
      "nameRu": "Договор перевозки №123",
      "nameKz": "№123 тасымалдау шарты",
      "nameEn": "Transportation Agreement #123",
      "document": {
        "file": {
          "mime": "application/pdf",
          "data": "JVBERi0xLjcK..."
        }
      }
    }
  ]
}
```

**PUT** `/api/v1/egov-sign/session/{sessionId}/document`

Request: тот же JSON, но с подписанными данными в поле `data`

## 🔐 Безопасность

- ✅ JWT токены для `auth_token` с TTL 30 минут
- ✅ Валидация подписей через `SignVerifyService` (Kalkan)
- ✅ Проверка BIN/IIN подписанта
- ✅ Проверка метки времени (TSP)
- ✅ HTTPS для всех запросов
- ✅ CORS для API eGov Mobile

## ⏱️ Оценка времени

| Компонент | Задач | Время |
|-----------|-------|-------|
| Backend   | 4     | 2-3 дня |
| Frontend  | 4     | 1-2 дня |
| Mobile    | 5     | 2-3 дня |
| Тестирование | - | 1 день |
| **Итого** | **13** | **6-9 дней** |

## 🚀 Порядок разработки

1. **Backend** → Создать API №1 и API №2
2. **Frontend** → QR подписание
3. **Mobile** → Deep link подписание
4. **Интеграция** → Тестирование end-to-end

## 📝 Статус задач

- [ ] Backend: 0/4
- [ ] Frontend: 0/4
- [ ] Mobile: 0/5
- [ ] **Общий прогресс: 0/13 (0%)**

---

**Дата создания:** 2026-01-07
**Автор:** Claude Code
**Версия:** 1.0
