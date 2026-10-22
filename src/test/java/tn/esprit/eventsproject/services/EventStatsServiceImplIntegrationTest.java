package tn.esprit.eventsproject.services;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;
import org.springframework.transaction.annotation.Transactional;
import tn.esprit.eventsproject.dto.EventStatsDTO;
import tn.esprit.eventsproject.entities.Event;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.repositories.EventRepository;
import tn.esprit.eventsproject.repositories.LogisticsRepository;
import tn.esprit.eventsproject.repositories.ParticipantRepository;

import javax.persistence.EntityManager;
import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;

import static org.junit.Assert.*;

/**
 * SANS Mockito : test d'intégration de la feature statistiques
 * (vrai service + vrais repositories + base H2 en mémoire).
 * @Transactional annule les données après chaque test.
 */
@RunWith(SpringRunner.class)
@SpringBootTest
@Transactional
public class EventStatsServiceImplIntegrationTest {

    @Autowired
    IEventStatsService eventStatsService;
    @Autowired
    EventRepository eventRepository;
    @Autowired
    ParticipantRepository participantRepository;
    @Autowired
    LogisticsRepository logisticsRepository;
    @Autowired
    EntityManager entityManager;

    private Logistics saveLogistics(String description, boolean reserve, float prixUnit, int quantite) {
        Logistics l = new Logistics();
        l.setDescription(description);
        l.setReserve(reserve);
        l.setPrixUnit(prixUnit);
        l.setQuantite(quantite);
        return logisticsRepository.save(l);
    }

    private void saveParticipant(String nom, Tache tache, Event event) {
        Participant p = new Participant();
        p.setNom(nom);
        p.setPrenom("Test");
        p.setTache(tache);
        p.setEvents(new HashSet<>(Collections.singletonList(event))); // Participant = côté propriétaire
        participantRepository.save(p);
    }

    private Event saveEvent(String description, LocalDate debut, LocalDate fin) {
        Event e = new Event();
        e.setDescription(description);
        e.setDateDebut(debut);
        e.setDateFin(fin);
        e.setLogistics(new HashSet<>(Arrays.asList(
                saveLogistics("Chaises", true, 12.5f, 40),  // 500
                saveLogistics("Tables", true, 50f, 2),      // 100
                saveLogistics("Sono", false, 300f, 1))));   // non réservée
        return eventRepository.save(e);
    }

    /** Écrit en base puis vide le cache JPA pour relire l'Event avec ses participants. */
    private void flushAndClear() {
        entityManager.flush();
        entityManager.clear();
    }

    @Test
    public void testGetEventStats() {
        Event event = saveEvent("Hackathon", LocalDate.of(2025, 5, 10), LocalDate.of(2025, 5, 11));
        saveParticipant("Tounsi", Tache.ORGANISATEUR, event);
        saveParticipant("Ben Ali", Tache.ANIMATEUR, event);
        saveParticipant("Trabelsi", Tache.ANIMATEUR, event);
        flushAndClear();

        EventStatsDTO stats = eventStatsService.getEventStats(event.getIdEvent());

        assertEquals("Hackathon", stats.getDescription());
        assertEquals(2, stats.getDureeJours());
        assertEquals(3, stats.getNbParticipants());
        assertEquals(Long.valueOf(2), stats.getParticipantsParTache().get(Tache.ANIMATEUR));
        assertEquals(Long.valueOf(1), stats.getParticipantsParTache().get(Tache.ORGANISATEUR));
        assertEquals(3, stats.getNbLogistics());
        assertEquals(2, stats.getNbLogisticsReservees());
        assertEquals(600f, stats.getCoutLogistiqueReservee(), 0.001);
    }

    @Test
    public void testGetUpcomingEventsStats() {
        LocalDate today = LocalDate.now();
        Event passe = saveEvent("Event passé", today.minusDays(10), today.minusDays(9));
        Event proche = saveEvent("Event proche", today.plusDays(2), today.plusDays(3));
        Event lointain = saveEvent("Event lointain", today.plusDays(30), today.plusDays(31));
        flushAndClear();

        List<EventStatsDTO> upcoming = eventStatsService.getUpcomingEventsStats();

        List<Integer> ids = new java.util.ArrayList<>();
        for (EventStatsDTO s : upcoming) {
            ids.add(s.getIdEvent());
        }
        assertFalse(ids.contains(passe.getIdEvent()));
        assertTrue(ids.contains(proche.getIdEvent()));
        assertTrue(ids.contains(lointain.getIdEvent()));
        // tri par date de début croissante
        assertTrue(ids.indexOf(proche.getIdEvent()) < ids.indexOf(lointain.getIdEvent()));
    }

    @Test
    public void testGetEventsStatsBetween() {
        Event mai = saveEvent("Event mai", LocalDate.of(2025, 5, 15), LocalDate.of(2025, 5, 16));
        Event juillet = saveEvent("Event juillet", LocalDate.of(2025, 7, 15), LocalDate.of(2025, 7, 16));
        flushAndClear();

        List<EventStatsDTO> result = eventStatsService.getEventsStatsBetween(
                LocalDate.of(2025, 5, 1), LocalDate.of(2025, 5, 31));

        List<Integer> ids = new java.util.ArrayList<>();
        for (EventStatsDTO s : result) {
            ids.add(s.getIdEvent());
        }
        assertTrue(ids.contains(mai.getIdEvent()));
        assertFalse(ids.contains(juillet.getIdEvent()));
    }
}
