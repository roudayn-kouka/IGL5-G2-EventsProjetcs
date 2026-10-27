package tn.fst.eventsproject.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;
import tn.fst.eventsproject.entities.Feedback;

import java.time.Instant;

@Getter
@AllArgsConstructor
public class FeedbackResponse {
    private final Integer id;
    private final Integer note;
    private final String commentaire;
    private final Instant date;
    private final int eventId;
    private final int participantId;

    public static FeedbackResponse from(Feedback feedback) {
        return new FeedbackResponse(feedback.getId(), feedback.getNote(), feedback.getCommentaire(),
                feedback.getDate(), feedback.getEvent().getIdEvent(), feedback.getParticipant().getIdPart());
    }
}
