# Отчеты заказчика - Сравнение исполнителей

## Описание задачи
Реализовать API для отчета "Сравнение исполнителей" с комплексным анализом производительности, качества услуг, стоимости и рейтингом поставщиков логистических услуг.

## Frontend UI референс
- Компонент: `ExecutorComparisonReport.vue` (существующий)
- Фильтры: исполнители, период, тип груза, географическое направление
- Метрики: стоимость, качество, скорость, надежность, общий рейтинг
- Сравнительные таблицы: мультикритериальное сравнение исполнителей
- Графики: производительность, тренды, бенчмаркинг

## Эндпоинты для реализации

### 1. GET `/api/reports/executor-comparison/analysis`
Получение сравнительного анализа исполнителей

**Параметры запроса:**
```json
{
  "executorIds": ["number"], // массив ID исполнителей для сравнения
  "cargoType": "string (optional)",
  "routeDirection": "string (optional)", // north, south, east, west
  "dateFrom": "string (optional)", // ISO date
  "dateTo": "string (optional)", // ISO date
  "comparisonMetrics": ["string"] // cost, quality, speed, reliability
}
```

**Ответ:**
```json
{
  "executors": [
    {
      "executorId": "number",
      "executorName": "string",
      "executorBin": "string",
      "contactInfo": {
        "phone": "string",
        "email": "string",
        "address": "string"
      },
      "metrics": {
        "cost": {
          "avgCostPerTon": "number",
          "avgCostPerKm": "number",
          "totalCost": "number",
          "costRank": "number", // место по стоимости
          "costTrend": "string" // increasing, stable, decreasing
        },
        "quality": {
          "avgRating": "number", // 1-5
          "qualityScore": "number", // 0-100
          "customerSatisfaction": "number", // процент
          "qualityRank": "number",
          "qualityTrend": "string"
        },
        "speed": {
          "avgDeliveryTime": "number", // часы
          "onTimeDeliveryRate": "number", // процент
          "avgDelayHours": "number",
          "speedRank": "number",
          "speedTrend": "string"
        },
        "reliability": {
          "completionRate": "number", // процент
          "issueRate": "number", // процент перевозок с проблемами
          "cancellationRate": "number", // процент отмен
          "reliabilityRank": "number",
          "reliabilityTrend": "string"
        },
        "overall": {
          "totalScore": "number", // 0-100
          "overallRank": "number",
          "recommendation": "string", // preferred, acceptable, not_recommended
          "strengths": ["string"],
          "weaknesses": ["string"]
        }
      },
      "statistics": {
        "totalTransports": "number",
        "activeContracts": "number",
        "totalRevenue": "number",
        "avgTransportValue": "number",
        "marketShare": "number", // процент от общего объема
        "cooperationDuration": "number" // месяцы
      }
    }
  ],
  "comparison": {
    "bestPerformer": {
      "executorName": "string",
      "strongestMetric": "string",
      "score": "number"
    },
    "mostCostEffective": {
      "executorName": "string", 
      "avgCostPerTon": "number",
      "savings": "number" // экономия по сравнению со средним
    },
    "mostReliable": {
      "executorName": "string",
      "reliabilityScore": "number",
      "onTimeRate": "number"
    },
    "benchmark": {
      "avgCostPerTon": "number",
      "avgQualityRating": "number",
      "avgOnTimeRate": "number",
      "avgReliabilityScore": "number"
    }
  }
}
```

### 2. GET `/api/reports/executor-comparison/scoring`
Получение детальной системы скоринга исполнителей

**Ответ:**
```json
{
  "scoringModel": {
    "weights": {
      "cost": "number", // вес критерия стоимости
      "quality": "number", // вес критерия качества
      "speed": "number", // вес критерия скорости
      "reliability": "number" // вес критерия надежности
    },
    "methodology": "string" // описание методологии расчета
  },
  "executorScores": [
    {
      "executorId": "number",
      "executorName": "string",
      "scores": {
        "costScore": "number", // 0-100
        "qualityScore": "number", // 0-100
        "speedScore": "number", // 0-100
        "reliabilityScore": "number", // 0-100
        "weightedTotal": "number", // взвешенная сумма
        "normalizedScore": "number" // нормализованный балл 0-100
      },
      "ranking": {
        "overallRank": "number",
        "costRank": "number",
        "qualityRank": "number",
        "speedRank": "number",
        "reliabilityRank": "number"
      },
      "scoreHistory": [
        {
          "month": "string",
          "totalScore": "number",
          "costScore": "number",
          "qualityScore": "number",
          "speedScore": "number",
          "reliabilityScore": "number"
        }
      ]
    }
  ]
}
```

### 3. GET `/api/reports/executor-comparison/financial`
Получение финансового анализа исполнителей

**Ответ:**
```json
{
  "financialAnalysis": [
    {
      "executorId": "number",
      "executorName": "string",
      "financial": {
        "totalRevenue": "number",
        "avgTransactionValue": "number",
        "paymentTerms": "number", // средний срок оплаты в днях
        "creditRating": "string", // AAA, AA, A, BBB, etc.
        "paymentHistory": {
          "onTimePayments": "number", // процент
          "avgPaymentDelay": "number", // дни
          "totalDebt": "number",
          "overdueDebt": "number"
        },
        "pricing": {
          "competitiveness": "number", // 0-100
          "priceStability": "number", // 0-100
          "discountLevel": "number", // процент скидки
          "additionalFees": ["string"] // доп. сборы
        },
        "riskAssessment": {
          "financialRisk": "string", // low, medium, high
          "operationalRisk": "string",
          "reputationalRisk": "string",
          "overallRisk": "string"
        }
      }
    }
  ],
  "marketAnalysis": {
    "averageRates": {
      "avgCostPerTon": "number",
      "avgCostPerKm": "number"
    },
    "priceRanges": {
      "minCostPerTon": "number",
      "maxCostPerTon": "number",
      "medianCostPerTon": "number"
    },
    "competitivePositioning": [
      {
        "executorName": "string",
        "pricePosition": "string", // premium, competitive, budget
        "valueProposition": "string"
      }
    ]
  }
}
```

### 4. GET `/api/reports/executor-comparison/charts`
Получение данных для сравнительных графиков

**Ответ:**
```json
{
  "radarChart": {
    "executors": ["string"],
    "metrics": ["Стоимость", "Качество", "Скорость", "Надежность"],
    "data": [
      {
        "executor": "string",
        "values": ["number"] // баллы по каждой метрике
      }
    ]
  },
  "performanceTrends": {
    "months": ["string"],
    "executors": [
      {
        "name": "string",
        "scores": ["number"] // баллы по месяцам
      }
    ]
  },
  "marketShare": {
    "executors": ["string"],
    "transportCount": ["number"],
    "revenue": ["number"],
    "marketShare": ["number"]
  },
  "benchmarkComparison": {
    "metrics": ["string"],
    "industryAverage": ["number"],
    "topPerformer": ["number"],
    "yourExecutors": [
      {
        "name": "string",
        "values": ["number"]
      }
    ]
  }
}
```

### 5. GET `/api/reports/executor-comparison/recommendations`
Получение рекомендаций по выбору исполнителей

**Ответ:**
```json
{
  "recommendations": [
    {
      "scenario": "string", // cost_optimization, quality_focus, speed_priority
      "description": "string",
      "recommendedExecutors": [
        {
          "executorName": "string",
          "reason": "string",
          "expectedBenefits": ["string"],
          "potentialRisks": ["string"],
          "suitabilityScore": "number" // 0-100
        }
      ]
    }
  ],
  "optimization": {
    "currentPortfolio": {
      "totalExecutors": "number",
      "avgScore": "number",
      "diversificationIndex": "number", // 0-100
      "riskLevel": "string"
    },
    "suggestedChanges": [
      {
        "action": "string", // add, remove, increase_volume, decrease_volume
        "executorName": "string",
        "reasoning": "string",
        "expectedImprovement": "number", // процент
        "implementation": "string" // immediate, gradual, trial
      }
    ],
    "potentialSavings": "number", // экономия в тенге
    "riskMitigation": ["string"]
  }
}
```

### 6. GET `/api/reports/executor-comparison/export`
Экспорт сравнительного анализа исполнителей в Excel

**Параметры:** те же что и для основного эндпоинта

**Ответ:** Excel файл с детальным сравнением

## SQL запросы (базовая логика)

### Основной запрос для сравнения исполнителей
```sql
WITH executor_metrics AS (
    SELECT 
        eo.id as executorId,
        eo.organization_name as executorName,
        eo.bin as executorBin,
        eo.phone,
        eo.email,
        eo.address,
        
        -- Метрики стоимости
        COUNT(t.id) as totalTransports,
        AVG(tc.cost / NULLIF(t.cargo_weight, 0)) as avgCostPerTon,
        AVG(tc.cost / NULLIF(
            ST_Distance(
                ST_MakePoint(cl_from.longitude::float, cl_from.latitude::float)::geography,
                ST_MakePoint(cl_to.longitude::float, cl_to.latitude::float)::geography
            ) / 1000, 0
        )) as avgCostPerKm,
        SUM(tc.cost) as totalCost,
        
        -- Метрики качества  
        AVG(COALESCE(qr.avg_rating, 0)) as avgRating,
        AVG(COALESCE(cs.satisfaction_score, 0)) as customerSatisfaction,
        
        -- Метрики скорости
        AVG(EXTRACT(EPOCH FROM (t.actual_delivery_date - t.actual_start_date))/3600) as avgDeliveryTime,
        ROUND((COUNT(CASE WHEN t.actual_delivery_date <= t.planned_delivery_date THEN 1 END)::float / COUNT(t.id)) * 100, 1) as onTimeDeliveryRate,
        AVG(CASE 
            WHEN t.actual_delivery_date > t.planned_delivery_date 
            THEN EXTRACT(EPOCH FROM (t.actual_delivery_date - t.planned_delivery_date))/3600
            ELSE 0
        END) as avgDelayHours,
        
        -- Метрики надежности
        ROUND((COUNT(CASE WHEN t.status = 'COMPLETED' THEN 1 END)::float / COUNT(t.id)) * 100, 1) as completionRate,
        ROUND((COUNT(ti.transportation_id)::float / COUNT(t.id)) * 100, 1) as issueRate,
        ROUND((COUNT(CASE WHEN t.status = 'CANCELLED' THEN 1 END)::float / COUNT(t.id)) * 100, 1) as cancellationRate,
        
        -- Дополнительная статистика
        COUNT(DISTINCT a.id) as activeContracts,
        AVG(tc.cost) as avgTransportValue,
        MIN(t.created_at) as firstCooperation
        
    FROM user.organization eo
        LEFT JOIN applications.transportation_cost tc ON eo.id = tc.executor_organization_id
        LEFT JOIN applications.transportation t ON tc.transportation_id = t.id
        LEFT JOIN applications.cargo_loading cl_from ON t.id = cl_from.transportation_id 
            AND cl_from.loading_type = 'LOADING'
        LEFT JOIN applications.cargo_loading cl_to ON t.id = cl_to.transportation_id 
            AND cl_to.loading_type = 'UNLOADING'
        LEFT JOIN (
            SELECT transportation_id, AVG(rating) as avg_rating
            FROM transportation.quality_rating 
            GROUP BY transportation_id
        ) qr ON t.id = qr.transportation_id
        LEFT JOIN (
            SELECT executor_organization_id, AVG(satisfaction_score) as satisfaction_score
            FROM executor.customer_satisfaction
            GROUP BY executor_organization_id
        ) cs ON eo.id = cs.executor_organization_id
        LEFT JOIN transportation.transport_issue ti ON t.id = ti.transportation_id
        LEFT JOIN agreement.agreement a ON t.agreement_id = a.id AND a.status = 'ACTIVE'
    WHERE t.organization_id = $organizationId
        AND ($executorIds IS NULL OR eo.id = ANY($executorIds))
        AND ($cargoType IS NULL OR t.cargo_type_id IN (
            SELECT id FROM dictionaries.cargo_type WHERE cargo_type_name = $cargoType
        ))
        AND ($dateFrom IS NULL OR t.created_at >= $dateFrom)
        AND ($dateTo IS NULL OR t.created_at <= $dateTo)
    GROUP BY eo.id, eo.organization_name, eo.bin, eo.phone, eo.email, eo.address
    HAVING COUNT(t.id) > 0
),
scoring AS (
    SELECT 
        *,
        -- Нормализация метрик в баллы 0-100
        CASE 
            WHEN avgCostPerTon > 0 THEN 
                GREATEST(0, 100 - ((avgCostPerTon - MIN(avgCostPerTon) OVER()) / 
                                   NULLIF(MAX(avgCostPerTon) OVER() - MIN(avgCostPerTon) OVER(), 0)) * 100)
            ELSE 0
        END as costScore,
        
        (avgRating / 5.0) * 100 as qualityScore,
        
        CASE 
            WHEN avgDeliveryTime > 0 THEN 
                GREATEST(0, 100 - ((avgDeliveryTime - MIN(avgDeliveryTime) OVER()) / 
                                   NULLIF(MAX(avgDeliveryTime) OVER() - MIN(avgDeliveryTime) OVER(), 0)) * 100)
            ELSE 0
        END as speedScore,
        
        (completionRate * 0.5 + (100 - issueRate) * 0.3 + (100 - cancellationRate) * 0.2) as reliabilityScore
        
    FROM executor_metrics
),
final_ranking AS (
    SELECT 
        *,
        -- Взвешенная оценка (веса можно настраивать)
        (costScore * 0.25 + qualityScore * 0.3 + speedScore * 0.25 + reliabilityScore * 0.2) as weightedTotal,
        
        -- Ранжирование
        RANK() OVER (ORDER BY (costScore * 0.25 + qualityScore * 0.3 + speedScore * 0.25 + reliabilityScore * 0.2) DESC) as overallRank,
        RANK() OVER (ORDER BY costScore DESC) as costRank,
        RANK() OVER (ORDER BY qualityScore DESC) as qualityRank,
        RANK() OVER (ORDER BY speedScore DESC) as speedRank,
        RANK() OVER (ORDER BY reliabilityScore DESC) as reliabilityRank,
        
        -- Рекомендации
        CASE 
            WHEN (costScore * 0.25 + qualityScore * 0.3 + speedScore * 0.25 + reliabilityScore * 0.2) >= 80 THEN 'preferred'
            WHEN (costScore * 0.25 + qualityScore * 0.3 + speedScore * 0.25 + reliabilityScore * 0.2) >= 60 THEN 'acceptable'
            ELSE 'not_recommended'
        END as recommendation
        
    FROM scoring
)
SELECT * FROM final_ranking
ORDER BY overallRank;
```

### Запрос для финансового анализа
```sql
SELECT 
    eo.id as executorId,
    eo.organization_name as executorName,
    
    -- Финансовые метрики
    SUM(tc.cost) as totalRevenue,
    AVG(tc.cost) as avgTransactionValue,
    
    -- Платежная история
    AVG(CASE 
        WHEN p.paid_at IS NOT NULL AND p.due_date IS NOT NULL
        THEN EXTRACT(DAYS FROM (p.paid_at - p.due_date))
        ELSE NULL
    END) as avgPaymentDelay,
    ROUND((COUNT(CASE WHEN p.paid_at <= p.due_date THEN 1 END)::float / 
           NULLIF(COUNT(p.id), 0)) * 100, 1) as onTimePaymentRate,
    
    -- Задолженность
    SUM(CASE WHEN p.payment_status != 'paid' THEN p.amount ELSE 0 END) as totalDebt,
    SUM(CASE WHEN p.payment_status != 'paid' AND p.due_date < NOW() THEN p.amount ELSE 0 END) as overdueDebt,
    
    -- Ценовая конкурентоспособность
    CASE 
        WHEN AVG(tc.cost / NULLIF(t.cargo_weight, 0)) <= 
             (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tc2.cost / NULLIF(t2.cargo_weight, 0))
              FROM applications.transportation_cost tc2
                  LEFT JOIN applications.transportation t2 ON tc2.transportation_id = t2.id
              WHERE t2.organization_id = $organizationId)
        THEN 100
        WHEN AVG(tc.cost / NULLIF(t.cargo_weight, 0)) <= 
             (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tc2.cost / NULLIF(t2.cargo_weight, 0))
              FROM applications.transportation_cost tc2
                  LEFT JOIN applications.transportation t2 ON tc2.transportation_id = t2.id
              WHERE t2.organization_id = $organizationId)
        THEN 75
        WHEN AVG(tc.cost / NULLIF(t.cargo_weight, 0)) <= 
             (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tc2.cost / NULLIF(t2.cargo_weight, 0))
              FROM applications.transportation_cost tc2
                  LEFT JOIN applications.transportation t2 ON tc2.transportation_id = t2.id
              WHERE t2.organization_id = $organizationId)
        THEN 50
        ELSE 25
    END as competitiveness,
    
    -- Кредитный рейтинг (упрощенная логика)
    CASE 
        WHEN AVG(CASE WHEN p.paid_at <= p.due_date THEN 1 ELSE 0 END) >= 0.95 
             AND SUM(CASE WHEN p.payment_status != 'paid' AND p.due_date < NOW() THEN p.amount ELSE 0 END) = 0
        THEN 'AAA'
        WHEN AVG(CASE WHEN p.paid_at <= p.due_date THEN 1 ELSE 0 END) >= 0.90 THEN 'AA'
        WHEN AVG(CASE WHEN p.paid_at <= p.due_date THEN 1 ELSE 0 END) >= 0.80 THEN 'A'
        WHEN AVG(CASE WHEN p.paid_at <= p.due_date THEN 1 ELSE 0 END) >= 0.70 THEN 'BBB'
        WHEN AVG(CASE WHEN p.paid_at <= p.due_date THEN 1 ELSE 0 END) >= 0.60 THEN 'BB'
        ELSE 'B'
    END as creditRating
    
FROM user.organization eo
    LEFT JOIN applications.transportation_cost tc ON eo.id = tc.executor_organization_id
    LEFT JOIN applications.transportation t ON tc.transportation_id = t.id
    LEFT JOIN invoice.invoice i ON t.id = i.transportation_id
    LEFT JOIN finance.payment p ON i.id = p.invoice_id
WHERE t.organization_id = $organizationId
    AND t.created_at >= $dateFrom
    AND t.created_at <= $dateTo
GROUP BY eo.id, eo.organization_name
HAVING COUNT(t.id) > 0;
```

## Необходимые таблицы БД

### `executor.customer_satisfaction` - удовлетворенность клиентов
```sql
CREATE SCHEMA IF NOT EXISTS executor;

CREATE TABLE executor.customer_satisfaction (
    id BIGSERIAL PRIMARY KEY,
    customer_organization_id BIGINT REFERENCES user.organization(id),
    executor_organization_id BIGINT REFERENCES user.organization(id),
    transportation_id BIGINT REFERENCES applications.transportation(id),
    satisfaction_score INTEGER CHECK (satisfaction_score BETWEEN 1 AND 5),
    feedback_text TEXT,
    would_recommend BOOLEAN,
    improvement_suggestions TEXT,
    survey_date DATE DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);
```

### `executor.performance_history` - история производительности
```sql
CREATE TABLE executor.performance_history (
    id BIGSERIAL PRIMARY KEY,
    executor_organization_id BIGINT REFERENCES user.organization(id),
    customer_organization_id BIGINT REFERENCES user.organization(id),
    period_month DATE NOT NULL, -- первое число месяца
    total_transports INTEGER DEFAULT 0,
    cost_score DECIMAL(5,2),
    quality_score DECIMAL(5,2),
    speed_score DECIMAL(5,2),
    reliability_score DECIMAL(5,2),
    overall_score DECIMAL(5,2),
    rank_position INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(executor_organization_id, customer_organization_id, period_month)
);
```

## Техническая реализация

1. Создать схему `executor` для новых таблиц
2. Создать контроллер `ExecutorComparisonReportController`
3. Создать сервис `ExecutorComparisonReportService`
4. Реализовать многокритериальную систему оценки
5. Добавить алгоритмы машинного обучения для прогнозирования
6. Создать систему бенчмаркинга
7. Реализовать автоматические рекомендации
8. Добавить периодический расчет рейтингов

## Критерии приемки

- ✅ API корректно сравнивает исполнителей по всем метрикам
- ✅ Система скоринга работает с настраиваемыми весами
- ✅ Ранжирование исполнителей точное и обоснованное
- ✅ Финансовый анализ включает все ключевые показатели
- ✅ Рекомендации генерируются на основе данных
- ✅ Бенчмаркинг показывает позиции относительно рынка
- ✅ Экспорт содержит полное сравнение и рекомендации
- ✅ API работает только для авторизованных пользователей
- ✅ Производительность оптимизирована для сравнения множества исполнителей