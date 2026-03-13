# Отчеты заказчика - Логи уведомлений

## Описание задачи
Реализовать API для отчета "Логи уведомлений" с трекингом всех отправленных уведомлений, анализом доставляемости, эффективности каналов связи и автоматизации коммуникаций.

## Frontend UI референс
- Компонент: `NotificationLogsReport.vue` (существующий)
- Фильтры: канал отправки, статус доставки, тип уведомления, получатель, период
- Метрики: всего уведомлений, доставлено, не доставлено, процент открытий, конверсия
- Анализ каналов: email, SMS, push, in-app уведомления
- Эффективность: время доставки, bounce rate, engagement

## Эндпоинты для реализации

### 1. GET `/api/reports/notification-logs/list`
Получение логов уведомлений

**Параметры запроса:**
```json
{
  "channel": "string (optional)", // email, sms, push, in_app, telegram
  "deliveryStatus": "string (optional)", // sent, delivered, failed, bounced, opened, clicked
  "notificationType": "string (optional)", // transport_update, invoice_ready, deadline_warning, payment_reminder
  "recipientId": "number (optional)",
  "priority": "string (optional)", // low, normal, high, urgent
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "page": "number (default: 0)",
  "size": "number (default: 20)"
}
```

**Ответ:**
```json
{
  "data": [
    {
      "id": "number",
      "notificationType": "string",
      "channel": "string",
      "priority": "string",
      "recipientInfo": {
        "recipientId": "number",
        "recipientName": "string",
        "recipientEmail": "string",
        "recipientPhone": "string"
      },
      "content": {
        "subject": "string",
        "message": "string",
        "templateId": "string",
        "variables": "object"
      },
      "deliveryInfo": {
        "sentAt": "string",
        "deliveredAt": "string",
        "deliveryStatus": "string",
        "deliveryAttempts": "number",
        "deliveryTime": "number", // секунды
        "providerId": "string", // внешний провайдер
        "messageId": "string" // ID у провайдера
      },
      "engagement": {
        "opened": "boolean",
        "openedAt": "string",
        "clicked": "boolean",
        "clickedAt": "string",
        "replied": "boolean",
        "repliedAt": "string"
      },
      "errorInfo": {
        "errorCode": "string",
        "errorMessage": "string",
        "retryCount": "number",
        "nextRetryAt": "string"
      },
      "metadata": {
        "relatedEntityType": "string", // transportation, invoice, contract
        "relatedEntityId": "number",
        "campaignId": "string",
        "userAgent": "string",
        "ipAddress": "string"
      }
    }
  ],
  "totalElements": "number",
  "totalPages": "number",
  "summary": {
    "totalNotifications": "number",
    "sentNotifications": "number",
    "deliveredNotifications": "number",
    "failedNotifications": "number",
    "deliveryRate": "number", // процент
    "openRate": "number", // процент
    "clickRate": "number" // процент
  }
}
```

### 2. GET `/api/reports/notification-logs/analytics`
Получение аналитики по уведомлениям

**Ответ:**
```json
{
  "channelPerformance": [
    {
      "channel": "string",
      "totalSent": "number",
      "delivered": "number",
      "failed": "number",
      "deliveryRate": "number",
      "avgDeliveryTime": "number", // секунды
      "openRate": "number",
      "clickRate": "number",
      "bounceRate": "number",
      "cost": "number", // стоимость отправки
      "roi": "number" // возврат на инвестиции
    }
  ],
  "notificationTypes": [
    {
      "type": "string",
      "count": "number",
      "deliveryRate": "number",
      "engagementRate": "number",
      "effectiveness": "number" // 0-100
    }
  ],
  "timeAnalysis": {
    "hourlyDistribution": [
      {
        "hour": "number",
        "sentCount": "number",
        "openRate": "number"
      }
    ],
    "dailyDistribution": [
      {
        "dayOfWeek": "number",
        "sentCount": "number",
        "engagementRate": "number"
      }
    ]
  },
  "recipientAnalysis": {
    "topRecipients": [
      {
        "recipientName": "string",
        "notificationCount": "number",
        "engagementRate": "number"
      }
    ],
    "segmentation": [
      {
        "segment": "string", // customers, executors, admins
        "count": "number",
        "engagementRate": "number"
      }
    ]
  }
}
```

### 3. GET `/api/reports/notification-logs/delivery-issues`
Получение анализа проблем доставки

**Ответ:**
```json
{
  "deliveryIssues": [
    {
      "issueType": "string", // bounced_email, invalid_phone, blocked_content, rate_limit
      "count": "number",
      "percentage": "number",
      "affectedRecipients": "number",
      "totalCost": "number", // потери от недоставки
      "examples": [
        {
          "notificationId": "number",
          "recipientInfo": "string",
          "errorMessage": "string",
          "timestamp": "string"
        }
      ]
    }
  ],
  "providerPerformance": [
    {
      "providerId": "string",
      "providerName": "string",
      "channel": "string",
      "sentCount": "number",
      "deliveryRate": "number",
      "avgDeliveryTime": "number",
      "errorRate": "number",
      "cost": "number",
      "reliability": "number" // 0-100
    }
  ],
  "blacklistedContacts": [
    {
      "contactType": "string", // email, phone
      "contact": "string",
      "reason": "string",
      "blacklistedAt": "string",
      "lastAttempt": "string"
    }
  ],
  "retryAnalysis": {
    "totalRetries": "number",
    "successfulRetries": "number",
    "retrySuccessRate": "number",
    "avgRetryDelay": "number" // минуты
  }
}
```

### 4. GET `/api/reports/notification-logs/campaigns`
Получение анализа кампаний уведомлений

**Ответ:**
```json
{
  "campaigns": [
    {
      "campaignId": "string",
      "campaignName": "string",
      "campaignType": "string", // promotional, transactional, informational
      "startDate": "string",
      "endDate": "string",
      "targetAudience": "number",
      "sentCount": "number",
      "deliveryRate": "number",
      "openRate": "number",
      "clickRate": "number",
      "conversionRate": "number",
      "totalCost": "number",
      "revenue": "number", // если применимо
      "roi": "number"
    }
  ],
  "templatePerformance": [
    {
      "templateId": "string",
      "templateName": "string",
      "usageCount": "number",
      "avgOpenRate": "number",
      "avgClickRate": "number",
      "conversionRate": "number",
      "effectiveness": "number" // 0-100
    }
  ],
  "abTestResults": [
    {
      "testId": "string",
      "testName": "string",
      "variantA": {
        "name": "string",
        "sentCount": "number",
        "openRate": "number",
        "clickRate": "number"
      },
      "variantB": {
        "name": "string",
        "sentCount": "number",
        "openRate": "number",
        "clickRate": "number"
      },
      "winner": "string",
      "confidence": "number" // процент уверенности
    }
  ]
}
```

### 5. GET `/api/reports/notification-logs/charts`
Получение данных для графиков уведомлений

**Ответ:**
```json
{
  "deliveryTrends": {
    "dates": ["string"],
    "sent": ["number"],
    "delivered": ["number"],
    "failed": ["number"],
    "deliveryRate": ["number"]
  },
  "channelComparison": {
    "channels": ["string"],
    "deliveryRates": ["number"],
    "openRates": ["number"],
    "costs": ["number"]
  },
  "engagementAnalysis": {
    "hours": ["number"],
    "openRates": ["number"],
    "clickRates": ["number"]
  },
  "errorDistribution": {
    "errorTypes": ["string"],
    "counts": ["number"],
    "percentages": ["number"]
  }
}
```

### 6. GET `/api/reports/notification-logs/export`
Экспорт логов уведомлений в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с детальными логами

## SQL запросы (базовая логика)

### Основной запрос для логов уведомлений
```sql
SELECT 
    nl.id,
    nl.notification_type as notificationType,
    nl.channel,
    nl.priority,
    
    -- Информация о получателе
    u.id as recipientId,
    u.full_name as recipientName,
    u.email as recipientEmail,
    u.phone as recipientPhone,
    
    -- Контент уведомления
    nl.subject,
    nl.message,
    nl.template_id as templateId,
    nl.template_variables as templateVariables,
    
    -- Информация о доставке
    nl.sent_at as sentAt,
    nl.delivered_at as deliveredAt,
    nl.delivery_status as deliveryStatus,
    nl.delivery_attempts as deliveryAttempts,
    EXTRACT(EPOCH FROM (nl.delivered_at - nl.sent_at)) as deliveryTime,
    nl.provider_id as providerId,
    nl.external_message_id as messageId,
    
    -- Engagement метрики
    nl.opened as opened,
    nl.opened_at as openedAt,
    nl.clicked as clicked,
    nl.clicked_at as clickedAt,
    nl.replied as replied,
    nl.replied_at as repliedAt,
    
    -- Информация об ошибках
    nl.error_code as errorCode,
    nl.error_message as errorMessage,
    nl.retry_count as retryCount,
    nl.next_retry_at as nextRetryAt,
    
    -- Метаданные
    nl.related_entity_type as relatedEntityType,
    nl.related_entity_id as relatedEntityId,
    nl.campaign_id as campaignId,
    nl.user_agent as userAgent,
    nl.ip_address as ipAddress
    
FROM notifications.notification_log nl
    LEFT JOIN user.user u ON nl.recipient_user_id = u.id
WHERE 
    ($organizationId IS NULL OR u.organization_id = $organizationId OR nl.organization_id = $organizationId)
    AND ($channel IS NULL OR nl.channel = $channel)
    AND ($deliveryStatus IS NULL OR nl.delivery_status = $deliveryStatus)
    AND ($notificationType IS NULL OR nl.notification_type = $notificationType)
    AND ($recipientId IS NULL OR nl.recipient_user_id = $recipientId)
    AND ($priority IS NULL OR nl.priority = $priority)
    AND ($dateFrom IS NULL OR nl.sent_at >= $dateFrom)
    AND ($dateTo IS NULL OR nl.sent_at <= $dateTo)
ORDER BY nl.sent_at DESC;
```

### Запрос для аналитики каналов
```sql
WITH channel_stats AS (
    SELECT 
        nl.channel,
        COUNT(*) as totalSent,
        COUNT(CASE WHEN nl.delivery_status = 'delivered' THEN 1 END) as delivered,
        COUNT(CASE WHEN nl.delivery_status IN ('failed', 'bounced') THEN 1 END) as failed,
        ROUND((COUNT(CASE WHEN nl.delivery_status = 'delivered' THEN 1 END)::float / COUNT(*)) * 100, 2) as deliveryRate,
        AVG(EXTRACT(EPOCH FROM (nl.delivered_at - nl.sent_at))) as avgDeliveryTime,
        ROUND((COUNT(CASE WHEN nl.opened = true THEN 1 END)::float / 
               NULLIF(COUNT(CASE WHEN nl.delivery_status = 'delivered' THEN 1 END), 0)) * 100, 2) as openRate,
        ROUND((COUNT(CASE WHEN nl.clicked = true THEN 1 END)::float / 
               NULLIF(COUNT(CASE WHEN nl.delivery_status = 'delivered' THEN 1 END), 0)) * 100, 2) as clickRate,
        ROUND((COUNT(CASE WHEN nl.delivery_status = 'bounced' THEN 1 END)::float / COUNT(*)) * 100, 2) as bounceRate,
        SUM(COALESCE(nc.cost_per_message, 0)) as totalCost
    FROM notifications.notification_log nl
        LEFT JOIN notifications.notification_cost nc ON nl.channel = nc.channel
    WHERE nl.organization_id = $organizationId
        AND nl.sent_at >= $dateFrom
        AND nl.sent_at <= $dateTo
    GROUP BY nl.channel
),
channel_conversion AS (
    SELECT 
        nl.channel,
        COUNT(CASE WHEN c.id IS NOT NULL THEN 1 END) as conversions,
        ROUND((COUNT(CASE WHEN c.id IS NOT NULL THEN 1 END)::float / 
               NULLIF(COUNT(CASE WHEN nl.clicked = true THEN 1 END), 0)) * 100, 2) as conversionRate
    FROM notifications.notification_log nl
        LEFT JOIN notifications.notification_conversion c ON nl.id = c.notification_id
    WHERE nl.organization_id = $organizationId
        AND nl.sent_at >= $dateFrom
        AND nl.sent_at <= $dateTo
    GROUP BY nl.channel
)
SELECT 
    cs.*,
    COALESCE(cc.conversions, 0) as conversions,
    COALESCE(cc.conversionRate, 0) as conversionRate,
    CASE 
        WHEN cs.totalCost > 0 
        THEN ROUND((COALESCE(cc.conversions, 0) * 1000) / cs.totalCost, 2) -- ROI calculation
        ELSE 0 
    END as roi
FROM channel_stats cs
    LEFT JOIN channel_conversion cc ON cs.channel = cc.channel
ORDER BY cs.deliveryRate DESC;
```

### Анализ проблем доставки
```sql
WITH delivery_issues AS (
    SELECT 
        CASE 
            WHEN nl.error_code LIKE '%BOUNCE%' OR nl.error_message LIKE '%bounce%' THEN 'bounced_email'
            WHEN nl.error_code LIKE '%INVALID%' OR nl.error_message LIKE '%invalid%' THEN 'invalid_contact'
            WHEN nl.error_code LIKE '%BLOCKED%' OR nl.error_message LIKE '%blocked%' THEN 'blocked_content'
            WHEN nl.error_code LIKE '%RATE%' OR nl.error_message LIKE '%rate limit%' THEN 'rate_limit'
            WHEN nl.error_code LIKE '%SPAM%' OR nl.error_message LIKE '%spam%' THEN 'spam_filter'
            ELSE 'other'
        END as issueType,
        COUNT(*) as count,
        COUNT(DISTINCT nl.recipient_user_id) as affectedRecipients,
        SUM(COALESCE(nc.cost_per_message, 0)) as totalCost
    FROM notifications.notification_log nl
        LEFT JOIN notifications.notification_cost nc ON nl.channel = nc.channel
    WHERE nl.delivery_status IN ('failed', 'bounced')
        AND nl.organization_id = $organizationId
        AND nl.sent_at >= $dateFrom
        AND nl.sent_at <= $dateTo
    GROUP BY issueType
),
total_notifications AS (
    SELECT COUNT(*) as total
    FROM notifications.notification_log
    WHERE organization_id = $organizationId
        AND sent_at >= $dateFrom
        AND sent_at <= $dateTo
)
SELECT 
    di.*,
    ROUND((di.count::float / tn.total) * 100, 2) as percentage
FROM delivery_issues di
    CROSS JOIN total_notifications tn
ORDER BY di.count DESC;
```

## Необходимые таблицы БД

### `notifications.notification_log` - логи уведомлений
```sql
CREATE SCHEMA IF NOT EXISTS notifications;

CREATE TABLE notifications.notification_log (
    id BIGSERIAL PRIMARY KEY,
    organization_id BIGINT REFERENCES user.organization(id),
    recipient_user_id BIGINT REFERENCES user.user(id),
    notification_type VARCHAR(50) NOT NULL,
    channel VARCHAR(20) NOT NULL, -- email, sms, push, in_app, telegram
    priority VARCHAR(10) DEFAULT 'normal', -- low, normal, high, urgent
    
    -- Контент
    subject VARCHAR(255),
    message TEXT,
    template_id VARCHAR(50),
    template_variables JSONB,
    
    -- Доставка
    sent_at TIMESTAMP,
    delivered_at TIMESTAMP,
    delivery_status VARCHAR(20) DEFAULT 'pending', -- pending, sent, delivered, failed, bounced
    delivery_attempts INTEGER DEFAULT 0,
    provider_id VARCHAR(50),
    external_message_id VARCHAR(100),
    
    -- Engagement
    opened BOOLEAN DEFAULT false,
    opened_at TIMESTAMP,
    clicked BOOLEAN DEFAULT false,
    clicked_at TIMESTAMP,
    replied BOOLEAN DEFAULT false,
    replied_at TIMESTAMP,
    
    -- Ошибки и повторы
    error_code VARCHAR(50),
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    next_retry_at TIMESTAMP,
    
    -- Метаданные
    related_entity_type VARCHAR(30), -- transportation, invoice, contract
    related_entity_id BIGINT,
    campaign_id VARCHAR(50),
    user_agent TEXT,
    ip_address INET,
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_notification_log_org_date ON notifications.notification_log(organization_id, sent_at);
CREATE INDEX idx_notification_log_recipient ON notifications.notification_log(recipient_user_id);
CREATE INDEX idx_notification_log_channel ON notifications.notification_log(channel);
CREATE INDEX idx_notification_log_status ON notifications.notification_log(delivery_status);
```

### `notifications.notification_template` - шаблоны уведомлений
```sql
CREATE TABLE notifications.notification_template (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    channel VARCHAR(20) NOT NULL,
    subject_template VARCHAR(255),
    body_template TEXT NOT NULL,
    variables JSONB, -- список переменных
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### `notifications.notification_provider` - провайдеры отправки
```sql
CREATE TABLE notifications.notification_provider (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    channel VARCHAR(20) NOT NULL,
    api_endpoint VARCHAR(255),
    api_key_encrypted TEXT,
    is_active BOOLEAN DEFAULT true,
    max_rate_per_minute INTEGER DEFAULT 100,
    reliability_score DECIMAL(3,2) DEFAULT 0.95,
    cost_per_message DECIMAL(10,4) DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `notifications.notification_cost` - стоимость отправки
```sql
CREATE TABLE notifications.notification_cost (
    id BIGSERIAL PRIMARY KEY,
    channel VARCHAR(20) NOT NULL,
    provider_id VARCHAR(50) REFERENCES notifications.notification_provider(id),
    cost_per_message DECIMAL(10,4) NOT NULL,
    currency VARCHAR(3) DEFAULT 'KZT',
    effective_from DATE NOT NULL,
    effective_to DATE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `notifications.notification_conversion` - конверсии
```sql
CREATE TABLE notifications.notification_conversion (
    id BIGSERIAL PRIMARY KEY,
    notification_id BIGINT REFERENCES notifications.notification_log(id),
    conversion_type VARCHAR(30) NOT NULL, -- signup, purchase, contract_signed, payment_made
    conversion_value DECIMAL(15,2),
    converted_at TIMESTAMP DEFAULT NOW()
);
```

### `notifications.notification_blacklist` - черный список
```sql
CREATE TABLE notifications.notification_blacklist (
    id BIGSERIAL PRIMARY KEY,
    contact_type VARCHAR(10) NOT NULL, -- email, phone
    contact_value VARCHAR(255) NOT NULL,
    reason VARCHAR(100),
    blacklisted_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(contact_type, contact_value)
);
```

## Техническая реализация

1. Создать схему `notifications` в БД
2. Создать контроллер `NotificationLogsReportController`
3. Создать сервис `NotificationLogsReportService`
4. Интегрировать с провайдерами (SMTP, SMS, Push сервисы)
5. Реализовать систему retry для неудачных отправок
6. Добавить tracking открытий и кликов
7. Создать систему A/B тестирования шаблонов
8. Реализовать антиспам фильтрацию

## Интеграция с провайдерами

### Сервис управления уведомлениями
```java
@Service
public class NotificationService {
    
    private final Map<String, NotificationProvider> providers;
    private final NotificationLogRepository logRepository;
    
    public NotificationResult sendNotification(NotificationRequest request) {
        NotificationLog log = createNotificationLog(request);
        
        try {
            NotificationProvider provider = selectBestProvider(request.getChannel());
            String externalId = provider.send(request);
            
            log.setDeliveryStatus("sent");
            log.setSentAt(Instant.now());
            log.setExternalMessageId(externalId);
            log.setProviderId(provider.getId());
            
        } catch (Exception e) {
            log.setDeliveryStatus("failed");
            log.setErrorMessage(e.getMessage());
            log.setRetryCount(log.getRetryCount() + 1);
            
            // Планируем повтор
            if (log.getRetryCount() < 3) {
                scheduleRetry(log);
            }
        }
        
        logRepository.save(log);
        return NotificationResult.from(log);
    }
    
    private NotificationProvider selectBestProvider(String channel) {
        return providers.values().stream()
            .filter(p -> p.getChannel().equals(channel))
            .filter(NotificationProvider::isActive)
            .max(Comparator.comparing(NotificationProvider::getReliabilityScore))
            .orElseThrow(() -> new RuntimeException("No provider available for " + channel));
    }
    
    @Async
    public void trackEngagement(String notificationId, String eventType, String userAgent, String ipAddress) {
        NotificationLog log = logRepository.findById(Long.valueOf(notificationId))
            .orElse(null);
            
        if (log != null) {
            switch (eventType) {
                case "open":
                    log.setOpened(true);
                    log.setOpenedAt(Instant.now());
                    break;
                case "click":
                    log.setClicked(true);
                    log.setClickedAt(Instant.now());
                    break;
                case "reply":
                    log.setReplied(true);
                    log.setRepliedAt(Instant.now());
                    break;
            }
            
            log.setUserAgent(userAgent);
            log.setIpAddress(ipAddress);
            logRepository.save(log);
        }
    }
}
```

## Критерии приемки

- ✅ API корректно отслеживает все типы уведомлений
- ✅ Аналитика каналов показывает точные метрики доставляемости
- ✅ Система retry автоматически повторяет неудачные отправки
- ✅ Tracking открытий и кликов работает для всех каналов
- ✅ Анализ проблем доставки выявляет основные причины ошибок
- ✅ Черный список предотвращает отправку на заблокированные контакты
- ✅ A/B тестирование шаблонов позволяет оптимизировать контент
- ✅ Экспорт содержит все данные для анализа эффективности
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для больших объемов уведомлений