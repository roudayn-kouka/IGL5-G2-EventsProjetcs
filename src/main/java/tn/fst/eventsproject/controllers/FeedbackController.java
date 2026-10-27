package tn.fst.eventsproject.controllers;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import tn.fst.eventsproject.dto.FeedbackAverageResponse;
import tn.fst.eventsproject.dto.FeedbackRequest;
import tn.fst.eventsproject.dto.FeedbackResponse;
import tn.fst.eventsproject.services.FeedbackService;

import javax.validation.Valid;
import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/feedback")
@RequiredArgsConstructor
public class FeedbackController {
    private final FeedbackService feedbackService;

    @PostMapping("/{idEvent}/{idPart}")
    @ResponseStatus(HttpStatus.CREATED)
    public FeedbackResponse create(@PathVariable int idEvent, @PathVariable int idPart,
                                   @Valid @RequestBody FeedbackRequest request) {
        return FeedbackResponse.from(feedbackService.createFeedback(idEvent, idPart,
                request.getNote(), request.getCommentaire()));
    }

    @GetMapping("/event/{id}")
    public List<FeedbackResponse> getByEvent(@PathVariable int id) {
        return feedbackService.getFeedbackByEvent(id).stream()
                .map(FeedbackResponse::from).collect(Collectors.toList());
    }

    @GetMapping("/event/{id}/moyenne")
    public FeedbackAverageResponse average(@PathVariable int id) {
        return feedbackService.getAverageRatingByEvent(id);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable int id) {
        feedbackService.deleteFeedback(id);
    }
}
