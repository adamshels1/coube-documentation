# 02. Реализация сервисов (Services)

## Обзор

Детальная реализация всех 6 сервисов биллинга с примерами кода.

---

## 1. AccountService

**Назначение**: Управление биллинг-аккаунтами.

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.user.entity.Organization;
import kz.coube.backend.user.repository.OrganizationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class AccountService {
    
    private final AccountRepository accountRepository;
    private final OrganizationRepository organizationRepository;
    
    /**
     * Создать биллинг-аккаунт для организации
     */
    @Transactional
    public Account createAccount(Long organizationId, boolean isNewClient) {
        log.info("Creating billing account for organization {}, isNew={}", organizationId, isNewClient);
        
        // Проверить: аккаунт уже существует?
        if (accountRepository.findByOrganizationId(organizationId).isPresent()) {
            throw new IllegalStateException("Billing account already exists for organization " + organizationId);
        }
        
        // Создать аккаунт
        Account account = new Account();
        account.setOrganizationId(organizationId);
        account.setBalance(BigDecimal.ZERO);
        account.setReservedBalance(BigDecimal.ZERO);
        account.setCurrency("KZT");
        account.setSubscriptionAmount(new BigDecimal("10000.00")); // фиксированная подписка
        account.setIsNewClient(isNewClient);
        
        if (isNewClient) {
            // Новый клиент → пробный период
            account.setStatus("trial");
            account.setTrialEndsAt(LocalDateTime.now().plusMonths(1));
            account.setSubscriptionActive(false);
            log.info("New client - trial period until {}", account.getTrialEndsAt());
        } else {
            // Старый клиент → обычная подписка
            account.setStatus("active");
            account.setSubscriptionActive(true);
            account.setSubscriptionStartDate(LocalDate.now());
            account.setSubscriptionNextBillingDate(LocalDate.now().plusMonths(1));
            log.info("Existing client - subscription active");
        }
        
        account.setCreatedBy("system");
        account.setUpdatedBy("system");
        
        Account saved = accountRepository.save(account);
        
        // Обновить organization.billing_account_id
        Organization org = organizationRepository.findById(organizationId)
            .orElseThrow(() -> new IllegalArgumentException("Organization not found: " + organizationId));
        org.setBillingAccountId(saved.getId());
        organizationRepository.save(org);
        
        log.info("Billing account created: id={}", saved.getId());
        return saved;
    }
    
    /**
     * Получить аккаунт по ID организации
     */
    public Account getAccountByOrganizationId(Long organizationId) {
        return accountRepository.findByOrganizationId(organizationId)
            .orElseThrow(() -> new IllegalArgumentException("Billing account not found for organization: " + organizationId));
    }
    
    /**
     * Получить аккаунт по ID
     */
    public Account getAccount(Long accountId) {
        return accountRepository.findById(accountId)
            .orElseThrow(() -> new IllegalArgumentException("Account not found: " + accountId));
    }
    
    /**
     * Заблокировать аккаунт
     */
    @Transactional
    public void blockAccount(Long accountId, String reason) {
        log.warn("Blocking account {}, reason: {}", accountId, reason);
        
        Account account = getAccount(accountId);
        account.setStatus("blocked");
        account.setBlockedReason(reason);
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
    }
    
    /**
     * Активировать аккаунт
     */
    @Transactional
    public void activateAccount(Long accountId) {
        log.info("Activating account {}", accountId);
        
        Account account = getAccount(accountId);
        account.setStatus("active");
        account.setBlockedReason(null);
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
    }
    
    /**
     * Активировать подписку после окончания trial
     */
    @Transactional
    public void activateSubscription(Long accountId) {
        log.info("Activating subscription for account {}", accountId);
        
        Account account = getAccount(accountId);
        account.setSubscriptionActive(true);
        account.setSubscriptionStartDate(LocalDate.now());
        account.setSubscriptionNextBillingDate(LocalDate.now().plusMonths(1));
        account.setStatus("active");
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
    }
}
```

---

## 2. BalanceService

**Назначение**: Операции с балансом (пополнение, списание).

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.entity.Transaction;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.billing.repository.TransactionRepository;
import kz.coube.backend.billing.dto.BalanceDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;

@Slf4j
@Service
@RequiredArgsConstructor
public class BalanceService {
    
    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final AccountService accountService;
    
    /**
     * Получить баланс
     */
    public BalanceDto getBalance(Long accountId) {
        Account account = accountService.getAccount(accountId);
        
        BigDecimal availableBalance = account.getBalance().subtract(account.getReservedBalance());
        
        // Примерная оценка дней до блокировки
        Integer daysUntilBlocked = null;
        if (account.getSubscriptionActive() && account.getSubscriptionAmount().compareTo(BigDecimal.ZERO) > 0) {
            BigDecimal dailyCost = account.getSubscriptionAmount().divide(new BigDecimal("30"), 2, RoundingMode.HALF_UP);
            if (dailyCost.compareTo(BigDecimal.ZERO) > 0) {
                daysUntilBlocked = availableBalance.divide(dailyCost, 0, RoundingMode.DOWN).intValue();
            }
        }
        
        return BalanceDto.builder()
            .accountId(accountId)
            .balance(account.getBalance())
            .reservedBalance(account.getReservedBalance())
            .availableBalance(availableBalance)
            .currency(account.getCurrency())
            .subscriptionActive(account.getSubscriptionActive())
            .subscriptionAmount(account.getSubscriptionAmount())
            .status(account.getStatus())
            .daysUntilBlocked(daysUntilBlocked)
            .build();
    }
    
    /**
     * Пополнение баланса
     */
    @Transactional
    public Transaction topup(Long accountId, BigDecimal amount, String description) {
        log.info("Topup account {}: amount={}", accountId, amount);
        
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Topup amount must be positive");
        }
        
        Account account = accountService.getAccount(accountId);
        
        BigDecimal balanceBefore = account.getBalance();
        account.setBalance(account.getBalance().add(amount));
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
        
        // Создать транзакцию
        Transaction transaction = new Transaction();
        transaction.setAccountId(accountId);
        transaction.setType("topup");
        transaction.setAmount(amount);
        transaction.setBalanceBefore(balanceBefore);
        transaction.setBalanceAfter(account.getBalance());
        transaction.setDescription(description);
        transaction.setCreatedBy("system");
        
        Transaction saved = transactionRepository.save(transaction);
        
        log.info("Topup completed: transaction={}", saved.getId());
        return saved;
    }
    
    /**
     * Списание за подписку
     */
    @Transactional
    public Transaction chargeSubscription(Long accountId, BigDecimal amount) {
        log.info("Charging subscription for account {}: amount={}", accountId, amount);
        
        Account account = accountService.getAccount(accountId);
        
        BigDecimal balanceBefore = account.getBalance();
        account.setBalance(account.getBalance().subtract(amount));
        account.setUpdatedBy("system");
        
        // Проверить: баланс отрицательный?
        if (account.getBalance().compareTo(BigDecimal.ZERO) < 0) {
            log.warn("Account {} balance is negative: {}", accountId, account.getBalance());
            accountService.blockAccount(accountId, "Insufficient balance for subscription");
        }
        
        accountRepository.save(account);
        
        // Создать транзакцию
        Transaction transaction = new Transaction();
        transaction.setAccountId(accountId);
        transaction.setType("subscription_charge");
        transaction.setAmount(amount.negate()); // отрицательное значение
        transaction.setBalanceBefore(balanceBefore);
        transaction.setBalanceAfter(account.getBalance());
        transaction.setDescription("Monthly subscription charge");
        transaction.setCreatedBy("system");
        
        Transaction saved = transactionRepository.save(transaction);
        
        log.info("Subscription charged: transaction={}", saved.getId());
        return saved;
    }
}
```

---

## 3. ReservationService

**Назначение**: Резервирование комиссии (hold/capture/release).

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.entity.Reservation;
import kz.coube.backend.billing.entity.Transaction;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.billing.repository.ReservationRepository;
import kz.coube.backend.billing.repository.TransactionRepository;
import kz.coube.backend.billing.exception.InsufficientBalanceException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Slf4j
@Service
@RequiredArgsConstructor
public class ReservationService {
    
    private final ReservationRepository reservationRepository;
    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    private final AccountService accountService;
    
    /**
     * Резервировать комиссию
     */
    @Transactional
    public Reservation reserve(Long accountId, Long transportationId, BigDecimal amount) {
        log.info("Reserving commission for account {}, transportation {}, amount={}", 
            accountId, transportationId, amount);
        
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Reservation amount must be positive");
        }
        
        Account account = accountService.getAccount(accountId);
        
        // Проверить: достаточно доступного баланса?
        BigDecimal availableBalance = account.getBalance().subtract(account.getReservedBalance());
        if (availableBalance.compareTo(amount) < 0) {
            log.error("Insufficient balance: available={}, required={}", availableBalance, amount);
            throw new InsufficientBalanceException(
                String.format("Insufficient balance. Available: %s, Required: %s", availableBalance, amount)
            );
        }
        
        // Создать резерв
        Reservation reservation = new Reservation();
        reservation.setAccountId(accountId);
        reservation.setTransportationId(transportationId);
        reservation.setAmount(amount);
        reservation.setStatus("hold");
        reservation.setReservedAt(LocalDateTime.now());
        
        Reservation saved = reservationRepository.save(reservation);
        
        // Увеличить reserved_balance
        account.setReservedBalance(account.getReservedBalance().add(amount));
        account.setUpdatedBy("system");
        accountRepository.save(account);
        
        // Создать транзакцию
        Transaction transaction = new Transaction();
        transaction.setAccountId(accountId);
        transaction.setType("commission_reserve");
        transaction.setAmount(BigDecimal.ZERO); // не меняем баланс, только резерв
        transaction.setBalanceBefore(account.getBalance());
        transaction.setBalanceAfter(account.getBalance());
        transaction.setTransportationId(transportationId);
        transaction.setReservationId(saved.getId());
        transaction.setDescription("Commission reserve 5% for transportation #" + transportationId);
        transaction.setCreatedBy("system");
        transactionRepository.save(transaction);
        
        log.info("Reservation created: id={}", saved.getId());
        return saved;
    }
    
    /**
     * Зачислить комиссию (capture)
     */
    @Transactional
    public Transaction capture(Long reservationId) {
        log.info("Capturing reservation {}", reservationId);
        
        Reservation reservation = reservationRepository.findById(reservationId)
            .orElseThrow(() -> new IllegalArgumentException("Reservation not found: " + reservationId));
        
        if (!"hold".equals(reservation.getStatus())) {
            throw new IllegalStateException("Reservation is not in HOLD status: " + reservation.getStatus());
        }
        
        Account account = accountService.getAccount(reservation.getAccountId());
        
        BigDecimal balanceBefore = account.getBalance();
        
        // Списать с баланса и уменьшить резерв
        account.setBalance(account.getBalance().subtract(reservation.getAmount()));
        account.setReservedBalance(account.getReservedBalance().subtract(reservation.getAmount()));
        account.setUpdatedBy("system");
        accountRepository.save(account);
        
        // Обновить резерв
        reservation.setStatus("captured");
        reservation.setCapturedAt(LocalDateTime.now());
        reservationRepository.save(reservation);
        
        // Создать транзакцию
        Transaction transaction = new Transaction();
        transaction.setAccountId(reservation.getAccountId());
        transaction.setType("commission_capture");
        transaction.setAmount(reservation.getAmount().negate());
        transaction.setBalanceBefore(balanceBefore);
        transaction.setBalanceAfter(account.getBalance());
        transaction.setTransportationId(reservation.getTransportationId());
        transaction.setReservationId(reservationId);
        transaction.setDescription("Commission captured 5% for transportation #" + reservation.getTransportationId());
        transaction.setCreatedBy("system");
        
        Transaction saved = transactionRepository.save(transaction);
        
        log.info("Reservation captured: transaction={}", saved.getId());
        return saved;
    }
    
    /**
     * Освободить резерв (release)
     */
    @Transactional
    public Transaction release(Long reservationId) {
        log.info("Releasing reservation {}", reservationId);
        
        Reservation reservation = reservationRepository.findById(reservationId)
            .orElseThrow(() -> new IllegalArgumentException("Reservation not found: " + reservationId));
        
        if (!"hold".equals(reservation.getStatus())) {
            throw new IllegalStateException("Reservation is not in HOLD status: " + reservation.getStatus());
        }
        
        Account account = accountService.getAccount(reservation.getAccountId());
        
        // Уменьшить reserved_balance
        account.setReservedBalance(account.getReservedBalance().subtract(reservation.getAmount()));
        account.setUpdatedBy("system");
        accountRepository.save(account);
        
        // Обновить резерв
        reservation.setStatus("released");
        reservation.setReleasedAt(LocalDateTime.now());
        reservationRepository.save(reservation);
        
        // Создать транзакцию
        Transaction transaction = new Transaction();
        transaction.setAccountId(reservation.getAccountId());
        transaction.setType("commission_release");
        transaction.setAmount(BigDecimal.ZERO);
        transaction.setBalanceBefore(account.getBalance());
        transaction.setBalanceAfter(account.getBalance());
        transaction.setTransportationId(reservation.getTransportationId());
        transaction.setReservationId(reservationId);
        transaction.setDescription("Commission reservation released for transportation #" + reservation.getTransportationId());
        transaction.setCreatedBy("system");
        
        Transaction saved = transactionRepository.save(transaction);
        
        log.info("Reservation released: transaction={}", saved.getId());
        return saved;
    }
}
```

---

## 4. InvoiceService

**Назначение**: Создание счетов на пополнение.

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Invoice;
import kz.coube.backend.billing.repository.InvoiceRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class InvoiceService {
    
    private final InvoiceRepository invoiceRepository;
    private final AccountService accountService;
    
    /**
     * Создать счёт на пополнение баланса
     */
    @Transactional
    public Invoice createInvoice(Long accountId, BigDecimal amount) {
        log.info("Creating invoice for account {}, amount={}", accountId, amount);
        
        if (amount.compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalArgumentException("Invoice amount must be positive");
        }
        
        // Проверить существование аккаунта
        accountService.getAccount(accountId);
        
        Invoice invoice = new Invoice();
        invoice.setAccountId(accountId);
        invoice.setAmount(amount);
        invoice.setStatus("pending");
        // invoice_number будет сгенерирован триггером после INSERT
        
        Invoice saved = invoiceRepository.save(invoice);
        
        log.info("Invoice created: id={}, number={}", saved.getId(), saved.getInvoiceNumber());
        return saved;
    }
    
    /**
     * Получить счета по аккаунту
     */
    public List<Invoice> getInvoices(Long accountId) {
        return invoiceRepository.findByAccountIdOrderByCreatedAtDesc(accountId);
    }
    
    /**
     * Получить счёт по ID
     */
    public Invoice getInvoice(Long invoiceId) {
        return invoiceRepository.findById(invoiceId)
            .orElseThrow(() -> new IllegalArgumentException("Invoice not found: " + invoiceId));
    }
    
    /**
     * Отметить счёт как оплаченный
     */
    @Transactional
    public void markAsPaid(Long invoiceId) {
        Invoice invoice = getInvoice(invoiceId);
        invoice.setStatus("paid");
        invoice.setPaidAt(LocalDateTime.now());
        invoiceRepository.save(invoice);
    }
}
```

---

## 5. PaymentService

**Назначение**: Обработка платежей (ручное подтверждение).

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Invoice;
import kz.coube.backend.billing.entity.Payment;
import kz.coube.backend.billing.entity.Transaction;
import kz.coube.backend.billing.repository.PaymentRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentService {
    
    private final PaymentRepository paymentRepository;
    private final InvoiceService invoiceService;
    private final BalanceService balanceService;
    
    /**
     * Ручное подтверждение оплаты админом
     */
    @Transactional
    public Payment recordManualPayment(Long invoiceId, BigDecimal amount, String adminUsername) {
        log.info("Recording manual payment for invoice {}, amount={}, admin={}", 
            invoiceId, amount, adminUsername);
        
        Invoice invoice = invoiceService.getInvoice(invoiceId);
        
        if (!"pending".equals(invoice.getStatus())) {
            throw new IllegalStateException("Invoice is not pending: " + invoice.getStatus());
        }
        
        if (amount.compareTo(invoice.getAmount()) != 0) {
            log.warn("Payment amount {} does not match invoice amount {}", amount, invoice.getAmount());
        }
        
        // Создать платёж
        Payment payment = new Payment();
        payment.setInvoiceId(invoiceId);
        payment.setAccountId(invoice.getAccountId());
        payment.setAmount(amount);
        payment.setPaymentMethod("manual");
        payment.setStatus("success");
        payment.setCreatedBy(adminUsername);
        
        Payment saved = paymentRepository.save(payment);
        
        // Пополнить баланс
        Transaction transaction = balanceService.topup(
            invoice.getAccountId(), 
            amount, 
            "Balance topup via invoice #" + invoice.getInvoiceNumber()
        );
        
        // Отметить счёт как оплаченный
        invoiceService.markAsPaid(invoiceId);
        
        log.info("Manual payment recorded: payment={}, transaction={}", saved.getId(), transaction.getId());
        
        // TODO: Отправить уведомление пользователю
        
        return saved;
    }
}
```

---

## 6. SubscriptionService (опционально)

**Назначение**: Управление подписками.

### Код

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;

@Slf4j
@Service
@RequiredArgsConstructor
public class SubscriptionService {
    
    private final AccountRepository accountRepository;
    private final AccountService accountService;
    
    /**
     * Активировать подписку
     */
    @Transactional
    public void activateSubscription(Long accountId) {
        log.info("Activating subscription for account {}", accountId);
        
        Account account = accountService.getAccount(accountId);
        account.setSubscriptionActive(true);
        account.setSubscriptionStartDate(LocalDate.now());
        account.setSubscriptionNextBillingDate(LocalDate.now().plusMonths(1));
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
    }
    
    /**
     * Отменить подписку
     */
    @Transactional
    public void cancelSubscription(Long accountId) {
        log.info("Cancelling subscription for account {}", accountId);
        
        Account account = accountService.getAccount(accountId);
        account.setSubscriptionActive(false);
        account.setUpdatedBy("system");
        
        accountRepository.save(account);
    }
}
```

---

## Exception класс

```java
package kz.coube.backend.billing.exception;

public class InsufficientBalanceException extends RuntimeException {
    public InsufficientBalanceException(String message) {
        super(message);
    }
}
```

---

## DTO классы

### BalanceDto

```java
package kz.coube.backend.billing.dto;

import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;

@Data
@Builder
public class BalanceDto {
    private Long accountId;
    private BigDecimal balance;
    private BigDecimal reservedBalance;
    private BigDecimal availableBalance;
    private String currency;
    private Boolean subscriptionActive;
    private BigDecimal subscriptionAmount;
    private String status;
    private Integer daysUntilBlocked;
}
```

---

## Unit тесты (примеры)

### AccountServiceTest

```java
package kz.coube.backend.billing.service;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AccountServiceTest {
    
    @Mock
    private AccountRepository accountRepository;
    
    @Mock
    private OrganizationRepository organizationRepository;
    
    @InjectMocks
    private AccountService accountService;
    
    @Test
    void createAccount_newClient_shouldSetTrialPeriod() {
        // Given
        Long orgId = 123L;
        when(accountRepository.findByOrganizationId(orgId)).thenReturn(Optional.empty());
        when(accountRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(organizationRepository.findById(orgId)).thenReturn(Optional.of(new Organization()));
        
        // When
        Account account = accountService.createAccount(orgId, true);
        
        // Then
        assertEquals("trial", account.getStatus());
        assertNotNull(account.getTrialEndsAt());
        assertEquals(false, account.getSubscriptionActive());
    }
    
    @Test
    void createAccount_existingClient_shouldActivateSubscription() {
        // Given
        Long orgId = 123L;
        when(accountRepository.findByOrganizationId(orgId)).thenReturn(Optional.empty());
        when(accountRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(organizationRepository.findById(orgId)).thenReturn(Optional.of(new Organization()));
        
        // When
        Account account = accountService.createAccount(orgId, false);
        
        // Then
        assertEquals("active", account.getStatus());
        assertEquals(true, account.getSubscriptionActive());
        assertNotNull(account.getSubscriptionNextBillingDate());
    }
}
```

---

**Готово!** Все 6 сервисов реализованы с примерами кода и тестов.

**Следующий шаг**: `03-api-endpoints.md`
