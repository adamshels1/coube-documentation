# 03. REST API Endpoints

## Обзор

Полная документация REST API для биллинга с примерами запросов и ответов.

---

## 1. BillingController (для клиентов)

### GET /api/v1/billing/balance

**Назначение**: Получить текущий баланс.

**Авторизация**: JWT (текущий пользователь)

**Код**:
```java
@RestController
@RequestMapping("/api/v1/billing")
@RequiredArgsConstructor
@Slf4j
public class BillingController {
    
    private final BalanceService balanceService;
    private final AccountService accountService;
    private final TransactionRepository transactionRepository;
    private final InvoiceService invoiceService;
    
    @GetMapping("/balance")
    public ResponseEntity<BalanceDto> getBalance(@AuthenticationPrincipal UserDetails userDetails) {
        Long organizationId = getCurrentOrganizationId(userDetails);
        Account account = accountService.getAccountByOrganizationId(organizationId);
        BalanceDto balance = balanceService.getBalance(account.getId());
        return ResponseEntity.ok(balance);
    }
}
```

**Пример запроса**:
```bash
curl -X GET http://localhost:8080/api/v1/billing/balance \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

**Пример ответа**:
```json
{
  "accountId": 1,
  "balance": 150000.00,
  "reservedBalance": 10000.00,
  "availableBalance": 140000.00,
  "currency": "KZT",
  "subscriptionActive": true,
  "subscriptionAmount": 10000.00,
  "status": "active",
  "daysUntilBlocked": 420
}
```

---

### GET /api/v1/billing/transactions

**Назначение**: История операций.

**Параметры**:
- `page` (default: 0)
- `size` (default: 20)

**Код**:
```java
@GetMapping("/transactions")
public ResponseEntity<Page<TransactionDto>> getTransactions(
        @AuthenticationPrincipal UserDetails userDetails,
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size) {
    
    Long organizationId = getCurrentOrganizationId(userDetails);
    Account account = accountService.getAccountByOrganizationId(organizationId);
    
    Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
    Page<Transaction> transactions = transactionRepository.findByAccountId(account.getId(), pageable);
    
    Page<TransactionDto> dtos = transactions.map(this::mapToDto);
    return ResponseEntity.ok(dtos);
}

private TransactionDto mapToDto(Transaction t) {
    return TransactionDto.builder()
        .id(t.getId())
        .type(t.getType())
        .amount(t.getAmount())
        .balanceBefore(t.getBalanceBefore())
        .balanceAfter(t.getBalanceAfter())
        .description(t.getDescription())
        .createdAt(t.getCreatedAt())
        .build();
}
```

**Пример запроса**:
```bash
curl -X GET "http://localhost:8080/api/v1/billing/transactions?page=0&size=10" \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

**Пример ответа**:
```json
{
  "content": [
    {
      "id": 123,
      "type": "topup",
      "amount": 50000.00,
      "balanceBefore": 100000.00,
      "balanceAfter": 150000.00,
      "description": "Balance topup via invoice #INV-20250107-000001",
      "createdAt": "2025-01-07T10:30:00"
    },
    {
      "id": 122,
      "type": "commission_reserve",
      "amount": 0.00,
      "balanceBefore": 100000.00,
      "balanceAfter": 100000.00,
      "description": "Commission reserve 5% for transportation #789",
      "createdAt": "2025-01-06T15:20:00"
    }
  ],
  "totalElements": 45,
  "totalPages": 5,
  "number": 0,
  "size": 10
}
```

---

### POST /api/v1/billing/invoices/topup

**Назначение**: Создать счёт на пополнение баланса.

**Body**:
```json
{
  "amount": 50000.00
}
```

**Код**:
```java
@PostMapping("/invoices/topup")
public ResponseEntity<InvoiceDto> createTopupInvoice(
        @AuthenticationPrincipal UserDetails userDetails,
        @RequestBody @Valid TopupRequest request) {
    
    Long organizationId = getCurrentOrganizationId(userDetails);
    Account account = accountService.getAccountByOrganizationId(organizationId);
    
    Invoice invoice = invoiceService.createInvoice(account.getId(), request.getAmount());
    
    InvoiceDto dto = InvoiceDto.builder()
        .id(invoice.getId())
        .invoiceNumber(invoice.getInvoiceNumber())
        .amount(invoice.getAmount())
        .status(invoice.getStatus())
        .createdAt(invoice.getCreatedAt())
        .build();
    
    return ResponseEntity.ok(dto);
}
```

**Пример запроса**:
```bash
curl -X POST http://localhost:8080/api/v1/billing/invoices/topup \
  -H "Authorization: Bearer <JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"amount": 50000.00}'
```

**Пример ответа**:
```json
{
  "id": 15,
  "invoiceNumber": "INV-20250107-000015",
  "amount": 50000.00,
  "status": "pending",
  "createdAt": "2025-01-07T14:25:00"
}
```

---

### GET /api/v1/billing/invoices

**Назначение**: Список счетов.

**Код**:
```java
@GetMapping("/invoices")
public ResponseEntity<List<InvoiceDto>> getInvoices(@AuthenticationPrincipal UserDetails userDetails) {
    Long organizationId = getCurrentOrganizationId(userDetails);
    Account account = accountService.getAccountByOrganizationId(organizationId);
    
    List<Invoice> invoices = invoiceService.getInvoices(account.getId());
    List<InvoiceDto> dtos = invoices.stream()
        .map(i -> InvoiceDto.builder()
            .id(i.getId())
            .invoiceNumber(i.getInvoiceNumber())
            .amount(i.getAmount())
            .status(i.getStatus())
            .createdAt(i.getCreatedAt())
            .paidAt(i.getPaidAt())
            .build())
        .toList();
    
    return ResponseEntity.ok(dtos);
}
```

**Пример запроса**:
```bash
curl -X GET http://localhost:8080/api/v1/billing/invoices \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

**Пример ответа**:
```json
[
  {
    "id": 15,
    "invoiceNumber": "INV-20250107-000015",
    "amount": 50000.00,
    "status": "paid",
    "createdAt": "2025-01-07T14:25:00",
    "paidAt": "2025-01-07T15:30:00"
  },
  {
    "id": 14,
    "invoiceNumber": "INV-20250105-000014",
    "amount": 30000.00,
    "status": "pending",
    "createdAt": "2025-01-05T10:15:00",
    "paidAt": null
  }
]
```

---

## 2. BillingAdminController (для админов)

### POST /api/v1/admin/billing/payments/manual

**Назначение**: Ручное подтверждение оплаты.

**Авторизация**: @PreAuthorize("hasRole('ADMIN')")

**Body**:
```json
{
  "invoiceId": 15,
  "amount": 50000.00
}
```

**Код**:
```java
@RestController
@RequestMapping("/api/v1/admin/billing")
@RequiredArgsConstructor
@Slf4j
public class BillingAdminController {
    
    private final PaymentService paymentService;
    
    @PostMapping("/payments/manual")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<PaymentDto> recordManualPayment(
            @AuthenticationPrincipal UserDetails userDetails,
            @RequestBody @Valid ManualPaymentRequest request) {
        
        String adminUsername = userDetails.getUsername();
        
        Payment payment = paymentService.recordManualPayment(
            request.getInvoiceId(),
            request.getAmount(),
            adminUsername
        );
        
        PaymentDto dto = PaymentDto.builder()
            .id(payment.getId())
            .invoiceId(payment.getInvoiceId())
            .amount(payment.getAmount())
            .paymentMethod(payment.getPaymentMethod())
            .status(payment.getStatus())
            .createdAt(payment.getCreatedAt())
            .createdBy(payment.getCreatedBy())
            .build();
        
        return ResponseEntity.ok(dto);
    }
}
```

**Пример запроса**:
```bash
curl -X POST http://localhost:8080/api/v1/admin/billing/payments/manual \
  -H "Authorization: Bearer <ADMIN_JWT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "invoiceId": 15,
    "amount": 50000.00
  }'
```

**Пример ответа**:
```json
{
  "id": 42,
  "invoiceId": 15,
  "amount": 50000.00,
  "paymentMethod": "manual",
  "status": "success",
  "createdAt": "2025-01-07T15:30:00",
  "createdBy": "admin@coube.kz"
}
```

---

## 3. Internal API (для Applications модуля)

### POST /internal/billing/reservations

**Назначение**: Резервировать комиссию (вызывается из EventListener).

**Авторизация**: Internal (без JWT, только из backend)

**Body**:
```json
{
  "accountId": 456,
  "transportationId": 789,
  "amount": 5000.00
}
```

**Код**:
```java
@RestController
@RequestMapping("/internal/billing")
@RequiredArgsConstructor
@Slf4j
public class BillingInternalController {
    
    private final ReservationService reservationService;
    
    @PostMapping("/reservations")
    public ResponseEntity<ReservationDto> createReservation(@RequestBody @Valid CreateReservationRequest request) {
        Reservation reservation = reservationService.reserve(
            request.getAccountId(),
            request.getTransportationId(),
            request.getAmount()
        );
        
        ReservationDto dto = ReservationDto.builder()
            .id(reservation.getId())
            .accountId(reservation.getAccountId())
            .transportationId(reservation.getTransportationId())
            .amount(reservation.getAmount())
            .status(reservation.getStatus())
            .reservedAt(reservation.getReservedAt())
            .build();
        
        return ResponseEntity.ok(dto);
    }
    
    @PostMapping("/reservations/{id}/capture")
    public ResponseEntity<Void> captureReservation(@PathVariable Long id) {
        reservationService.capture(id);
        return ResponseEntity.ok().build();
    }
    
    @PostMapping("/reservations/{id}/release")
    public ResponseEntity<Void> releaseReservation(@PathVariable Long id) {
        reservationService.release(id);
        return ResponseEntity.ok().build();
    }
}
```

**НЕ ВЫСТАВЛЯТЬ НАРУЖУ!** Только для внутренних вызовов.

---

## DTO классы

### TopupRequest
```java
@Data
public class TopupRequest {
    @NotNull
    @DecimalMin("1.00")
    private BigDecimal amount;
}
```

### ManualPaymentRequest
```java
@Data
public class ManualPaymentRequest {
    @NotNull
    private Long invoiceId;
    
    @NotNull
    @DecimalMin("0.01")
    private BigDecimal amount;
}
```

### TransactionDto
```java
@Data
@Builder
public class TransactionDto {
    private Long id;
    private String type;
    private BigDecimal amount;
    private BigDecimal balanceBefore;
    private BigDecimal balanceAfter;
    private String description;
    private LocalDateTime createdAt;
}
```

### InvoiceDto
```java
@Data
@Builder
public class InvoiceDto {
    private Long id;
    private String invoiceNumber;
    private BigDecimal amount;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime paidAt;
}
```

### PaymentDto
```java
@Data
@Builder
public class PaymentDto {
    private Long id;
    private Long invoiceId;
    private BigDecimal amount;
    private String paymentMethod;
    private String status;
    private LocalDateTime createdAt;
    private String createdBy;
}
```

---

## Error Handling

```java
@ControllerAdvice
public class BillingExceptionHandler {
    
    @ExceptionHandler(InsufficientBalanceException.class)
    public ResponseEntity<ErrorResponse> handleInsufficientBalance(InsufficientBalanceException e) {
        ErrorResponse error = new ErrorResponse("INSUFFICIENT_BALANCE", e.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }
    
    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<ErrorResponse> handleIllegalArgument(IllegalArgumentException e) {
        ErrorResponse error = new ErrorResponse("INVALID_ARGUMENT", e.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }
    
    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<ErrorResponse> handleIllegalState(IllegalStateException e) {
        ErrorResponse error = new ErrorResponse("INVALID_STATE", e.getMessage());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(error);
    }
}

@Data
@AllArgsConstructor
class ErrorResponse {
    private String code;
    private String message;
}
```

---

## Swagger Documentation

```java
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Coube Billing API",
        version = "1.0",
        description = "API для управления балансом и подписками"
    )
)
public class SwaggerConfig {
}
```

**Аннотации для методов**:
```java
@Operation(summary = "Получить текущий баланс")
@ApiResponse(responseCode = "200", description = "Баланс получен")
@ApiResponse(responseCode = "401", description = "Не авторизован")
@GetMapping("/balance")
public ResponseEntity<BalanceDto> getBalance(...) { ... }
```

---

**Готово!** Все endpoints задокументированы.

**Следующий шаг**: `04-event-integration.md`
