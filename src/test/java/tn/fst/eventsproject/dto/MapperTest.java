package tn.fst.eventsproject.dto;

import org.junit.Test;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;

import java.util.Collections;

import static org.junit.Assert.*;

public class MapperTest {

    @Test
    public void participantRoundTripKeepsFieldsAndShortEvents() {
        Event e = new Event();
        e.setIdEvent(3);
        e.setDescription("Gala");
        e.setLogistics(Collections.singleton(new Logistics()));
        Participant p = new Participant();
        p.setIdPart(1);
        p.setNom("Tounsi");
        p.setTache(Tache.SERVEUR);
        p.setEvents(Collections.singleton(e));

        ParticipantDTO d = Mapper.toDto(p);
        assertEquals("Tounsi", d.getNom());
        assertEquals(Tache.SERVEUR, d.getTache());
        EventDTO de = d.getEvents().iterator().next();
        assertEquals(3, de.getIdEvent());
        assertNull(de.getLogistics());
        assertEquals("Tounsi", Mapper.toEntity(d).getNom());
    }

    @Test
    public void eventWithoutParticipantsGetsEmptySet() {
        Event e = Mapper.toEntity(new EventDTO());
        assertNotNull(e.getParticipants());
        assertTrue(e.getParticipants().isEmpty());
    }

    @Test
    public void nullLogisticsListStaysNull() {
        assertNull(Mapper.toLogisticsDtos(null));
    }
}
