package tn.esprit.eventsproject.controllers;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.junit4.SpringRunner;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import tn.esprit.eventsproject.entities.Logistics;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Test du contrôleur SANS Mockito : vrai contrôleur, vrai service, vraie base MySQL.
 * MockMvc simule les requêtes HTTP (pas besoin de lancer le serveur).
 * Note : MockMvc n'utilise pas le context-path "/events", on appelle donc "/logistics".
 */
@RunWith(SpringRunner.class)
@SpringBootTest
@AutoConfigureMockMvc
public class LogisticsControllerTest {

    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    private Logistics buildLogistics() {
        Logistics l = new Logistics();
        l.setDescription("Chaises");
        l.setReserve(true);
        l.setPrixUnit(12.5f);
        l.setQuantite(40);
        return l;
    }

    /** Ajoute une logistique via l'API et retourne l'objet créé. */
    private Logistics addViaApi() throws Exception {
        MvcResult result = mockMvc.perform(post("/logistics")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(buildLogistics())))
                .andExpect(status().isCreated())
                .andReturn();
        return objectMapper.readValue(result.getResponse().getContentAsString(), Logistics.class);
    }

    private void deleteViaApi(int id) throws Exception {
        mockMvc.perform(delete("/logistics/{id}", id)).andExpect(status().isNoContent());
    }

    @Test
    public void testAddLogistics() throws Exception {
        mockMvc.perform(post("/logistics")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(buildLogistics())))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.idLog").exists())
                .andExpect(jsonPath("$.description").value("Chaises"))
                .andExpect(jsonPath("$.quantite").value(40));
        // (la ligne reste en base : à supprimer manuellement ou via testDeleteLogistics)
    }

    @Test
    public void testRetrieveLogistics() throws Exception {
        Logistics saved = addViaApi();

        mockMvc.perform(get("/logistics/{id}", saved.getIdLog()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idLog").value(saved.getIdLog()))
                .andExpect(jsonPath("$.description").value("Chaises"));

        // 12.5 x 40 = 500
        mockMvc.perform(get("/logistics/{id}/cout", saved.getIdLog()))
                .andExpect(status().isOk())
                .andExpect(content().string("500.0"));

        deleteViaApi(saved.getIdLog());
    }

    @Test
    public void testUpdateLogistics() throws Exception {
        Logistics saved = addViaApi();
        saved.setDescription("Tables");
        saved.setQuantite(10);

        mockMvc.perform(put("/logistics")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(saved)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idLog").value(saved.getIdLog()))
                .andExpect(jsonPath("$.description").value("Tables"))
                .andExpect(jsonPath("$.quantite").value(10));

        deleteViaApi(saved.getIdLog());
    }

    @Test
    public void testDeleteLogistics() throws Exception {
        Logistics saved = addViaApi();

        mockMvc.perform(delete("/logistics/{id}", saved.getIdLog()))
                .andExpect(status().isNoContent());
    }
}
