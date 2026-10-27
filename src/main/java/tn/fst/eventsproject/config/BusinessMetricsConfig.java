package tn.fst.eventsproject.config;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.binder.MeterBinder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

/**
 * Métriques métier exposées sur /events/actuator/prometheus
 * et affichées dans le dashboard Grafana (une courbe par feature/namespace).
 */
@Configuration
public class BusinessMetricsConfig {

    @Bean
    public MeterBinder businessMetrics(EventRepository eventRepository,
                                       ParticipantRepository participantRepository,
                                       LogisticsRepository logisticsRepository) {
        return registry -> {
            Gauge.builder("fst.events.count", eventRepository, r -> r.count())
                    .description("Nombre d'événements")
                    .register(registry);
            Gauge.builder("fst.participants.count", participantRepository, r -> r.count())
                    .description("Nombre de participants")
                    .register(registry);
            Gauge.builder("fst.logistics.reserved.cost", logisticsRepository, r -> {
                        double total = 0;
                        for (Logistics l : r.findByReserveTrue()) {
                            total += l.getPrixUnit() * l.getQuantite();
                        }
                        return total;
                    })
                    .description("Coût total de la logistique réservée (DT)")
                    .register(registry);
        };
    }
}
