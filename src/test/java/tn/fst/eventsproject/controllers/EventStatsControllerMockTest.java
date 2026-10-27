package tn.fst.eventsproject.controllers;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.fst.eventsproject.dto.EventStatsDTO;
import tn.fst.eventsproject.dto.GlobalStatsDTO;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.services.IEventStatsService;

import java.time.LocalDate;
import java.util.Collections;
import java.util.EnumMap;
import java.util.Map;

import static org.hamcrest.Matchers.hasSize;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Test du contrôleur statistiques AVEC Mockito : le service est simulé,
 * aucune base de données et aucun contexte Spring complet.
 */
@RunWith(MockitoJUnitRunner.class)
public class EventStatsControllerMockTest {

    @Mock
    IEventStatsService eventStatsService;

    @InjectMocks
    EventStatsController eventStatsController;

    MockMvc mockMvc;

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(eventStatsController).build();
    }

    private EventStatsDTO buildStats() {
        Map<Tache, Long> parTache = new EnumMap<>(Tache.class);
        parTache.put(Tache.ORGANISATEUR, 1L);
        parTache.put(Tache.INVITE, 2L);
        return EventStatsDTO.builder()
                .idEvent(1)
                .description("Journée Portes Ouvertes")
                .dureeJours(3)
                .nbParticipants(3)
                .participantsParTache(parTache)
                .nbLogistics(3)
                .nbLogisticsReservees(2)
                .coutLogistiqueReservee(60f)
                .build();
    }

    @Test
    public void testGetEventStats() throws Exception {
        when(eventStatsService.getEventStats(1)).thenReturn(buildStats());

        mockMvc.perform(get("/event-stats/{id}", 1))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idEvent").value(1))
                .andExpect(jsonPath("$.nbParticipants").value(3))
                .andExpect(jsonPath("$.participantsParTache.INVITE").value(2))
                .andExpect(jsonPath("$.nbLogisticsReservees").value(2))
                .andExpect(jsonPath("$.coutLogistiqueReservee").value(60.0));

        verify(eventStatsService, times(1)).getEventStats(1);
    }

    @Test
    public void testGetUpcomingEventsStats() throws Exception {
        when(eventStatsService.getUpcomingEventsStats())
                .thenReturn(Collections.singletonList(buildStats()));

        mockMvc.perform(get("/event-stats/upcoming"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].description").value("Journée Portes Ouvertes"));

        verify(eventStatsService).getUpcomingEventsStats();
    }

    @Test
    public void testGetEventsStatsBetween() throws Exception {
        LocalDate d1 = LocalDate.of(2025, 5, 1);
        LocalDate d2 = LocalDate.of(2025, 5, 31);
        when(eventStatsService.getEventsStatsBetween(d1, d2))
                .thenReturn(Collections.singletonList(buildStats()));

        mockMvc.perform(get("/event-stats/between/{d1}/{d2}", "2025-05-01", "2025-05-31"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].idEvent").value(1));

        verify(eventStatsService, times(1)).getEventsStatsBetween(d1, d2);
    }

    @Test
    public void testGetAllEventsStats() throws Exception {
        when(eventStatsService.getAllEventsStats())
                .thenReturn(Collections.singletonList(buildStats()));

        mockMvc.perform(get("/event-stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].nbLogistics").value(3));

        verify(eventStatsService).getAllEventsStats();
    }

    @Test
    public void testGetGlobalStats() throws Exception {
        GlobalStatsDTO global = GlobalStatsDTO.builder()
                .nbEvents(6)
                .nbEventsAVenir(4)
                .nbParticipants(12)
                .nbLogistics(20)
                .nbLogisticsReservees(15)
                .tauxReservation(75f)
                .coutTotalLogistiqueReservee(9876.5f)
                .build();
        when(eventStatsService.getGlobalStats()).thenReturn(global);

        mockMvc.perform(get("/event-stats/summary"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nbEvents").value(6))
                .andExpect(jsonPath("$.nbEventsAVenir").value(4))
                .andExpect(jsonPath("$.tauxReservation").value(75.0));

        verify(eventStatsService, times(1)).getGlobalStats();
    }
}
