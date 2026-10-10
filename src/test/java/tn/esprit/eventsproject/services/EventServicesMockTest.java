package tn.esprit.eventsproject.services;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import tn.esprit.eventsproject.entities.Event;
import tn.esprit.eventsproject.repositories.EventRepository;
import tn.esprit.eventsproject.repositories.LogisticsRepository;
import tn.esprit.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.Optional;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

/**
 * AVEC Mockito : test unitaire (repositories simulés, pas de base de données).
 */
@RunWith(MockitoJUnitRunner.Silent.class)
public class EventServicesMockTest {

    @Mock
    EventRepository eventRepository;
    @Mock
    ParticipantRepository participantRepository;
    @Mock
    LogisticsRepository logisticsRepository;

    @InjectMocks
    EventServicesImpl eventServices;

    private Event buildEvent(int id) {
        Event e = new Event();
        e.setIdEvent(id);
        e.setDescription("Journée Portes Ouvertes");
        e.setDateDebut(LocalDate.of(2025, 5, 10));
        e.setDateFin(LocalDate.of(2025, 5, 12));
        e.setCout(1500f);
        return e;
    }

    @Test
    public void testAddEvent() {
        Event event = buildEvent(1);
        when(eventRepository.save(event)).thenReturn(event);

        Event result = eventServices.addEvent(event);

        assertNotNull(result);
        assertEquals(1, result.getIdEvent());
        assertEquals("Journée Portes Ouvertes", result.getDescription());
        verify(eventRepository, times(1)).save(event);
    }

    @Test
    public void testRetrieveEvent() {
        Event event = buildEvent(1);
        when(eventRepository.findById(1)).thenReturn(Optional.of(event));

        Event result = eventServices.retrieveEvent(1);

        assertNotNull(result);
        assertEquals(1500f, result.getCout(), 0.001);
        verify(eventRepository).findById(1);
    }

    @Test
    public void testRetrieveEventNotFound() {
        when(eventRepository.findById(99)).thenReturn(Optional.empty());

        assertNull(eventServices.retrieveEvent(99));
    }

    @Test
    public void testUpdateEvent() {
        Event event = buildEvent(1);
        event.setDescription("Hackathon");
        event.setCout(3000f);
        when(eventRepository.save(event)).thenReturn(event);

        Event result = eventServices.updateEvent(event);

        assertEquals("Hackathon", result.getDescription());
        assertEquals(3000f, result.getCout(), 0.001);
        verify(eventRepository, times(1)).save(event);
    }

    @Test
    public void testDeleteEvent() {
        doNothing().when(eventRepository).deleteById(1);

        eventServices.deleteEvent(1);

        verify(eventRepository, times(1)).deleteById(1);
    }
}
