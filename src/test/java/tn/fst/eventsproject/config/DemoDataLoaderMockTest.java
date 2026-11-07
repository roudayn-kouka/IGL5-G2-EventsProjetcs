package tn.fst.eventsproject.config;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.util.List;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * AVEC Mockito : chargement des données de démonstration (base vide / base déjà remplie).
 */
@RunWith(MockitoJUnitRunner.class)
public class DemoDataLoaderMockTest {

    @Mock
    EventRepository eventRepository;
    @Mock
    ParticipantRepository participantRepository;
    @Mock
    LogisticsRepository logisticsRepository;

    @InjectMocks
    DemoDataLoader demoDataLoader;

    @Test
    public void testBaseDejaRemplieAucuneInsertion() {
        when(eventRepository.count()).thenReturn(3L);

        demoDataLoader.run();

        verify(eventRepository, never()).save(any(Event.class));
        verifyNoInteractions(participantRepository, logisticsRepository);
    }

    @Test
    public void testBaseVideInsereLesDonneesDeDemo() {
        when(eventRepository.count()).thenReturn(0L, 6L);
        when(logisticsRepository.save(any(Logistics.class))).thenAnswer(i -> i.getArgument(0));
        when(eventRepository.save(any(Event.class))).thenAnswer(i -> i.getArgument(0));

        demoDataLoader.run();

        ArgumentCaptor<Event> events = ArgumentCaptor.forClass(Event.class);
        verify(eventRepository, times(6)).save(events.capture());
        verify(logisticsRepository, times(18)).save(any(Logistics.class));
        ArgumentCaptor<Participant> participants = ArgumentCaptor.forClass(Participant.class);
        verify(participantRepository, times(12)).save(participants.capture());

        Event jpo = events.getAllValues().get(0);
        assertEquals("Journée Portes Ouvertes FST", jpo.getDescription());
        assertEquals(4, jpo.getLogistics().size());

        // L'organisateur « Tounsi Ahmed » est celui utilisé par le calcul planifié du coût
        Participant tounsi = participants.getAllValues().get(0);
        assertEquals("Tounsi", tounsi.getNom());
        assertEquals(Tache.ORGANISATEUR, tounsi.getTache());
        assertEquals(4, tounsi.getEvents().size());

        List<Participant> all = participants.getAllValues();
        assertTrue(all.stream().allMatch(p -> !p.getEvents().isEmpty()));
    }
}
