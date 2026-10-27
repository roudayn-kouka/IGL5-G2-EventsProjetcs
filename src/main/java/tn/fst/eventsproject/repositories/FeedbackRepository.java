package tn.fst.eventsproject.repositories;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import tn.fst.eventsproject.entities.Feedback;

import java.util.List;

public interface FeedbackRepository extends JpaRepository<Feedback, Integer> {
    List<Feedback> findByEvent_IdEventOrderByDateAscIdAsc(int eventId);

    boolean existsByEvent_IdEventAndParticipant_IdPart(int eventId, int participantId);

    long countByEvent_IdEvent(int eventId);

    @Query("select coalesce(avg(f.note), 0.0) from Feedback f where f.event.idEvent = :eventId")
    double averageRatingByEvent(@Param("eventId") int eventId);
}
