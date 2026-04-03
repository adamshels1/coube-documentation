# Сессия — Страхование (03.04.2026)

## Где остановились

Eurasian починили `its_get_customer` (физик). Прогнали почти полный флоу с реальной CMS подписью через NCALayer.

Зависли на `docs_get_signed` — Eurasian обрабатывает но не завершает (проблема 1С на их стороне).

---

## Активные inst_id

| Процесс | inst_id | Статус |
|---|---|---|
| `its_get_customer_ul` (компания) | `16037325` | ✅ step_status: 10 — данные есть |
| `its_get_customer` (физик) | `16037635` | ✅ step_status: 10 — данные есть |
| `its_conclusion_cargo` (текущий тест) | `16037637` | ⚠️ завис на docs_get_signed |

---

## Что нужно сделать когда продолжим

1. **Проверить `inst_id=16037637`** — завершился ли `docs_get_signed` (step_status: 10 или 9)
2. **Если 9** — перезапустить `its_conclusion_cargo` с теми же данными и прогнать заново с NCALayer
3. **Если 10** — посмотреть что пришло в `params` и обновить документацию
4. **Понедельник 06.04** — Eurasian смотрят `its_get_customer_ul` (зависает в 1С)

---

## Команды для проверки статуса

```bash
# Проверить docs_get_signed
curl -s -u "coube:TheEurasiaCoube87@37#4" \
  "https://gates-test.theeurasia.kz/api/bpm/process/get-status?inst_id=16037637" | \
  python3 -c "
import sys, json
d = json.load(sys.stdin)
print('step_code:', d.get('step_code'))
print('step_status:', d.get('step_status'))
print('step_info:', d.get('step_info'))
print('params:', d.get('params'))
"
```

---

## Credentials

| | |
|---|---|
| BPM Test URL | `https://gates-test.theeurasia.kz/api/bpm` |
| Логин | `coube` |
| Пароль | `TheEurasiaCoube87@37#4` |
| Тестовый BIN | `221040021025` |
| Тестовый ИИН физика | `930419301377` |
| Телефон физика | `77478777626` |
