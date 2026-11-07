package tn.fst.eventsproject.config;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.util.Arrays;
import java.util.Collections;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

/**
 * AVEC Mockito : valeurs des métriques métier exposées à Prometheus (dashboard Grafana).
 */
@RunWith(MockitoJUnitRunner.class)
public class BusinessMetricsConfigTest {

    @Mock
    EventRepository eventRepository;
    @Mock
    ParticipantRepository participantRepository;
    @Mock
    LogisticsRepository logisticsRepository;

    SimpleMeterRegistry registry;

    @Before
    public void setUp() {
        registry = new SimpleMeterRegistry();
        new BusinessMetricsConfig()
                .businessMetrics(eventRepository, participantRepository, logisticsRepository)
                .bindTo(registry);
    }

    private Logistics logistique(float prixUnit, int quantite) {
        Logistics l = new Logistics();
        l.setReserve(true);
        l.setPrixUnit(prixUnit);
        l.setQuantite(quantite);
        return l;
    }

    @Test
    public void testCompteursEvenementsEtParticipants() {
        when(eventRepository.count()).thenReturn(6L);
        when(participantRepository.count()).thenReturn(12L);

        assertEquals(6.0, registry.get("fst.events.count").gauge().value(), 0.001);
        assertEquals(12.0, registry.get("fst.participants.count").gauge().value(), 0.001);
    }

    @Test
    public void testCoutDeLaLogistiqueReservee() {
        when(logisticsRepository.findByReserveTrue())
                .thenReturn(Arrays.asList(logistique(2.5f, 100), logistique(120f, 2)));

        assertEquals(490.0, registry.get("fst.logistics.reserved.cost").gauge().value(), 0.001);
    }

    @Test
    public void testCoutNulSansLogistiqueReservee() {
        when(logisticsRepository.findByReserveTrue()).thenReturn(Collections.emptyList());

        assertEquals(0.0, registry.get("fst.logistics.reserved.cost").gauge().value(), 0.001);
    }
}
