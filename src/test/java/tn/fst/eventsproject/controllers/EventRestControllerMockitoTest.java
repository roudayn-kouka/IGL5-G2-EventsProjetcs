package tn.fst.eventsproject.controllers;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import tn.fst.eventsproject.dto.EventWriteRequest;
import tn.fst.eventsproject.dto.LogisticsWriteRequest;
import tn.fst.eventsproject.dto.ParticipantWriteRequest;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.services.IEventServices;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EventRestControllerMockitoTest {

    @Mock
    private IEventServices eventServices;

    @InjectMocks
    private EventRestController controller;

    @Test
    void addParticipantMapsRequestAndReturnsServiceResult() {
        ParticipantWriteRequest request = new ParticipantWriteRequest();
        request.setNom("Doe");
        request.setPrenom("Jane");
        Participant expected = new Participant();
        when(eventServices.addParticipant(any(Participant.class))).thenReturn(expected);

        assertSame(expected, controller.addParticipant(request));
        verify(eventServices).addParticipant(any(Participant.class));
    }

    @Test
    void addEventForParticipantMapsRequestAndPassesPathId() {
        EventWriteRequest request = new EventWriteRequest();
        request.setDescription("Conference");
        Event expected = new Event();
        when(eventServices.addAffectEvenParticipant(any(Event.class), org.mockito.ArgumentMatchers.eq(14)))
                .thenReturn(expected);

        assertSame(expected, controller.addEventPart(request, 14));
        verify(eventServices).addAffectEvenParticipant(any(Event.class), org.mockito.ArgumentMatchers.eq(14));
    }

    @Test
    void addEventMapsRequestAndReturnsServiceResult() {
        EventWriteRequest request = new EventWriteRequest();
        request.setDescription("Conference");
        Event expected = new Event();
        when(eventServices.addAffectEvenParticipant(any(Event.class))).thenReturn(expected);

        assertSame(expected, controller.addEvent(request));
        verify(eventServices).addAffectEvenParticipant(any(Event.class));
    }

    @Test
    void addLogisticsMapsRequestAndPassesEventDescription() {
        LogisticsWriteRequest request = new LogisticsWriteRequest();
        request.setDescription("Projector");
        Logistics expected = new Logistics();
        when(eventServices.addAffectLog(any(Logistics.class), org.mockito.ArgumentMatchers.eq("Conference")))
                .thenReturn(expected);

        assertSame(expected, controller.addAffectLog(request, "Conference"));
        verify(eventServices).addAffectLog(any(Logistics.class), org.mockito.ArgumentMatchers.eq("Conference"));
    }

    @Test
    void getLogisticsDatesPassesDateRangeToService() {
        LocalDate start = LocalDate.of(2026, 10, 1);
        LocalDate end = LocalDate.of(2026, 10, 31);
        List<Logistics> expected = List.of(new Logistics());
        when(eventServices.getLogisticsDates(start, end)).thenReturn(expected);

        assertSame(expected, controller.getLogistiquesDates(start, end));
        verify(eventServices).getLogisticsDates(start, end);
    }
}
