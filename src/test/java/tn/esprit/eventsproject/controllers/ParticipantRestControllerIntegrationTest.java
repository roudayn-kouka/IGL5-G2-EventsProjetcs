package tn.esprit.eventsproject.controllers;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Test WITHOUT Mockito: the whole application context is started
 * (controller + real service + real repository + in-memory H2).
 * @Transactional rolls back the data after each test.
 */
@SpringBootTest
@AutoConfigureMockMvc
@AutoConfigureTestDatabase

@TestPropertySource(properties = {
    "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
    "spring.jpa.hibernate.ddl-auto=create-drop"
})

@Transactional
class ParticipantRestControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    private int createParticipant(String json) throws Exception {
        MvcResult result = mockMvc.perform(post("/participant/add")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isOk())
                .andReturn();
        JsonNode node = objectMapper.readTree(result.getResponse().getContentAsString());
        return node.get("idPart").asInt();
    }

    @Test
    void add_then_getById() throws Exception {
        int id = createParticipant("{\"nom\":\"Tounsi\",\"prenom\":\"Ahmed\",\"tache\":\"ORGANISATEUR\"}");
        assertTrue(id > 0);

        mockMvc.perform(get("/participant/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nom").value("Tounsi"))
                .andExpect(jsonPath("$.tache").value("ORGANISATEUR"));
    }

    @Test
    void getAll_shouldContainCreatedParticipants() throws Exception {
        createParticipant("{\"nom\":\"A\",\"prenom\":\"A\",\"tache\":\"INVITE\"}");
        createParticipant("{\"nom\":\"B\",\"prenom\":\"B\",\"tache\":\"SERVEUR\"}");

        mockMvc.perform(get("/participant/all"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2));
    }

    @Test
    void update_shouldChangeValues() throws Exception {
        int id = createParticipant("{\"nom\":\"Old\",\"prenom\":\"Name\",\"tache\":\"INVITE\"}");

        mockMvc.perform(put("/participant/update/" + id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nom\":\"New\",\"prenom\":\"Person\",\"tache\":\"ANIMATEUR\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nom").value("New"))
                .andExpect(jsonPath("$.tache").value("ANIMATEUR"));
    }

    @Test
    void changeTache_shouldPersist() throws Exception {
        int id = createParticipant("{\"nom\":\"Tounsi\",\"prenom\":\"Ahmed\",\"tache\":\"INVITE\"}");

        mockMvc.perform(put("/participant/" + id + "/tache/SERVEUR"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tache").value("SERVEUR"));

        mockMvc.perform(get("/participant/" + id))
                .andExpect(jsonPath("$.tache").value("SERVEUR"));
    }

    @Test
    void delete_then_getById_shouldReturn404() throws Exception {
        int id = createParticipant("{\"nom\":\"Tounsi\",\"prenom\":\"Ahmed\",\"tache\":\"INVITE\"}");

        mockMvc.perform(delete("/participant/delete/" + id))
                .andExpect(status().isOk());

        mockMvc.perform(get("/participant/" + id))
                .andExpect(status().isNotFound());
    }

    @Test
    void getById_unknownId_shouldReturn404() throws Exception {
        mockMvc.perform(get("/participant/99999"))
                .andExpect(status().isNotFound());
    }
}
