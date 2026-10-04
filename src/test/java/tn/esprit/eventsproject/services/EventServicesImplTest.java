package tn.esprit.eventsproject.services;

import lombok.extern.slf4j.Slf4j;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;
import tn.esprit.eventsproject.entities.Event;

import java.time.LocalDate;

import static org.junit.Assert.*;

/**
 * SANS Mockito : test d'intégration (vraie base de données).
 */
@RunWith(SpringRunner.class)
@SpringBootTest
@Slf4j
public class EventServicesImplTest {

    @Autowired
    IEventServices eventServices;

    private Event buildEvent() {
        Event e = new Event();
        e.setDescription("Journée Portes Ouvertes");
        e.setDateDebut(LocalDate.of(2025, 5, 10));
        e.setDateFin(LocalDate.of(2025, 5, 12));
        e.setCout(1500f);
        return e;
    }

    @Test
    public void testAddEvent() {
        Event saved = eventServices.addEvent(buildEvent());
        log.info("event added : {}", saved);

        assertNotNull(saved);
        assertTrue(saved.getIdEvent() > 0);
        assertEquals("Journée Portes Ouvertes", saved.getDescription());
        assertEquals(1500f, saved.getCout(), 0.001);

        eventServices.deleteEvent(saved.getIdEvent());
    }

    @Test
    public void testRetrieveEvent() {
        Event saved = eventServices.addEvent(buildEvent());

        Event found = eventServices.retrieveEvent(saved.getIdEvent());

        assertNotNull(found);
        assertEquals(saved.getIdEvent(), found.getIdEvent());
        assertEquals(LocalDate.of(2025, 5, 10), found.getDateDebut());

        eventServices.deleteEvent(saved.getIdEvent());
    }

    @Test
    public void testUpdateEvent() {
        Event saved = eventServices.addEvent(buildEvent());

        saved.setDescription("Hackathon");
        saved.setCout(3000f);
        Event updated = eventServices.updateEvent(saved);

        assertEquals(saved.getIdEvent(), updated.getIdEvent());
        assertEquals("Hackathon", updated.getDescription());
        assertEquals(3000f, updated.getCout(), 0.001);

        eventServices.deleteEvent(saved.getIdEvent());
    }

    @Test
    public void testDeleteEvent() {
        Event saved = eventServices.addEvent(buildEvent());
        int id = saved.getIdEvent();

        eventServices.deleteEvent(id);

        assertNull(eventServices.retrieveEvent(id));
    }
}
