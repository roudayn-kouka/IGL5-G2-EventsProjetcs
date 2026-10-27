package tn.fst.eventsproject.controllers;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.repositories.FeedbackRepository;

import javax.persistence.EntityManager;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = {"server.servlet.context-path=/events", "spring.jpa.open-in-view=false",
        "spring.datasource.url=jdbc:h2:mem:feedbackHttp;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE"})
@AutoConfigureMockMvc
@Transactional
class FeedbackControllerIntegrationTest {
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired EntityManager entityManager;
    @Autowired FeedbackRepository repository;
    int eventId;
    int participantId;

    @BeforeEach
    void setup() {
        Event event = new Event();
        event.setDateFin(LocalDate.now().minusDays(1));
        event.setDateDebut(LocalDate.now().minusDays(2));
        entityManager.persist(event);
        Participant participant = new Participant();
        participant.setEvents(Collections.singleton(event));
        entityManager.persist(participant);
        entityManager.flush();
        eventId = event.getIdEvent();
        participantId = participant.getIdPart();
        entityManager.clear();
    }

    ResultActions submit(int event, int participant, String body) throws Exception {
        return mvc.perform(post("/events/feedback/{event}/{participant}", event, participant)
                .contextPath("/events").contentType(MediaType.APPLICATION_JSON).content(body));
    }

    @Test
    void fullLifecycleReturnsSafeDtosAverageAndNoContentOnDelete() throws Exception {
        Instant before = Instant.now();
        String json = submit(eventId, participantId,
                "{\"note\":5,\"commentaire\":\"Excellent\",\"date\":\"2000-01-01T00:00:00Z\"}")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.note").value(5))
                .andExpect(jsonPath("$.eventId").value(eventId))
                .andExpect(jsonPath("$.participantId").value(participantId))
                .andExpect(jsonPath("$.event").doesNotExist())
                .andExpect(jsonPath("$.participant").doesNotExist())
                .andReturn().getResponse().getContentAsString();
        JsonNode response = mapper.readTree(json);
        assertFalse(Instant.parse(response.get("date").asText()).isBefore(before));
        int id = response.get("id").asInt();
        entityManager.flush();
        entityManager.clear();
        mvc.perform(get("/events/feedback/event/{id}", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].commentaire").value("Excellent"));
        mvc.perform(get("/events/feedback/event/{id}/moyenne", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.averageRating").value(5.0))
                .andExpect(jsonPath("$.totalFeedbacks").value(1));
        mvc.perform(delete("/events/feedback/{id}", id).contextPath("/events"))
                .andExpect(status().isNoContent()).andExpect(content().string(""));
        assertFalse(repository.existsById(id));
        mvc.perform(delete("/events/feedback/{id}", id).contextPath("/events"))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.message").value("Feedback not found"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"note\":null}", "{\"note\":0}", "{\"note\":6}",
            "{\"note\":1.5}", "{\"note\":5.0}", "{\"note\":\"5\"}", "{\"note\":true}",
            "{\"note\":2147483648}", "null", "{broken"})
    void invalidRequestIsBadRequestAndDoesNotPersist(String body) throws Exception {
        submit(eventId, participantId, body).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400)).andExpect(jsonPath("$.message").isNotEmpty());
        assertEquals(0, repository.countByEvent_IdEvent(eventId));
    }

    @Test
    void duplicateReturnsConflict() throws Exception {
        submit(eventId, participantId, "{\"note\":1}").andExpect(status().isCreated());
        submit(eventId, participantId, "{\"note\":5}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value(409));
        assertEquals(1, repository.countByEvent_IdEvent(eventId));
    }

    @Test
    void missingEventOrParticipantReturnsNotFound() throws Exception {
        submit(-1, participantId, "{\"note\":5}").andExpect(status().isNotFound());
        submit(eventId, -1, "{\"note\":5}").andExpect(status().isNotFound());
        mvc.perform(get("/events/feedback/event/-1").contextPath("/events"))
                .andExpect(status().isNotFound());
        mvc.perform(get("/events/feedback/event/-1/moyenne").contextPath("/events"))
                .andExpect(status().isNotFound());
    }

    @Test
    void unassociatedParticipantReturnsBadRequest() throws Exception {
        Participant other = new Participant();
        entityManager.persist(other);
        submit(eventId, other.getIdPart(), "{\"note\":5}").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Participant is not associated with this event"));
    }

    @ParameterizedTest
    @ValueSource(ints = {0, 1})
    void ongoingAndFutureEventsReturnBadRequest(int days) throws Exception {
        entityManager.find(Event.class, eventId).setDateFin(LocalDate.now().plusDays(days));
        submit(eventId, participantId, "{\"note\":5}").andExpect(status().isBadRequest());
    }

    @Test
    void eventWithNoEndDateReturnsBadRequest() throws Exception {
        entityManager.find(Event.class, eventId).setDateFin(null);
        submit(eventId, participantId, "{\"note\":5}").andExpect(status().isBadRequest());
    }

    @Test
    void emptyEventReturnsEmptyListAndZeroAverage() throws Exception {
        mvc.perform(get("/events/feedback/event/{id}", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(content().json("[]"));
        mvc.perform(get("/events/feedback/event/{id}/moyenne", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.eventId").value(eventId))
                .andExpect(jsonPath("$.averageRating").value(0.0))
                .andExpect(jsonPath("$.totalFeedbacks").value(0));
    }

    @Test
    void malformedIdReturnsReadableBadRequest() throws Exception {
        mvc.perform(get("/events/feedback/event/abc").contextPath("/events"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.message").isNotEmpty());
    }

    @Test
    void eventStatisticsReflectFeedbackCreationAndDeletion() throws Exception {
        mvc.perform(get("/events/event-stats/{id}", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.averageRating").value(0.0));
        String created = submit(eventId, participantId, "{\"note\":4}")
                .andExpect(status().isCreated()).andReturn().getResponse().getContentAsString();
        int feedbackId = mapper.readTree(created).get("id").asInt();
        Participant second = new Participant();
        second.setEvents(Collections.singleton(entityManager.find(Event.class, eventId)));
        entityManager.persist(second);
        submit(eventId, second.getIdPart(), "{\"note\":5}").andExpect(status().isCreated());
        // Reload the inverse collection after assigning the second participant on the owning side.
        entityManager.flush();
        entityManager.clear();
        mvc.perform(get("/events/event-stats/{id}", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.averageRating").value(4.5))
                .andExpect(jsonPath("$.nbParticipants").value(2));
        mvc.perform(get("/events/event-stats").contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$[?(@.idEvent == " + eventId + ")].averageRating")
                        .value(org.hamcrest.Matchers.contains(4.5)));
        mvc.perform(delete("/events/feedback/{id}", feedbackId).contextPath("/events"))
                .andExpect(status().isNoContent());
        mvc.perform(get("/events/event-stats/{id}", eventId).contextPath("/events"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.averageRating").value(5.0));
    }
}
