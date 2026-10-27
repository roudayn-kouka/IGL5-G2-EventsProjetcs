package tn.fst.eventsproject.repositories;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Feedback;
import tn.fst.eventsproject.entities.Participant;

import javax.persistence.EntityManager;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;

@DataJpaTest
class FeedbackRepositoryTest {
    @Autowired FeedbackRepository repository;
    @Autowired EntityManager entityManager;

    private Feedback review(Event event, Participant participant, int note) {
        Feedback feedback = new Feedback();
        feedback.setEvent(event);
        feedback.setParticipant(participant);
        feedback.setNote(note);
        feedback.setCommentaire("Useful event");
        return repository.saveAndFlush(feedback);
    }

    private Participant participant(Event event) {
        Participant participant = new Participant();
        participant.setEvents(Collections.singleton(event));
        entityManager.persist(participant);
        return participant;
    }

    @Test
    void persistsRelationshipsTimestampAndCalculatesAverage() {
        Event event = new Event();
        entityManager.persist(event);
        Participant first = participant(event);
        Feedback feedback = review(event, first, 4);
        review(event, participant(event), 5);
        entityManager.clear();
        Feedback loaded = repository.findById(feedback.getId()).get();
        assertNotNull(loaded.getDate());
        assertEquals("Useful event", loaded.getCommentaire());
        assertEquals(event.getIdEvent(), loaded.getEvent().getIdEvent());
        assertEquals(first.getIdPart(), loaded.getParticipant().getIdPart());
        assertEquals(1, loaded.getParticipant().getEvents().size());
        assertEquals(2, repository.findByEvent_IdEventOrderByDateAscIdAsc(event.getIdEvent()).size());
        assertEquals(2, repository.countByEvent_IdEvent(event.getIdEvent()));
        assertTrue(repository.existsByEvent_IdEventAndParticipant_IdPart(event.getIdEvent(), first.getIdPart()));
        assertEquals(4.5, repository.averageRatingByEvent(event.getIdEvent()));
    }

    @Test
    void emptyEventHasZeroAverage() {
        assertEquals(0.0, repository.averageRatingByEvent(-1));
        assertTrue(repository.findByEvent_IdEventOrderByDateAscIdAsc(-1).isEmpty());
        assertFalse(repository.existsByEvent_IdEventAndParticipant_IdPart(-1, -1));
    }

    @Test
    void databaseRejectsDuplicateEventParticipantPair() {
        Event event = new Event();
        entityManager.persist(event);
        Participant participant = participant(event);
        review(event, participant, 3);
        assertThrows(DataIntegrityViolationException.class, () -> review(event, participant, 5));
    }

    @Test
    void sameParticipantCanReviewMultipleEventsAndMultipleParticipantsCanReviewOneEvent() {
        Event first = new Event();
        Event second = new Event();
        entityManager.persist(first);
        entityManager.persist(second);
        Participant participant = participant(first);
        participant.setEvents(new java.util.HashSet<>(java.util.Arrays.asList(first, second)));
        review(first, participant, 1);
        review(second, participant, 5);
        review(first, participant(first), 4);
        assertEquals(2.5, repository.averageRatingByEvent(first.getIdEvent()));
        assertEquals(5.0, repository.averageRatingByEvent(second.getIdEvent()));
    }

    @Test
    void databaseRejectsMissingRequiredRating() {
        Event event = new Event();
        entityManager.persist(event);
        Feedback feedback = new Feedback();
        feedback.setEvent(event);
        feedback.setParticipant(participant(event));
        assertThrows(DataIntegrityViolationException.class, () -> repository.saveAndFlush(feedback));
    }

    @Test
    void databaseRejectsMissingRequiredRelationship() {
        Feedback feedback = new Feedback();
        feedback.setNote(5);
        assertThrows(DataIntegrityViolationException.class, () -> repository.saveAndFlush(feedback));
    }
}
