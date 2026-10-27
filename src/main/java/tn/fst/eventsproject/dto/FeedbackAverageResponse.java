package tn.fst.eventsproject.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;

@Getter
@AllArgsConstructor
public class FeedbackAverageResponse {
    private final int eventId;
    private final double averageRating;
    private final long totalFeedbacks;
}
