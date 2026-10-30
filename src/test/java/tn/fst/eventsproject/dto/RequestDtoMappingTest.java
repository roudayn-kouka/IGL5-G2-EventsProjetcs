package tn.fst.eventsproject.dto;

import org.junit.jupiter.api.Test;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;

import java.time.LocalDate;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

class RequestDtoMappingTest {

    @Test
    void eventRequestMapsFieldsAndRelatedEntityReferences() {
        ParticipantWriteRequest participant = new ParticipantWriteRequest();
        participant.setIdPart(7);

        LogisticsWriteRequest logistics = new LogisticsWriteRequest();
        logistics.setIdLog(9);
        logistics.setDescription("Sound system");
        logistics.setReserve(true);
        logistics.setPrixUnit(12.5f);
        logistics.setQuantite(4);

        EventWriteRequest request = new EventWriteRequest();
        request.setIdEvent(3);
        request.setDescription("Conference");
        request.setDateDebut(LocalDate.of(2026, 10, 1));
        request.setDateFin(LocalDate.of(2026, 10, 2));
        request.setCout(50.0f);
        request.setParticipants(Set.of(participant));
        request.setLogistics(Set.of(logistics));

        Event event = request.toEntity();

        assertAll(
                () -> assertEquals(3, event.getIdEvent()),
                () -> assertEquals("Conference", event.getDescription()),
                () -> assertEquals(LocalDate.of(2026, 10, 1), event.getDateDebut()),
                () -> assertEquals(LocalDate.of(2026, 10, 2), event.getDateFin()),
                () -> assertEquals(50.0f, event.getCout()),
                () -> assertEquals(7, event.getParticipants().iterator().next().getIdPart()),
                () -> assertEquals("Sound system", event.getLogistics().iterator().next().getDescription())
        );
    }

    @Test
    void eventRequestAllowsOmittedRelationships() {
        Event event = new EventWriteRequest().toEntity();

        assertNull(event.getParticipants());
        assertNull(event.getLogistics());
    }

    @Test
    void participantRequestMapsProfileAndEventReferences() {
        ParticipantWriteRequest.EventReference eventReference = new ParticipantWriteRequest.EventReference();
        eventReference.setIdEvent(4);

        ParticipantWriteRequest request = new ParticipantWriteRequest();
        request.setIdPart(12);
        request.setNom("Doe");
        request.setPrenom("Jane");
        request.setTache(Tache.ORGANISATEUR);
        request.setEvents(Set.of(eventReference));

        Participant participant = request.toEntity();

        assertAll(
                () -> assertEquals(0, participant.getIdPart(), "creation must leave the generated id unset"),
                () -> assertEquals("Doe", participant.getNom()),
                () -> assertEquals("Jane", participant.getPrenom()),
                () -> assertEquals(Tache.ORGANISATEUR, participant.getTache()),
                () -> assertEquals(4, participant.getEvents().iterator().next().getIdEvent())
        );
    }

    @Test
    void participantRequestAllowsOmittedEventsAndMapsAssociationReference() {
        ParticipantWriteRequest request = new ParticipantWriteRequest();
        request.setIdPart(12);

        Participant participant = request.toEntity();
        Participant reference = request.toReferenceEntity();

        assertNull(participant.getEvents());
        assertEquals(12, reference.getIdPart());
    }

    @Test
    void logisticsRequestMapsAllWritableFields() {
        LogisticsWriteRequest request = new LogisticsWriteRequest();
        request.setIdLog(5);
        request.setDescription("Projector");
        request.setReserve(true);
        request.setPrixUnit(20.0f);
        request.setQuantite(2);

        Logistics logistics = request.toEntity();

        assertAll(
                () -> assertEquals(5, logistics.getIdLog()),
                () -> assertEquals("Projector", logistics.getDescription()),
                () -> assertTrue(logistics.isReserve()),
                () -> assertEquals(20.0f, logistics.getPrixUnit()),
                () -> assertEquals(2, logistics.getQuantite())
        );
    }
}
