package tn.fst.eventsproject.controllers;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.repositories.*;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Real transactions in separate request threads, with no Mockito or test-managed transaction. */
@SpringBootTest(properties = {"spring.datasource.url=jdbc:h2:mem:feedbackConcurrency;DB_CLOSE_DELAY=-1",
        "spring.jpa.open-in-view=false", "server.servlet.context-path=/events"})
@AutoConfigureMockMvc
class FeedbackConcurrencyIntegrationTest {
    @Autowired MockMvc mvc;
    @Autowired EventRepository events;
    @Autowired ParticipantRepository participants;
    @Autowired FeedbackRepository feedbacks;
    @Autowired PlatformTransactionManager transactionManager;

    @Test
    void concurrentSubmissionsYieldOneCreatedOneConflictAndReadableCommittedFeedback() throws Exception {
        TransactionTemplate transaction = new TransactionTemplate(transactionManager);
        int[] ids = transaction.execute(status -> {
            Event event = new Event();
            event.setDateFin(LocalDate.now().minusDays(1));
            events.saveAndFlush(event);
            Participant participant = new Participant();
            participant.setEvents(Collections.singleton(event));
            participants.saveAndFlush(participant);
            return new int[]{event.getIdEvent(), participant.getIdPart()};
        });
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);
        try {
            Callable<Integer> submit = () -> {
                ready.countDown();
                assertTrue(start.await(10, TimeUnit.SECONDS));
                return mvc.perform(post("/events/feedback/{event}/{participant}", ids[0], ids[1])
                        .contextPath("/events").contentType(MediaType.APPLICATION_JSON).content("{\"note\":5}"))
                        .andReturn().getResponse().getStatus();
            };
            Future<Integer> first = executor.submit(submit);
            Future<Integer> second = executor.submit(submit);
            assertTrue(ready.await(10, TimeUnit.SECONDS));
            start.countDown();
            List<Integer> statuses = Arrays.asList(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));
            Collections.sort(statuses);
            assertEquals(Arrays.asList(201, 409), statuses);
            assertEquals(1, feedbacks.countByEvent_IdEvent(ids[0]));
            mvc.perform(get("/events/feedback/event/{id}", ids[0]).contextPath("/events"))
                    .andExpect(status().isOk()).andExpect(jsonPath("$[0].eventId").value(ids[0]))
                    .andExpect(jsonPath("$[0].participantId").value(ids[1]));
            mvc.perform(get("/events/feedback/event/{id}/moyenne", ids[0]).contextPath("/events"))
                    .andExpect(status().isOk()).andExpect(jsonPath("$.averageRating").value(5.0));
        } finally {
            start.countDown();
            executor.shutdownNow();
            assertTrue(executor.awaitTermination(10, TimeUnit.SECONDS));
            transaction.executeWithoutResult(status -> {
                feedbacks.deleteAll(feedbacks.findByEvent_IdEventOrderByDateAscIdAsc(ids[0]));
                feedbacks.flush();
                participants.deleteById(ids[1]);
                participants.flush();
                events.deleteById(ids[0]);
            });
        }
    }
}
