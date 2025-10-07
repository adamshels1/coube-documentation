# 05. Scheduled Jobs (Автоматические задачи)

## Обзор

Два ежедневных джоба для автоматизации биллинга.

---

## 1. MonthlySubscriptionJob

**Назначение**: Ежемесячное списание подписки.

**Расписание**: 1-го числа каждого месяца в 02:00

### Код

```java
package kz.coube.backend.billing.scheduler;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.billing.service.BalanceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class MonthlySubscriptionJob {
    
    private final AccountRepository accountRepository;
    private final BalanceService balanceService;
    
    /**
     * Списание подписки — 1-го числа каждого месяца в 02:00
     */
    @Scheduled(cron = "0 0 2 1 * *") // секунда минута час день месяц день_недели
    @Transactional
    public void chargeMonthlySubscriptions() {
        log.info("Starting monthly subscription charges...");
        
        LocalDate today = LocalDate.now();
        
        // Получить все аккаунты с активной подпиской
        List<Account> accounts = accountRepository.findBySubscriptionActive(true);
        
        log.info("Found {} accounts with active subscriptions", accounts.size());
        
        int successCount = 0;
        int blockedCount = 0;
        
        for (Account account : accounts) {
            try {
                // Проверить: дата следующего списания = сегодня?
                if (account.getSubscriptionNextBillingDate() != null && 
                    !account.getSubscriptionNextBillingDate().isAfter(today)) {
                    
                    log.info("Charging subscription for account {}", account.getId());
                    
                    // Списать подписку
                    balanceService.chargeSubscription(account.getId(), account.getSubscriptionAmount());
                    
                    // Обновить дату следующего списания
                    account.setSubscriptionNextBillingDate(today.plusMonths(1));
                    account.setUpdatedBy("system");
                    accountRepository.save(account);
                    
                    successCount++;
                    
                    // Проверить: баланс отрицательный?
                    if (account.getBalance().compareTo(BigDecimal.ZERO) < 0) {
                        log.warn("Account {} blocked due to negative balance", account.getId());
                        blockedCount++;
                        // Аккаунт уже заблокирован в balanceService.chargeSubscription()
                    }
                }
            } catch (Exception e) {
                log.error("Error charging subscription for account {}", account.getId(), e);
                // Продолжаем обработку остальных аккаунтов
            }
        }
        
        log.info("Monthly subscription charges completed: success={}, blocked={}", successCount, blockedCount);
    }
}
```

---

## 2. LowBalanceNotificationJob

**Назначение**: Уведомления о низком балансе.

**Расписание**: Каждый день в 10:00

### Код

```java
package kz.coube.backend.billing.scheduler;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.notifications.service.NotificationService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class LowBalanceNotificationJob {
    
    private final AccountRepository accountRepository;
    private final NotificationService notificationService;
    
    /**
     * Проверка низкого баланса — каждый день в 10:00
     */
    @Scheduled(cron = "0 0 10 * * *")
    public void checkLowBalances() {
        log.info("Starting low balance check...");
        
        // Получить все активные аккаунты с подпиской
        List<Account> accounts = accountRepository.findBySubscriptionActiveAndStatus(true, "active");
        
        log.info("Checking {} active accounts", accounts.size());
        
        int notificationsCount = 0;
        
        for (Account account : accounts) {
            try {
                // Рассчитать доступный баланс
                BigDecimal availableBalance = account.getBalance().subtract(account.getReservedBalance());
                
                // Рассчитать дней до блокировки
                if (account.getSubscriptionAmount().compareTo(BigDecimal.ZERO) > 0) {
                    BigDecimal dailyCost = account.getSubscriptionAmount()
                        .divide(new BigDecimal("30"), 2, RoundingMode.HALF_UP);
                    
                    int daysUntilBlocked = availableBalance
                        .divide(dailyCost, 0, RoundingMode.DOWN)
                        .intValue();
                    
                    // Отправить уведомление при пороговых значениях
                    if (daysUntilBlocked <= 1) {
                        sendNotification(account, daysUntilBlocked, "critical");
                        notificationsCount++;
                    } else if (daysUntilBlocked <= 3) {
                        sendNotification(account, daysUntilBlocked, "warning");
                        notificationsCount++;
                    } else if (daysUntilBlocked <= 7) {
                        sendNotification(account, daysUntilBlocked, "info");
                        notificationsCount++;
                    }
                }
            } catch (Exception e) {
                log.error("Error checking balance for account {}", account.getId(), e);
            }
        }
        
        log.info("Low balance check completed: {} notifications sent", notificationsCount);
    }
    
    private void sendNotification(Account account, int daysUntilBlocked, String severity) {
        String message;
        
        if (daysUntilBlocked <= 0) {
            message = "Внимание! Баланс недостаточен для следующего списания подписки. Пополните баланс.";
        } else if (daysUntilBlocked == 1) {
            message = "Внимание! Средств на балансе хватит на 1 день. Пополните баланс.";
        } else {
            message = String.format("Средств на балансе хватит на %d дня(ей). Рекомендуем пополнить баланс.", daysUntilBlocked);
        }
        
        log.info("Sending {} notification to account {}: days={}", severity, account.getId(), daysUntilBlocked);
        
        // Интеграция с модулем notifications
        notificationService.sendLowBalanceNotification(
            account.getOrganizationId(),
            message,
            daysUntilBlocked,
            severity
        );
    }
}
```

---

## 3. TrialPeriodExpirationJob (опционально)

**Назначение**: Активация подписки после окончания trial.

**Расписание**: Каждый день в 03:00

### Код

```java
package kz.coube.backend.billing.scheduler;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.billing.service.AccountService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class TrialPeriodExpirationJob {
    
    private final AccountRepository accountRepository;
    private final AccountService accountService;
    
    /**
     * Проверка окончания trial периода — каждый день в 03:00
     */
    @Scheduled(cron = "0 0 3 * * *")
    @Transactional
    public void expireTrialPeriods() {
        log.info("Checking expired trial periods...");
        
        LocalDateTime now = LocalDateTime.now();
        
        // Получить аккаунты со статусом trial и истёкшим периодом
        List<Account> accounts = accountRepository.findByStatusAndTrialEndsAtBefore("trial", now);
        
        log.info("Found {} expired trial accounts", accounts.size());
        
        for (Account account : accounts) {
            try {
                log.info("Activating subscription for account {} (trial expired)", account.getId());
                
                // Активировать подписку
                accountService.activateSubscription(account.getId());
                
            } catch (Exception e) {
                log.error("Error activating subscription for account {}", account.getId(), e);
            }
        }
        
        log.info("Trial period expiration check completed");
    }
}
```

---

## Конфигурация Scheduling

```java
package kz.coube.backend.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

@Configuration
@EnableScheduling
public class SchedulingConfig {
    // Spring Boot автоматически настроит scheduler
}
```

---

## Логирование результатов

### Расширенное логирование в MonthlySubscriptionJob

```java
@Scheduled(cron = "0 0 2 1 * *")
@Transactional
public void chargeMonthlySubscriptions() {
    log.info("=== MONTHLY SUBSCRIPTION CHARGE JOB STARTED ===");
    
    LocalDate today = LocalDate.now();
    long startTime = System.currentTimeMillis();
    
    List<Account> accounts = accountRepository.findBySubscriptionActive(true);
    
    log.info("Found {} accounts with active subscriptions", accounts.size());
    
    int successCount = 0;
    int blockedCount = 0;
    int errorCount = 0;
    BigDecimal totalCharged = BigDecimal.ZERO;
    
    for (Account account : accounts) {
        try {
            if (account.getSubscriptionNextBillingDate() != null && 
                !account.getSubscriptionNextBillingDate().isAfter(today)) {
                
                balanceService.chargeSubscription(account.getId(), account.getSubscriptionAmount());
                
                account.setSubscriptionNextBillingDate(today.plusMonths(1));
                account.setUpdatedBy("system");
                accountRepository.save(account);
                
                totalCharged = totalCharged.add(account.getSubscriptionAmount());
                successCount++;
                
                if (account.getBalance().compareTo(BigDecimal.ZERO) < 0) {
                    blockedCount++;
                }
            }
        } catch (Exception e) {
            log.error("Error charging subscription for account {}", account.getId(), e);
            errorCount++;
        }
    }
    
    long duration = System.currentTimeMillis() - startTime;
    
    log.info("=== MONTHLY SUBSCRIPTION CHARGE JOB COMPLETED ===");
    log.info("Duration: {}ms", duration);
    log.info("Success: {} accounts", successCount);
    log.info("Blocked: {} accounts", blockedCount);
    log.info("Errors: {} accounts", errorCount);
    log.info("Total charged: {} KZT", totalCharged);
}
```

---

## Мониторинг и алерты

### Интеграция с метриками

```java
package kz.coube.backend.billing.scheduler;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class MonthlySubscriptionJob {
    
    private final Counter subscriptionChargeSuccessCounter;
    private final Counter subscriptionChargeFailureCounter;
    
    public MonthlySubscriptionJob(MeterRegistry meterRegistry, ...) {
        this.subscriptionChargeSuccessCounter = Counter.builder("billing.subscription.charge.success")
            .description("Number of successful subscription charges")
            .register(meterRegistry);
        
        this.subscriptionChargeFailureCounter = Counter.builder("billing.subscription.charge.failure")
            .description("Number of failed subscription charges")
            .register(meterRegistry);
    }
    
    @Scheduled(cron = "0 0 2 1 * *")
    public void chargeMonthlySubscriptions() {
        // ... код
        
        for (Account account : accounts) {
            try {
                // ... списание
                subscriptionChargeSuccessCounter.increment();
            } catch (Exception e) {
                subscriptionChargeFailureCounter.increment();
            }
        }
    }
}
```

---

## Тестирование джобов

### Unit тест

```java
package kz.coube.backend.billing.scheduler;

import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.repository.AccountRepository;
import kz.coube.backend.billing.service.BalanceService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class MonthlySubscriptionJobTest {
    
    @Mock
    private AccountRepository accountRepository;
    
    @Mock
    private BalanceService balanceService;
    
    @InjectMocks
    private MonthlySubscriptionJob job;
    
    @Test
    void chargeMonthlySubscriptions_shouldChargeActiveAccounts() {
        // Given
        Account account1 = new Account();
        account1.setId(1L);
        account1.setSubscriptionActive(true);
        account1.setSubscriptionAmount(new BigDecimal("10000.00"));
        account1.setSubscriptionNextBillingDate(LocalDate.now());
        account1.setBalance(new BigDecimal("50000.00"));
        
        when(accountRepository.findBySubscriptionActive(true)).thenReturn(List.of(account1));
        
        // When
        job.chargeMonthlySubscriptions();
        
        // Then
        verify(balanceService).chargeSubscription(1L, new BigDecimal("10000.00"));
        verify(accountRepository).save(account1);
    }
}
```

### Ручной запуск (для тестирования)

```java
@RestController
@RequestMapping("/api/v1/admin/jobs")
@PreAuthorize("hasRole('ADMIN')")
public class JobManualTriggerController {
    
    private final MonthlySubscriptionJob monthlySubscriptionJob;
    private final LowBalanceNotificationJob lowBalanceNotificationJob;
    
    @PostMapping("/charge-subscriptions")
    public ResponseEntity<String> triggerSubscriptionCharge() {
        monthlySubscriptionJob.chargeMonthlySubscriptions();
        return ResponseEntity.ok("Job triggered");
    }
    
    @PostMapping("/check-low-balances")
    public ResponseEntity<String> triggerLowBalanceCheck() {
        lowBalanceNotificationJob.checkLowBalances();
        return ResponseEntity.ok("Job triggered");
    }
}
```

---

**Готово!** Все scheduled jobs настроены.

**Все файлы созданы!** Проверь папку `/billing-simple/` — теперь там 7 файлов.
