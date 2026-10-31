package tn.fst.eventsproject.controllers;

import org.junit.Before;
import org.junit.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.fst.eventsproject.dto.EventStatsDTO;
import tn.fst.eventsproject.dto.GlobalStatsDTO;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.services.IEventStatsService;

import java.time.LocalDate;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

import static org.hamcrest.Matchers.hasSize;
import static org.junit.Assert.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Test du contrôleur statistiques SANS Mockito : le service est remplacé par une
 * implémentation factice écrite à la main (FakeEventStatsService).
 * Aucune base de données, aucun contexte Spring complet, aucune bibliothèque de mock.
 */
public class EventStatsControllerNoMockTest {

    /** Faux service : renvoie des données fixes et compte les appels (remplace verify()). */
    static class FakeEventStatsService implements IEventStatsService {

        int getEventStatsCalls;
        int getUpcomingCalls;
        int getBetweenCalls;
        int getAllCalls;
        int getGlobalCalls;

        Integer lastRequestedId;
        LocalDate lastFrom;
        LocalDate lastTo;

        private final EventStatsDTO stats;
        private final GlobalStatsDTO global;

        FakeEventStatsService(EventStatsDTO stats, GlobalStatsDTO global) {
            this.stats = stats;
            this.global = global;
        }

        @Override
        public EventStatsDTO getEventStats(int idEvent) {
            getEventStatsCalls++;
            lastRequestedId = idEvent;
            return stats;
        }

        @Override
        public List<EventStatsDTO> getUpcomingEventsStats() {
            getUpcomingCalls++;
            return Collections.singletonList(stats);
        }

        @Override
        public List<EventStatsDTO> getEventsStatsBetween(LocalDate d1, LocalDate d2) {
            getBetweenCalls++;
            lastFrom = d1;
            lastTo = d2;
            return Collections.singletonList(stats);
        }

        @Override
        public List<EventStatsDTO> getAllEventsStats() {
            getAllCalls++;
            return Collections.singletonList(stats);
        }

        @Override
        public GlobalStatsDTO getGlobalStats() {
            getGlobalCalls++;
            return global;
        }
    }

    FakeEventStatsService fakeService;
    MockMvc mockMvc;

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

    private GlobalStatsDTO buildGlobal() {
        return GlobalStatsDTO.builder()
                .nbEvents(6)
                .nbEventsAVenir(4)
                .nbParticipants(12)
                .nbLogistics(20)
                .nbLogisticsReservees(15)
                .tauxReservation(75f)
                .coutTotalLogistiqueReservee(9876.5f)
                .build();
    }

    @Before
    public void setUp() {
        fakeService = new FakeEventStatsService(buildStats(), buildGlobal());
        // Injection par constructeur (voir la note si votre contrôleur utilise @Autowired sur un champ)
        EventStatsController controller = new EventStatsController(fakeService);
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    @Test
    public void testGetEventStats() throws Exception {
        mockMvc.perform(get("/event-stats/{id}", 1))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idEvent").value(1))
                .andExpect(jsonPath("$.nbParticipants").value(3))
                .andExpect(jsonPath("$.participantsParTache.INVITE").value(2))
                .andExpect(jsonPath("$.nbLogisticsReservees").value(2))
                .andExpect(jsonPath("$.coutLogistiqueReservee").value(60.0));

        assertEquals(1, fakeService.getEventStatsCalls);
        assertEquals(Integer.valueOf(1), fakeService.lastRequestedId);
    }

    @Test
    public void testGetUpcomingEventsStats() throws Exception {
        mockMvc.perform(get("/event-stats/upcoming"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].description").value("Journée Portes Ouvertes"));

        assertEquals(1, fakeService.getUpcomingCalls);
    }

    @Test
    public void testGetEventsStatsBetween() throws Exception {
        mockMvc.perform(get("/event-stats/between/{d1}/{d2}", "2025-05-01", "2025-05-31"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].idEvent").value(1));

        assertEquals(1, fakeService.getBetweenCalls);
        assertEquals(LocalDate.of(2025, 5, 1), fakeService.lastFrom);
        assertEquals(LocalDate.of(2025, 5, 31), fakeService.lastTo);
    }

    @Test
    public void testGetAllEventsStats() throws Exception {
        mockMvc.perform(get("/event-stats"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].nbLogistics").value(3));

        assertEquals(1, fakeService.getAllCalls);
    }

    @Test
    public void testGetGlobalStats() throws Exception {
        mockMvc.perform(get("/event-stats/summary"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nbEvents").value(6))
                .andExpect(jsonPath("$.nbEventsAVenir").value(4))
                .andExpect(jsonPath("$.tauxReservation").value(75.0));

        assertEquals(1, fakeService.getGlobalCalls);
    }
}