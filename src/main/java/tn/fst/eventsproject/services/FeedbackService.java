package tn.fst.eventsproject.services;

import org.hibernate.exception.ConstraintViolationException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import tn.fst.eventsproject.dto.FeedbackAverageResponse;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Feedback;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.FeedbackRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;
import java.util.Locale;

@Service
@Transactional(readOnly = true)
public class FeedbackService {
    private final FeedbackRepository feedbackRepository;
    private final EventRepository eventRepository;
    private final ParticipantRepository participantRepository;
    private final Clock clock;

    @Autowired
    public FeedbackService(FeedbackRepository feedbackRepository, EventRepository eventRepository,
                           ParticipantRepository participantRepository) {
        this(feedbackRepository, eventRepository, participantRepository, Clock.systemDefaultZone());
    }

    public FeedbackService(FeedbackRepository feedbackRepository, EventRepository eventRepository,
                           ParticipantRepository participantRepository, Clock clock) {
        this.feedbackRepository = feedbackRepository;
        this.eventRepository = eventRepository;
        this.participantRepository = participantRepository;
        this.clock = clock;
    }

    @Transactional
    public Feedback createFeedback(int eventId, int participantId, Integer note, String commentaire) {
        validateRating(note);
        Event event = loadEvent(eventId);
        Participant participant = requireAssociatedParticipant(eventId, participantId);
        requireFinishedEvent(event);
        if (feedbackRepository.existsByEvent_IdEventAndParticipant_IdPart(eventId, participantId)) {
            throw duplicateFeedback();
        }
        return saveFeedback(event, participant, note, commentaire);
    }

    private void validateRating(Integer note) {
        if (note == null || note < 1 || note > 5) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Rating must be an integer between 1 and 5");
        }
    }

    private Event loadEvent(int eventId) {
        return eventRepository.findById(eventId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Event not found"));
    }

    private Participant requireAssociatedParticipant(int eventId, int participantId) {
        Participant participant = participantRepository.findById(participantId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Participant not found"));
        boolean associated = participant.getEvents() != null && participant.getEvents().stream()
                .anyMatch(event -> event.getIdEvent() == eventId);
        if (!associated) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Participant is not associated with this event");
        }
        return participant;
    }

    private void requireFinishedEvent(Event event) {
        // dateFin is inclusive: an event ending today has not finished yet.
        if (event.getDateFin() == null || !event.getDateFin().isBefore(LocalDate.now(clock))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Event has not finished");
        }
    }

    private Feedback saveFeedback(Event event, Participant participant, Integer note, String commentaire) {
        Feedback feedback = new Feedback();
        feedback.setEvent(event);
        feedback.setParticipant(participant);
        feedback.setNote(note);
        feedback.setCommentaire(commentaire);
        feedback.setDate(clock.instant());
        try {
            // Flush inside this transaction so concurrent duplicates are translated before returning.
            return feedbackRepository.saveAndFlush(feedback);
        } catch (DataIntegrityViolationException exception) {
            if (isDuplicateFeedbackConstraint(exception)) {
                throw duplicateFeedback();
            }
            throw exception;
        }
    }

    private boolean isDuplicateFeedbackConstraint(Throwable failure) {
        for (Throwable cause = failure; cause != null; cause = cause.getCause()) {
            if (cause instanceof ConstraintViolationException) {
                String constraint = ((ConstraintViolationException) cause).getConstraintName();
                return constraint != null && constraint.toLowerCase(Locale.ROOT)
                        .contains("uk_feedback_event_participant");
            }
        }
        return false;
    }

    public List<Feedback> getFeedbackByEvent(int eventId) {
        requireEvent(eventId);
        return feedbackRepository.findByEvent_IdEventOrderByDateAscIdAsc(eventId);
    }

    public FeedbackAverageResponse getAverageRatingByEvent(int eventId) {
        requireEvent(eventId);
        return new FeedbackAverageResponse(eventId, feedbackRepository.averageRatingByEvent(eventId),
                feedbackRepository.countByEvent_IdEvent(eventId));
    }

    @Transactional
    public void deleteFeedback(int feedbackId) {
        Feedback feedback = feedbackRepository.findById(feedbackId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Feedback not found"));
        feedbackRepository.delete(feedback);
    }

    private void requireEvent(int eventId) {
        if (!eventRepository.existsById(eventId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Event not found");
        }
    }

    private ResponseStatusException duplicateFeedback() {
        return new ResponseStatusException(HttpStatus.CONFLICT, "Participant already reviewed this event");
    }
}
