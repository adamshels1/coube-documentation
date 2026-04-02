# Страхование — Следующий шаг

## Где остановились

Тестируем BPM-процесс `its_conclusion_cargo` (используем BPM, не SOAP).

Всё работает до последнего шага:

```
its_get_customer_ul  → ✅ step_status: 10
its_get_customer     → ✅ step_status: 10  
docs_get_confirm     → ✅ step_status: 0  (PDF получены)
docs_get_signed      → ❌ step_status: 9  (ошибка)
```

## Ошибка

```json
{
  "critical_error": "Неправильная схема использования сервиса, используйте методы микросервиса",
  "system_id": "Не передан обязательный параметр system_id",
  "contract_id": "Не передан обязательный параметр contract_id"
}
```

## Что нужно от Евразии

Они должны были ответить на вопрос:

> `docs_get_signed` требует `system_id` и `contract_id`. Что это такое и где их взять?

## Что делать когда ответят

1. Если `system_id` — это от signing-микросервиса:
   - Запросить документацию на этот микросервис (endpoint, формат запроса)
   - Реализовать вызов перед `docs_get_signed`

2. Если `contract_id` — это номер договора:
   - Уточнить, нужно ли сначала вызвать SOAP `CreateNewDocument` чтобы получить `PolicyNumber`
   - Или это внутренний ID процесса

3. После получения обоих параметров — дотестировать `docs_get_signed` до `step_status: 10`

## Тестовые данные (stage)

| Параметр | Значение |
|---|---|
| BPM URL | `https://gates-test.theeurasia.kz/api/bpm` |
| BPM логин | `coube` |
| BPM пароль | `TheEurasiaCoube87@37#4` |
| SOAP URL | `https://wstest.theeurasia.kz:2190/ws/wsNovelty.1cws` |
| SOAP логин | `Novelty` |
| SOAP пароль | `noveltytest` |
| Тестовый BIN | `221040021025` |
| agent-iin | `871103300964` |

## Формат вызова docs_get_signed (как должно быть)

```bash
curl -s -u "coube:TheEurasiaCoube87@37#4" \
  -X POST "https://gates-test.theeurasia.kz/api/bpm/process/set-param" \
  -H "Content-Type: application/json" \
  -d '{
    "inst_id": "<из init>",
    "step_code": "docs_get_signed",
    "params": {
      "success": 1,
      "system_id": "<???  от signing-микросервиса>",
      "contract_id": "<??? что это>",
      "application": "<base64 подписанный PDF>",
      "contract": "<base64 подписанный PDF>",
      "invoice": ""
    }
  }'
```

## Полная документация

`coube-documentation/docs/Страхование/insurance-api-test-report.md`
