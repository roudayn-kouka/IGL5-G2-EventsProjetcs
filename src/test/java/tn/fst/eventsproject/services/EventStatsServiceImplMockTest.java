package tn.fst.eventsproject.services;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import tn.fst.eventsproject.dto.EventStatsDTO;
import tn.fst.eventsproject.dto.GlobalStatsDTO;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.FeedbackRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * AVEC Mockito : test unitaire de la feature statistiques
 * (repository simulé, pas de base de données).
 */
@RunWith(MockitoJUnitRunner.class)
public class EventStatsServiceImplMockTest {

    @Mock
    EventRepository eventRepository;
    @Mock
    ParticipantRepository participantRepository;
    @Mock
    LogisticsRepository logisticsRepository;

    @Mock
    FeedbackRepository feedbackRepository;

    @InjectMocks
    EventStatsServiceImpl eventStatsService;

    private Participant participant(int id, Tache tache) {
        Participant p = new Participant();
        p.setIdPart(id);
        p.setNom("Nom" + id);
        p.setPrenom("Prenom" + id);
        p.setTache(tache);
        return p;
    }

    private Logistics logistics(int id, boolean reserve, float prixUnit, int quantite) {
        Logistics l = new Logistics();
        l.setIdLog(id);
        l.setDescription("Log" + id);
        l.setReserve(reserve);
        l.setPrixUnit(prixUnit);
        l.setQuantite(quantite);
        return l;
    }

    private Event buildEvent(int id) {
        Event e = new Event();
        e.setIdEvent(id);
        e.setDescription("Journée Portes Ouvertes");
        e.setDateDebut(LocalDate.of(2025, 5, 10));
        e.setDateFin(LocalDate.of(2025, 5, 12));
        e.setParticipants(new HashSet<>(Arrays.asList(
                participant(1, Tache.ORGANISATEUR),
                participant(2, Tache.INVITE),
                participant(3, Tache.INVITE))));
        e.setLogistics(new HashSet<>(Arrays.asList(
                logistics(1, true, 10f, 5),    // 50
                logistics(2, true, 2.5f, 4),   // 10
                logistics(3, false, 100f, 1)))); // non réservée -> ignorée
        return e;
    }

    @Test
    public void testGetEventStats() {
        when(eventRepository.findById(1)).thenReturn(Optional.of(buildEvent(1)));
        when(feedbackRepository.averageRatingByEvent(1)).thenReturn(4.5);

        EventStatsDTO stats = eventStatsService.getEventStats(1);

        assertEquals(1, stats.getIdEvent());
        assertEquals(4.5, stats.getAverageRating(), 0.001);
        assertEquals("Journée Portes Ouvertes", stats.getDescription());
        assertEquals(3, stats.getDureeJours());
        assertEquals(3, stats.getNbParticipants());
        assertEquals(Long.valueOf(1), stats.getParticipantsParTache().get(Tache.ORGANISATEUR));
        assertEquals(Long.valueOf(2), stats.getParticipantsParTache().get(Tache.INVITE));
        assertEquals(Long.valueOf(0), stats.getParticipantsParTache().get(Tache.SERVEUR));
        assertEquals(3, stats.getNbLogistics());
        assertEquals(2, stats.getNbLogisticsReservees());
        assertEquals(60f, stats.getCoutLogistiqueReservee(), 0.001);
        verify(eventRepository, times(1)).findById(1);
    }

    @Test
    public void testGetEventStatsSansParticipantsNiLogistics() {
        Event e = new Event();
        e.setIdEvent(2);
        e.setDescription("Event vide");
        when(eventRepository.findById(2)).thenReturn(Optional.of(e));

        EventStatsDTO stats = eventStatsService.getEventStats(2);

        assertEquals(0, stats.getNbParticipants());
        assertEquals(0, stats.getNbLogistics());
        assertEquals(0, stats.getDureeJours());
        assertEquals(0f, stats.getCoutLogistiqueReservee(), 0.001);
    }

    @Test
    public void testGetEventStatsNotFound() {
        when(eventRepository.findById(99)).thenReturn(Optional.empty());

        try {
            eventStatsService.getEventStats(99);
            fail("Une ResponseStatusException était attendue");
        } catch (ResponseStatusException ex) {
            assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        }
    }

    @Test
    public void testGetUpcomingEventsStats() {
        when(eventRepository.findByDateDebutGreaterThanEqualOrderByDateDebutAsc(any(LocalDate.class)))
                .thenReturn(Arrays.asList(buildEvent(1), buildEvent(2)));

        List<EventStatsDTO> result = eventStatsService.getUpcomingEventsStats();

        assertEquals(2, result.size());
        assertEquals(1, result.get(0).getIdEvent());
        assertEquals(2, result.get(1).getIdEvent());
        verify(eventRepository).findByDateDebutGreaterThanEqualOrderByDateDebutAsc(LocalDate.now());
    }

    @Test
    public void testGetEventsStatsBetween() {
        LocalDate d1 = LocalDate.of(2025, 5, 1);
        LocalDate d2 = LocalDate.of(2025, 5, 31);
        when(eventRepository.findByDateDebutBetween(d1, d2))
                .thenReturn(Collections.singletonList(buildEvent(1)));

        List<EventStatsDTO> result = eventStatsService.getEventsStatsBetween(d1, d2);

        assertEquals(1, result.size());
        assertEquals(60f, result.get(0).getCoutLogistiqueReservee(), 0.001);
        verify(eventRepository, times(1)).findByDateDebutBetween(d1, d2);
    }

    @Test
    public void testGetEventsStatsBetweenIntervalleInvalide() {
        LocalDate d1 = LocalDate.of(2025, 6, 1);
        LocalDate d2 = LocalDate.of(2025, 5, 1);

        try {
            eventStatsService.getEventsStatsBetween(d1, d2);
            fail("Une ResponseStatusException était attendue");
        } catch (ResponseStatusException ex) {
            assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
        }
        verifyNoInteractions(eventRepository);
    }

    @Test
    public void testGetAllEventsStatsTrieParDate() {
        Event tard = buildEvent(1);
        tard.setDateDebut(LocalDate.of(2025, 9, 1));
        Event tot = buildEvent(2);
        tot.setDateDebut(LocalDate.of(2025, 3, 1));
        when(eventRepository.findAll()).thenReturn(Arrays.asList(tard, tot));

        List<EventStatsDTO> result = eventStatsService.getAllEventsStats();

        assertEquals(2, result.size());
        assertEquals(2, result.get(0).getIdEvent()); // le plus tôt en premier
        assertEquals(1, result.get(1).getIdEvent());
    }

    @Test
    public void testGetGlobalStats() {
        when(eventRepository.count()).thenReturn(4L);
        when(eventRepository.findByDateDebutGreaterThanEqualOrderByDateDebutAsc(any(LocalDate.class)))
                .thenReturn(Collections.singletonList(buildEvent(1)));
        when(participantRepository.count()).thenReturn(3L);
        when(participantRepository.findAll()).thenReturn(Arrays.asList(
                participant(1, Tache.ORGANISATEUR),
                participant(2, Tache.INVITE),
                participant(3, Tache.INVITE)));
        when(logisticsRepository.count()).thenReturn(4L);
        when(logisticsRepository.findByReserveTrue()).thenReturn(Arrays.asList(
                logistics(1, true, 10f, 5),     // 50
                logistics(2, true, 2.5f, 4)));  // 10

        GlobalStatsDTO stats = eventStatsService.getGlobalStats();

        assertEquals(4, stats.getNbEvents());
        assertEquals(1, stats.getNbEventsAVenir());
        assertEquals(3, stats.getNbParticipants());
        assertEquals(4, stats.getNbLogistics());
        assertEquals(2, stats.getNbLogisticsReservees());
        assertEquals(50f, stats.getTauxReservation(), 0.001);
        assertEquals(60f, stats.getCoutTotalLogistiqueReservee(), 0.001);
        assertEquals(Long.valueOf(2), stats.getParticipantsParTache().get(Tache.INVITE));
        assertEquals(Long.valueOf(0), stats.getParticipantsParTache().get(Tache.SERVEUR));
    }

    @Test
    public void testGetGlobalStatsBaseVide() {
        when(logisticsRepository.findByReserveTrue()).thenReturn(Collections.<Logistics>emptyList());
        when(logisticsRepository.count()).thenReturn(0L);

        GlobalStatsDTO stats = eventStatsService.getGlobalStats();

        assertEquals(0, stats.getNbEvents());
        assertEquals(0f, stats.getTauxReservation(), 0.001); // pas de division par zéro
        assertEquals(0f, stats.getCoutTotalLogistiqueReservee(), 0.001);
    }
}
