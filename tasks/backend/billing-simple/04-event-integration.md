# 04. Интеграция с модулем Applications (Events)

## Обзор

Автоматическое резервирование комиссии при работе с заявками через Spring Events.

---

## Архитектура

```
Applications Module                    Billing Module
      │                                      │
      │  TransportationSignedByExecutorEvent │
      ├──────────────────────────────────────>│
      │                                       │ reserve(commission)
      │                                       │
      │  TransportationConfirmedEvent         │
      ├──────────────────────────────────────>│
      │                                       │ capture(reservation)
      │                                       │
      │  TransportationCancelledEvent         │
      ├──────────────────────────────────────>│
      │                                       │ release(reservation)
```

---

## Events (создать в Applications модуле)

### 1. TransportationSignedByExecutorEvent

```java
package kz.coube.backend.applications.event;

import lombok.Getter;
import org.springframework.context.ApplicationEvent;

@Getter
public class TransportationSignedByExecutorEvent extends ApplicationEvent {
    private final Long transportationId;
    private final Long executorOrganizationId;
    private final BigDecimal transportationCost;
    
    public TransportationSignedByExecutorEvent(Object source, Long transportationId, 
                                                Long executorOrganizationId, BigDecimal transportationCost) {
        super(source);
        this.transportationId = transportationId;
        this.executorOrganizationId = executorOrganizationId;
        this.transportationCost = transportationCost;
    }
}
```

### 2. TransportationConfirmedEvent

```java
package kz.coube.backend.applications.event;

import lombok.Getter;
import org.springframework.context.ApplicationEvent;

@Getter
public class TransportationConfirmedEvent extends ApplicationEvent {
    private final Long transportationId;
    private final Long reservationId; // из transportation.commission_reservation_id
    
    public TransportationConfirmedEvent(Object source, Long transportationId, Long reservationId) {
        super(source);
        this.transportationId = transportationId;
        this.reservationId = reservationId;
    }
}
```

### 3. TransportationCancelledEvent

```java
package kz.coube.backend.applications.event;

import lombok.Getter;
import org.springframework.context.ApplicationEvent;

@Getter
public class TransportationCancelledEvent extends ApplicationEvent {
    private final Long transportationId;
    private final Long reservationId;
    
    public TransportationCancelledEvent(Object source, Long transportationId, Long reservationId) {
        super(source);
        this.transportationId = transportationId;
        this.reservationId = reservationId;
    }
}
```

---

## EventListener (в Billing модуле)

### TransportationEventListener

```java
package kz.coube.backend.billing.event;

import kz.coube.backend.applications.entity.Transportation;
import kz.coube.backend.applications.event.*;
import kz.coube.backend.applications.repository.TransportationRepository;
import kz.coube.backend.billing.entity.Account;
import kz.coube.backend.billing.entity.Reservation;
import kz.coube.backend.billing.service.AccountService;
import kz.coube.backend.billing.service.ReservationService;
import kz.coube.backend.billing.exception.InsufficientBalanceException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;

@Slf4j
@Component
@RequiredArgsConstructor
public class TransportationEventListener {
    
    private final ReservationService reservationService;
    private final AccountService accountService;
    private final TransportationRepository transportationRepository;
    
    private static final BigDecimal COMMISSION_RATE = new BigDecimal("0.05"); // 5%
    
    /**
     * Событие: Исполнитель подписал заявку
     * Действие: Зарезервировать комиссию 5%
     */
    @EventListener
    @Async
    @Transactional
    public void onTransportationSignedByExecutor(TransportationSignedByExecutorEvent event) {
        log.info("Event received: TransportationSignedByExecutor, transportationId={}", event.getTransportationId());
        
        try {
            // Получить биллинг-аккаунт исполнителя
            Account account = accountService.getAccountByOrganizationId(event.getExecutorOrganizationId());
            
            // Рассчитать комиссию 5%
            BigDecimal commission = event.getTransportationCost()
                .multiply(COMMISSION_RATE)
                .setScale(2, RoundingMode.HALF_UP);
            
            log.info("Reserving commission: cost={}, commission={} (5%)", 
                event.getTransportationCost(), commission);
            
            // Зарезервировать комиссию
            Reservation reservation = reservationService.reserve(
                account.getId(),
                event.getTransportationId(),
                commission
            );
            
            // Обновить transportation.commission_reservation_id
            Transportation transportation = transportationRepository.findById(event.getTransportationId())
                .orElseThrow(() -> new IllegalArgumentException("Transportation not found: " + event.getTransportationId()));
            
            transportation.setCommissionReservationId(reservation.getId());
            transportationRepository.save(transportation);
            
            log.info("Commission reserved successfully: reservationId={}", reservation.getId());
            
        } catch (InsufficientBalanceException e) {
            log.error("Failed to reserve commission: {}", e.getMessage());
            // TODO: Уведомить исполнителя о недостатке средств
            // TODO: Заблокировать возможность подписания заявок до пополнения баланса
            throw e;
        } catch (Exception e) {
            log.error("Error processing TransportationSignedByExecutor event", e);
            throw e;
        }
    }
    
    /**
     * Событие: Заявка подтверждена второй стороной
     * Действие: Зачислить комиссию (capture)
     */
    @EventListener
    @Async
    @Transactional
    public void onTransportationConfirmed(TransportationConfirmedEvent event) {
        log.info("Event received: TransportationConfirmed, transportationId={}", event.getTransportationId());
        
        try {
            if (event.getReservationId() == null) {
                log.warn("No reservation found for transportation {}", event.getTransportationId());
                return;
            }
            
            // Зачислить комиссию
            reservationService.capture(event.getReservationId());
            
            log.info("Commission captured successfully for transportation {}", event.getTransportationId());
            
        } catch (Exception e) {
            log.error("Error processing TransportationConfirmed event", e);
            throw e;
        }
    }
    
    /**
     * Событие: Заявка отменена
     * Действие: Освободить резерв (release)
     */
    @EventListener
    @Async
    @Transactional
    public void onTransportationCancelled(TransportationCancelledEvent event) {
        log.info("Event received: TransportationCancelled, transportationId={}", event.getTransportationId());
        
        try {
            if (event.getReservationId() == null) {
                log.warn("No reservation found for transportation {}", event.getTransportationId());
                return;
            }
            
            // Освободить резерв
            reservationService.release(event.getReservationId());
            
            log.info("Commission reservation released for transportation {}", event.getTransportationId());
            
        } catch (Exception e) {
            log.error("Error processing TransportationCancelled event", e);
            throw e;
        }
    }
}
```

---

## Публикация событий (в Applications модуле)

### TransportationService

```java
package kz.coube.backend.applications.service;

import kz.coube.backend.applications.entity.Transportation;
import kz.coube.backend.applications.event.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

@Slf4j
@Service
@RequiredArgsConstructor
public class TransportationService {
    
    private final ApplicationEventPublisher eventPublisher;
    private final TransportationRepository transportationRepository;
    
    /**
     * Исполнитель подписывает заявку
     */
    @Transactional
    public void signByExecutor(Long transportationId, Long executorOrganizationId) {
        log.info("Signing transportation {} by executor {}", transportationId, executorOrganizationId);
        
        Transportation transportation = transportationRepository.findById(transportationId)
            .orElseThrow(() -> new IllegalArgumentException("Transportation not found"));
        
        // Обновить статус
        transportation.setStatus("SIGNED_BY_EXECUTOR");
        transportationRepository.save(transportation);
        
        // Получить стоимость заявки
        BigDecimal cost = getTransportationCost(transportationId); // из transportation_cost
        
        // Опубликовать событие
        TransportationSignedByExecutorEvent event = new TransportationSignedByExecutorEvent(
            this,
            transportationId,
            executorOrganizationId,
            cost
        );
        eventPublisher.publishEvent(event);
        
        log.info("Event published: TransportationSignedByExecutorEvent");
    }
    
    /**
     * Подтверждение заявки
     */
    @Transactional
    public void confirmTransportation(Long transportationId) {
        log.info("Confirming transportation {}", transportationId);
        
        Transportation transportation = transportationRepository.findById(transportationId)
            .orElseThrow(() -> new IllegalArgumentException("Transportation not found"));
        
        // Обновить статус
        transportation.setStatus("CONFIRMED");
        transportationRepository.save(transportation);
        
        // Опубликовать событие
        TransportationConfirmedEvent event = new TransportationConfirmedEvent(
            this,
            transportationId,
            transportation.getCommissionReservationId()
        );
        eventPublisher.publishEvent(event);
        
        log.info("Event published: TransportationConfirmedEvent");
    }
    
    /**
     * Отмена заявки
     */
    @Transactional
    public void cancelTransportation(Long transportationId) {
        log.info("Cancelling transportation {}", transportationId);
        
        Transportation transportation = transportationRepository.findById(transportationId)
            .orElseThrow(() -> new IllegalArgumentException("Transportation not found"));
        
        // Обновить статус
        transportation.setStatus("CANCELLED");
        transportationRepository.save(transportation);
        
        // Опубликовать событие (только если есть резерв)
        if (transportation.getCommissionReservationId() != null) {
            TransportationCancelledEvent event = new TransportationCancelledEvent(
                this,
                transportationId,
                transportation.getCommissionReservationId()
            );
            eventPublisher.publishEvent(event);
            
            log.info("Event published: TransportationCancelledEvent");
        }
    }
    
    private BigDecimal getTransportationCost(Long transportationId) {
        // Получить стоимость из transportation_cost
        // Упрощённая версия:
        return new BigDecimal("100000.00"); // TODO: реальная логика
    }
}
```

---

## Конфигурация асинхронности

```java
package kz.coube.backend.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.context.annotation.Bean;

import java.util.concurrent.Executor;

@Configuration
@EnableAsync
public class AsyncConfig {
    
    @Bean(name = "eventExecutor")
    public Executor eventExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(5);
        executor.setMaxPoolSize(10);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("event-");
        executor.initialize();
        return executor;
    }
}
```

---

## Обработка ошибок

### Что если резерв не удался?

```java
@EventListener
@Async
@Transactional
public void onTransportationSignedByExecutor(TransportationSignedByExecutorEvent event) {
    try {
        // ... код резервирования
    } catch (InsufficientBalanceException e) {
        log.error("Insufficient balance for executor {}", event.getExecutorOrganizationId());
        
        // 1. Отменить подписание заявки
        Transportation transportation = transportationRepository.findById(event.getTransportationId())
            .orElseThrow();
        transportation.setStatus("UNSIGNED"); // откат статуса
        transportationRepository.save(transportation);
        
        // 2. Уведомить исполнителя
        notificationService.sendInsufficientBalanceNotification(
            event.getExecutorOrganizationId(),
            "Недостаточно средств на балансе для резервирования комиссии"
        );
        
        // 3. Можно заблокировать возможность подписывать новые заявки
        accountService.blockAccount(accountId, "Insufficient balance for commission");
    }
}
```

---

## Integration тесты

```java
package kz.coube.backend.billing.event;

import kz.coube.backend.applications.event.TransportationSignedByExecutorEvent;
import kz.coube.backend.billing.entity.Reservation;
import kz.coube.backend.billing.repository.ReservationRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.test.context.jdbc.Sql;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@Sql("/test-data.sql")
class TransportationEventListenerTest {
    
    @Autowired
    private ApplicationEventPublisher eventPublisher;
    
    @Autowired
    private ReservationRepository reservationRepository;
    
    @Test
    void onTransportationSignedByExecutor_shouldCreateReservation() throws InterruptedException {
        // Given
        Long transportationId = 789L;
        Long executorOrgId = 456L;
        BigDecimal cost = new BigDecimal("100000.00");
        
        // When
        TransportationSignedByExecutorEvent event = new TransportationSignedByExecutorEvent(
            this, transportationId, executorOrgId, cost
        );
        eventPublisher.publishEvent(event);
        
        // Wait for async processing
        Thread.sleep(1000);
        
        // Then
        Reservation reservation = reservationRepository.findByTransportationId(transportationId)
            .orElseThrow();
        
        assertEquals("hold", reservation.getStatus());
        assertEquals(new BigDecimal("5000.00"), reservation.getAmount()); // 5% from 100000
    }
}
```

---

**Готово!** Интеграция с Applications модулем через события настроена.

**Следующий шаг**: `05-scheduled-jobs.md`
