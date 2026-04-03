# Coube × Eurasian Insurance — Полная картина интеграции

## Договорённость

Eurasian генерирует PDF документы → отдаёт Coube → Coube подписывает через NCALayer (CMS подпись) → возвращает подписанные PDF → Eurasian сохраняет договор.

---

## Полный флоу

```
Coube                                    Eurasian BPM
─────────────────────────────────────────────────────

1. its_get_customer_ul
   → BIN компании, реквизиты, владельцы (без leader!)
                                         ← Проверка ГБД/БМГ
   ← system_data компании (сохранить для шага 3)

2. its_get_customer
   → ИИН + телефон физлица
                                         ← Проверка БМГ
   → set-param: { kdp: 5 }
                                         ← Сохранение в 1С
   ← system_data физлица (сохранить для шага 3)

3. its_conclusion_cargo
   → contract_id (наш ID)
   → contract { date_from, date_to, territory, departure_station,
                destination_station, method, total_premium, tariff,
                signatory_iin, reason_type, reason_date, reason_number }
   → client = system_data из шага 1
   → insureds = [system_data из шага 1]
   → beneficiaries = [system_data из шага 2]
   → cargo [{ cargotype, cargoname, cargoweight, cargounit,
               cargovolume, cargoquantity, cargopackaging,
               transportmethod, vehiclebodytype, capacity,
               hassecurity, losses, sum, premium }]
                                         ← Генерация документов
   ← docs_get_confirm: PDF Заявление + PDF Договор (base64)

4. Показываем PDF пользователю
   Пользователь подписывает через NCALayer → CMS подпись
   → set-param: { confirm: 1 }

5. docs_get_signed
   → { success: 1, application: base64_cms, contract: base64_cms, invoice: "" }
                                         ← Eurasian сохраняет договор в 1С
   ← step_status: 10 ✅
```

---

## Статус тестирования (03.04.2026)

| Шаг | Статус | Примечание |
|-----|--------|------------|
| `its_get_customer_ul` | ⚠️ | Зависает в 1С — Eurasian смотрят 06.04 |
| `its_get_customer` + `kdp_get_type` | ✅ | Работает полностью |
| `its_conclusion_cargo` | ✅ | Работает |
| `docs_get_confirm` + `{ confirm: 1 }` | ✅ | Работает |
| `docs_get_signed` с реальным CMS PDF | ⚠️ | Принимает, зависает в 1С |
| Финальный `step_status: 10` | ❓ | Не дошли |

---

## Важные детали API

| Параметр | Значение |
|---|---|
| BPM Test URL | `https://gates-test.theeurasia.kz/api/bpm` |
| Логин | `coube` |
| Пароль | `TheEurasiaCoube87@37#4` |
| `leader` в `its_get_customer_ul` | НЕ передавать — ошибка `leader_short` |
| `docs_get_confirm` подтверждение | `{ confirm: 1 }` — не `success: 1` |
| `docs_get_signed` `system_id` | НЕ нужен |
| `docs_get_signed` `invoice` | Пустая строка `""` если нет |
| PDF в `docs_get_signed` | Должен быть подписан через NCALayer (CMS) |

---

## Ждём от Eurasian

1. Починить `customer_send_save1c` для юрлиц (06.04.2026)
2. Починить зависание `docs_get_signed` в 1С
3. Что приходит в `params` при финальном `step_status: 10`
