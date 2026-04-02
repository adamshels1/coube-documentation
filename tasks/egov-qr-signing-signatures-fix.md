# Задача: Исправить добавление подписей и CMS файлов при подписании через eGov (QR/Mobile)

**Дата создания:** 2026-04-01  
**Приоритет:** High  
**Компонент:** Backend (coube-backend), Frontend (coube-frontend)  
**Статус:** Open

---

## Описание проблемы

В проекте существуют два способа подписания документов:

1. **ЭЦП подписание** (через веб, выбор ключа) — работает корректно:
   - Подписи сохраняются на документах
   - В архиве формируются CMS файлы

2. **eGov подписание** (через QR код и мобильное приложение) — подписание происходит, НО:
   - ❌ Подписи **не добавляются** в документы (не сохраняются в сущности)
   - ❌ CMS файлы **не попадают** в архив

---

## Анализ текущей реализации

### Как ЭЦП подписание сохраняет подписи

**Для контрактов** (`ContractProcessService.java`):
1. Создаётся подпись через `signatureService.createSignatureWithTwoSigns()`
2. Прикрепляется к контракту: `contract.setSignatureWithTwoSigns(signature)`
3. Сохраняется: `contractService.saveContract(contract)`

**Для соглашений (Agreement)** (`AgreementExecutorService.java`):
1. Создаётся подпись через `signatureService.createSignatureWithOneSign()`
2. Прикрепляется: `agreementExecutor.setCustomerSignature(signature)`
3. Сохраняется: `agreementExecutorRepository.save(agreementExecutor)`

### Как формируется архив с CMS файлами

Файл: `SignatureService.java`, метод `createSignedDocumentArchive()`:

```java
// Итерируется по подписям документа
for (int i = 0; i < document.getSignatures().size(); i++) {
    Signature signature = document.getSignatures().get(i);
    FileMetaInfo cmsFileMetaInfo = signature.getSignedFile();
    // Если CMS файл есть — добавляет в архив
    zipArchiveUtil.addFileToZip(zos, cmsStream, "Подписи/" + cmsFileName);
}
```

**Вывод:** Архив строится на основе `document.getSignatures()`. Если подписи не привязаны к документу в БД — CMS файлов в архиве не будет.

### Адаптер контракта (`ContractDocumentAdapter.java`, строки ~40-55)

```java
public List<Signature> getSignatures() {
    List<Signature> signatures = new ArrayList<>();
    if (contract.getSignatureWithOneSign() != null) {
        signatures.add(contract.getSignatureWithOneSign());
    }
    if (contract.getSignatureWithTwoSigns() != null) {
        signatures.add(contract.getSignatureWithTwoSigns());
    }
    return signatures;
}
```

---

## Выявленные проблемы

### Проблема 1: Отсутствует обработчик типа `agreement` в eGov сервисе

**Файл:** `coube-backend/.../egov/service/EgovDocumentService.java`

Метод `putSignedDocuments()` обрабатывает только:
- `factoring-agreement` → сохраняет в `FactoringAgreement`
- `contract` → сохраняет в `Contract`

**Отсутствует:** кейс для `agreement` / `AgreementExecutor`, который должен вызывать `agreementExecutor.setCustomerSignature(signature)`.

### Проблема 2: Возможная проблема с транзакцией при eGov подписании контрактов

**Файл:** `coube-backend/.../applications/service/contract/ContractProcessService.java`, метод `signContractSecondViaEgov()` (~строка 503-543)

Подпись создаётся, но из-за разницы в транзакционных границах (eGov callback обрабатывается асинхронно) подпись может не быть видна адаптеру при следующем запросе архива.

**Нужно проверить:** корректно ли `contract.setSignatureWithTwoSigns(signature)` и `contractService.saveContract(contract)` выполняются в одной транзакции и flush происходит до ответа.

### Проблема 3: Неправильный `documentType` на фронтенде

**Файл:** `coube-frontend/.../ContractSigningFlow/ContractSigningFlow.vue`, строка ~66

При QR подписании соглашений может передаваться `documentType: 'agreement'`, но бэкенд не имеет соответствующего обработчика. Нужно согласовать типы между фронтом и бэком.

---

## Что нужно сделать

### Backend задачи

#### 1. Добавить обработку `agreement` типа в `EgovDocumentService`

В методах `getDocument()` и `putSignedDocuments()` добавить кейс для обычных соглашений (`AgreementExecutor`):

```java
case "agreement":
    // getDocument: вернуть PDF соглашения
    // putSignedDocuments: agreementExecutor.setCustomerSignature(signature)
    //                     agreementExecutorRepository.save(agreementExecutor)
```

**Файл:** `coube-backend/src/main/java/kz/coube/backend/egov/service/EgovDocumentService.java`

#### 2. Проверить и исправить транзакционность для контрактов

В методе `signContractSecondViaEgov()`:
- Убедиться, что сохранение контракта (`contractService.saveContract`) происходит с flush
- Проверить, что `signature.getSignedFile()` содержит CMS файл (не null) после eGov подписания

**Файл:** `coube-backend/src/main/java/kz/coube/backend/applications/service/contract/ContractProcessService.java`

#### 3. Добавить `agreement` в check constraint БД

Аналогично тому, как был добавлен `contract` (коммит `73b57a12`) — проверить constraint таблицы `egov_sign_sessions` на поле `document_type`.

**Файл:** Миграция Flyway в `coube-documentation/migration-db/`

#### 4. Проверить сохранение CMS файла в `Signature`

При eGov подписании убедиться, что в объекте `Signature` заполняется поле `signedFile` (FileMetaInfo с CMS контентом). Это критично для архива.

**Файл:** `coube-backend/src/main/java/kz/coube/backend/signature/SignatureService.java`

### Frontend задачи

#### 5. Проверить и унифицировать `documentType` для QR подписания

Убедиться, что при вызове `/v1/egov/sign/init` передаётся корректный `documentType`, который обрабатывается бэкендом.

**Файл:** `coube-frontend/src/components/ContractSigningFlow/ContractSigningFlow.vue`

---

## Последовательность воспроизведения бага

1. Открыть контракт/соглашение в web-интерфейсе
2. Выбрать подписание через QR (eGov Mobile)
3. Отсканировать QR код мобильным приложением
4. Подписать документ в eGov Mobile
5. Вернуться на страницу документа
6. **Ожидаемое поведение:** В документе отображаются подписи, в архиве есть CMS файлы
7. **Фактическое поведение:** Подписи не отображаются, архив без CMS файлов

---

## Связанные файлы

| Файл | Назначение |
|------|-----------|
| `coube-backend/.../egov/service/EgovDocumentService.java` | Основной сервис обработки eGov подписания |
| `coube-backend/.../egov/service/EgovSignSessionService.java` | Управление сессиями eGov подписания |
| `coube-backend/.../signature/SignatureService.java` | Создание подписей и архивов |
| `coube-backend/.../signature/adapter/ContractDocumentAdapter.java` | Адаптер для получения подписей контракта |
| `coube-backend/.../applications/service/contract/ContractProcessService.java` | Обработка подписания контрактов (в т.ч. через eGov) |
| `coube-backend/.../agreement/service/AgreementExecutorService.java` | Обработка подписания соглашений (ЭЦП) |
| `coube-frontend/.../ContractSigningFlow/ContractSigningFlow.vue` | UI компонент QR подписания |

---

## Связанные коммиты (последние изменения по eGov)

| Коммит | Описание | Дата |
|--------|----------|------|
| `1c89f2d7` | fix: send original PDF (not CMS) to eGov for contract signing | 2026-03-31 |
| `73b57a12` | fix: add contract to egov_sign_sessions document_type check constraint | 2026-03-31 |
| `707ae73d` | feat: add contract document type support for eGov Mobile signing | 2026-03-31 |
| `c61dbca` | feat: add factoring onboarding and fix EDS contract signing via eGov Mobile (mobile) | 2026-03-31 |

---

## Критерии приёмки

- [ ] После eGov/QR подписания контракта — подпись отображается в документе
- [ ] После eGov/QR подписания соглашения — подпись отображается в документе
- [ ] Скачиваемый архив содержит CMS файлы подписей (как при ЭЦП подписании)
- [ ] ЭЦП подписание продолжает работать без регрессий
- [ ] Тест: подписать один и тот же тип документа через ЭЦП и через eGov — результат должен быть идентичным
