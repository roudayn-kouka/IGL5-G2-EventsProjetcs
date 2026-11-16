package tn.fst.logisticsclient.services;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import tn.fst.logisticsclient.clients.BadUrlClient;
import tn.fst.logisticsclient.clients.LogisticsFeignClient;
import tn.fst.logisticsclient.dto.LogisticsDTO;

@Slf4j
@Service
@RequiredArgsConstructor
public class LogisticsResilientService {

    private final LogisticsFeignClient client;
    private final BadUrlClient badClient;

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

    @CircuitBreaker(name = "logisticsService", fallbackMethod = "fallbackFault")
    public LogisticsDTO slow() {
        return client.slow();
    }

    @CircuitBreaker(name = "logisticsService", fallbackMethod = "fallbackFault")
    public LogisticsDTO corrupted() {
        LogisticsDTO d = client.corrupted();
        if (d.getPrixUnit() == null || d.getPrixUnit() < 0
                || d.getQuantite() == null || d.getQuantite() < 0) {
            throw new IllegalStateException("Reponse invalide : prix ou quantite negatif");
        }
        return d;
    }

    @CircuitBreaker(name = "logisticsService", fallbackMethod = "fallbackFault")
    public LogisticsDTO badUrl() {
        return badClient.get();
    }

    public LogisticsDTO fallbackFault(Throwable t) {
        log.warn("FALLBACK faute : {}", t.toString());
        return new LogisticsDTO(0, "Fallback : " + t.getClass().getSimpleName(), false, 0f, 0);
    }
}