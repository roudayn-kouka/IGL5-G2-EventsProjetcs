package tn.fst.eventsproject.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EventServicesImplMockitoTest {

    @Mock
    private EventRepository eventRepository;

    @Mock
    private ParticipantRepository participantRepository;

    @Mock
    private LogisticsRepository logisticsRepository;

    @InjectMocks
    private EventServicesImpl service;

    @Test
    void associatesParticipantWhenEventsCollectionIsNull() {
        Event event = new Event();
        Participant participant = new Participant();
        when(participantRepository.findById(3)).thenReturn(Optional.of(participant));
        when(eventRepository.save(event)).thenReturn(event);

        assertSame(event, service.addAffectEvenParticipant(event, 3));

        assertEquals(Set.of(event), participant.getEvents());
        verify(eventRepository).save(event);
    }

    @Test
    void addsEventToExistingParticipantEvents() {
        Event existing = new Event();
        Event added = new Event();
        Participant participant = new Participant();
        participant.setEvents(new HashSet<>(Set.of(existing)));
        when(participantRepository.findById(3)).thenReturn(Optional.of(participant));
        when(eventRepository.save(added)).thenReturn(added);

        service.addAffectEvenParticipant(added, 3);

        assertEquals(Set.of(existing, added), participant.getEvents());
    }

    @Test
    void rejectsMissingParticipantForSingleAssociation() {
        Event event = new Event();
        when(participantRepository.findById(3)).thenReturn(Optional.empty());

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.addAffectEvenParticipant(event, 3));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        verify(eventRepository, never()).save(any(Event.class));
    }

    @Test
    void rejectsEventWithNullParticipantSet() {
        Event event = new Event();
        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.addAffectEvenParticipant(event));

        assertEquals(HttpStatus.BAD_REQUEST, error.getStatus());
        verifyNoInteractions(participantRepository, eventRepository);
    }

    @Test
    void associatesAllParticipantsForNullAndExistingEventCollections() {
        Event event = new Event();
        Participant firstReference = new Participant();
        firstReference.setIdPart(1);
        Participant secondReference = new Participant();
        secondReference.setIdPart(2);
        event.setParticipants(Set.of(firstReference, secondReference));

        Participant first = new Participant();
        Participant second = new Participant();
        Event existingEvent = new Event();
        second.setEvents(new HashSet<>(Set.of(existingEvent)));
        when(participantRepository.findById(1)).thenReturn(Optional.of(first));
        when(participantRepository.findById(2)).thenReturn(Optional.of(second));
        when(eventRepository.save(event)).thenReturn(event);

        assertSame(event, service.addAffectEvenParticipant(event));

        assertEquals(Set.of(event), first.getEvents());
        assertEquals(Set.of(existingEvent, event), second.getEvents());
    }

    @Test
    void rejectsMissingParticipantInEventAssociationSet() {
        Event event = new Event();
        Participant reference = new Participant();
        reference.setIdPart(42);
        event.setParticipants(Set.of(reference));
        when(participantRepository.findById(42)).thenReturn(Optional.empty());

        ResponseStatusException error = assertThrows(ResponseStatusException.class,
                () -> service.addAffectEvenParticipant(event));

        assertEquals(HttpStatus.NOT_FOUND, error.getStatus());
        verify(eventRepository, never()).save(any(Event.class));
    }

    @Test
    void addsLogisticsAndSavesEventWhenCollectionIsNull() {
        Logistics logistics = new Logistics();
        Event event = new Event();
        when(eventRepository.findByDescription("Conference")).thenReturn(event);
        when(logisticsRepository.save(logistics)).thenReturn(logistics);

        assertSame(logistics, service.addAffectLog(logistics, "Conference"));

        assertEquals(Set.of(logistics), event.getLogistics());
        verify(eventRepository).save(event);
    }

    @Test
    void addsLogisticsToExistingCollectionWithoutResavingEvent() {
        Logistics existing = new Logistics();
        Logistics added = new Logistics();
        Event event = new Event();
        event.setLogistics(new HashSet<>(Set.of(existing)));
        when(eventRepository.findByDescription("Conference")).thenReturn(event);
        when(logisticsRepository.save(added)).thenReturn(added);

        service.addAffectLog(added, "Conference");

        assertEquals(Set.of(existing, added), event.getLogistics());
        verify(eventRepository, never()).save(event);
    }

    @Test
    void returnsOnlyReservedLogisticsAndHandlesEventsWithoutLogistics() {
        Event emptyEvent = new Event();
        emptyEvent.setLogistics(new HashSet<>());
        Event event = new Event();
        Logistics reserved = new Logistics();
        reserved.setReserve(true);
        Logistics unreserved = new Logistics();
        unreserved.setReserve(false);
        event.setLogistics(new HashSet<>(Set.of(reserved, unreserved)));
        when(eventRepository.findByDateDebutBetween(any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(List.of(emptyEvent, event));

        List<Logistics> result = service.getLogisticsDates(
                LocalDate.of(2026, 1, 1), LocalDate.of(2026, 12, 31));

        assertEquals(List.of(reserved), result);
    }

    @Test
    void calculatesReservedCostsIndependentlyAndTreatsNullLogisticsAsEmpty() {
        Event withoutLogistics = new Event();
        Event withLogistics = new Event();
        Logistics reserved = new Logistics();
        reserved.setReserve(true);
        reserved.setPrixUnit(12.5f);
        reserved.setQuantite(4);
        Logistics unreserved = new Logistics();
        unreserved.setReserve(false);
        unreserved.setPrixUnit(100.0f);
        unreserved.setQuantite(3);
        withLogistics.setLogistics(new HashSet<>(Set.of(reserved, unreserved)));
        when(eventRepository.findByParticipants_NomAndParticipants_PrenomAndParticipants_Tache(
                "Tounsi", "Ahmed", Tache.ORGANISATEUR)).thenReturn(List.of(withoutLogistics, withLogistics));
        when(eventRepository.save(any(Event.class))).thenAnswer(invocation -> invocation.getArgument(0));

        service.calculCout();

        assertEquals(0.0f, withoutLogistics.getCout());
        assertEquals(50.0f, withLogistics.getCout());
        verify(eventRepository).save(withoutLogistics);
        verify(eventRepository).save(withLogistics);
    }
}
