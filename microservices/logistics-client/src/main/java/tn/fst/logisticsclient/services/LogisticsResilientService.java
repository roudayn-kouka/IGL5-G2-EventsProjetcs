package tn.fst.logisticsclient.services;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import tn.fst.logisticsclient.clients.LogisticsFeignClient;
import tn.fst.logisticsclient.dto.LogisticsDTO;

@Slf4j
@Service
@RequiredArgsConstructor
public class LogisticsResilientService {

    private final LogisticsFeignClient client;

    @Retry(name = "logisticsService")
    @RateLimiter(name = "logisticsService")
    @CircuitBreaker(name = "logisticsService", fallbackMethod = "fallbackById")
    public LogisticsDTO getById(Integer id) {
        log.info("Appel de logistics-service pour id={}", id);
        return client.getById(id);
    }

    public LogisticsDTO fallbackById(Integer id, Throwable t) {
        log.warn("FALLBACK pour id={} : {}", id, t.toString());
        return new LogisticsDTO(id, "Service Logistics indisponible (fallback)", false, 0f, 0);
    }
}