package tn.fst.eventsproject.services;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Feedback;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.repositories.*;

import java.time.*;
import java.util.Collections;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class FeedbackServiceTest {
    @Mock FeedbackRepository feedbackRepository;
    @Mock EventRepository eventRepository;
    @Mock ParticipantRepository participantRepository;
    FeedbackService service;
    final Clock clock = Clock.fixed(Instant.parse("2026-10-27T12:00:00Z"), ZoneId.of("Africa/Tunis"));
    Event event;
    Participant participant;

    @BeforeEach
    void setup() {
        service = new FeedbackService(feedbackRepository, eventRepository, participantRepository, clock);
        event = new Event();
        event.setIdEvent(1);
        event.setDateFin(LocalDate.now(clock).minusDays(1));
        participant = new Participant();
        participant.setIdPart(2);
        participant.setEvents(Collections.singleton(event));
    }

    void eligible() {
        when(eventRepository.findById(1)).thenReturn(Optional.of(event));
        when(participantRepository.findById(2)).thenReturn(Optional.of(participant));
    }

    void assertStatus(HttpStatus status, Runnable operation) {
        assertEquals(status, assertThrows(ResponseStatusException.class, operation::run).getStatus());
    }

    @Test
    void createsWithServerTimestamp() {
        eligible();
        when(feedbackRepository.saveAndFlush(any())).thenAnswer(invocation -> invocation.getArgument(0));
        Feedback result = service.createFeedback(1, 2, 5, "Great");
        assertEquals(5, result.getNote());
        assertEquals("Great", result.getCommentaire());
        assertEquals(clock.instant(), result.getDate());
        assertSame(event, result.getEvent());
        assertSame(participant, result.getParticipant());
    }

    @ParameterizedTest
    @NullSource
    @ValueSource(ints = {0, -1, 6})
    void rejectsInvalidRating(Integer note) {
        assertStatus(HttpStatus.BAD_REQUEST, () -> service.createFeedback(1, 2, note, null));
        verifyNoInteractions(eventRepository, participantRepository, feedbackRepository);
    }

    @Test
    void rejectsMissingEvent() {
        assertStatus(HttpStatus.NOT_FOUND, () -> service.createFeedback(1, 2, 5, null));
    }

    @Test
    void rejectsMissingParticipant() {
        when(eventRepository.findById(1)).thenReturn(Optional.of(event));
        assertStatus(HttpStatus.NOT_FOUND, () -> service.createFeedback(1, 2, 5, null));
    }

    @Test
    void rejectsUnassociatedParticipant() {
        eligible();
        participant.setEvents(Collections.emptySet());
        assertStatus(HttpStatus.BAD_REQUEST, () -> service.createFeedback(1, 2, 5, null));
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 1})
    void rejectsEventsEndingTodayOrLater(int days) {
        eligible();
        event.setDateFin(LocalDate.now(clock).plusDays(days));
        assertStatus(HttpStatus.BAD_REQUEST, () -> service.createFeedback(1, 2, 5, null));
    }

    @Test
    void rejectsUnknownEndDate() {
        eligible();
        event.setDateFin(null);
        assertStatus(HttpStatus.BAD_REQUEST, () -> service.createFeedback(1, 2, 5, null));
    }

    @Test
    void rejectsDuplicate() {
        eligible();
        when(feedbackRepository.existsByEvent_IdEventAndParticipant_IdPart(1, 2)).thenReturn(true);
        assertStatus(HttpStatus.CONFLICT, () -> service.createFeedback(1, 2, 5, null));
        verify(feedbackRepository, never()).saveAndFlush(any());
    }

    @Test
    void deletesExistingFeedback() {
        Feedback feedback = new Feedback();
        when(feedbackRepository.findById(3)).thenReturn(Optional.of(feedback));
        service.deleteFeedback(3);
        verify(feedbackRepository).delete(feedback);
    }

    @Test
    void rejectsDeletingMissingFeedback() {
        assertStatus(HttpStatus.NOT_FOUND, () -> service.deleteFeedback(3));
    }

    @Test
    void retrievesFeedbackAndAverage() {
        when(eventRepository.existsById(1)).thenReturn(true);
        Feedback feedback = new Feedback();
        when(feedbackRepository.findByEvent_IdEventOrderByDateAscIdAsc(1)).thenReturn(Collections.singletonList(feedback));
        when(feedbackRepository.averageRatingByEvent(1)).thenReturn(4.5);
        when(feedbackRepository.countByEvent_IdEvent(1)).thenReturn(2L);
        assertSame(feedback, service.getFeedbackByEvent(1).get(0));
        assertEquals(4.5, service.getAverageRatingByEvent(1).getAverageRating());
        assertEquals(2, service.getAverageRatingByEvent(1).getTotalFeedbacks());
    }

    @Test
    void emptyEventHasEmptyListAndZeroAverage() {
        when(eventRepository.existsById(1)).thenReturn(true);
        assertTrue(service.getFeedbackByEvent(1).isEmpty());
        assertEquals(0.0, service.getAverageRatingByEvent(1).getAverageRating());
        assertEquals(0, service.getAverageRatingByEvent(1).getTotalFeedbacks());
    }

    @Test
    void readsRejectMissingEvent() {
        assertStatus(HttpStatus.NOT_FOUND, () -> service.getFeedbackByEvent(1));
        assertStatus(HttpStatus.NOT_FOUND, () -> service.getAverageRatingByEvent(1));
    }
}
