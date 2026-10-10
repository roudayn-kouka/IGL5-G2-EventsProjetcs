package tn.esprit.eventsproject.controllers;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.server.ResponseStatusException;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.services.IParticipantServices;

import java.util.Arrays;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Controller test WITH Mockito: only the web layer is loaded,
 * the service is replaced by a mock (no database at all).
 */
@WebMvcTest(ParticipantRestController.class)
class ParticipantRestControllerMockitoTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private IParticipantServices participantServices;

    private Participant buildParticipant(String nom, String prenom, Tache tache) {
        Participant p = new Participant();
        p.setNom(nom);
        p.setPrenom(prenom);
        p.setTache(tache);
        return p;
    }

    @Test
    void addParticipant_shouldReturnSavedParticipant() throws Exception {
        when(participantServices.addParticipant(any(Participant.class)))
                .thenReturn(buildParticipant("Tounsi", "Ahmed", Tache.ORGANISATEUR));

        mockMvc.perform(post("/participant/add")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nom\":\"Tounsi\",\"prenom\":\"Ahmed\",\"tache\":\"ORGANISATEUR\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nom").value("Tounsi"))
                .andExpect(jsonPath("$.tache").value("ORGANISATEUR"));

        verify(participantServices).addParticipant(any(Participant.class));
    }

    @Test
    void getAll_shouldReturnJsonArray() throws Exception {
        when(participantServices.getAllParticipants()).thenReturn(Arrays.asList(
                buildParticipant("A", "A", Tache.INVITE),
                buildParticipant("B", "B", Tache.SERVEUR)));

        mockMvc.perform(get("/participant/all"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[0].nom").value("A"));
    }

    @Test
    void getById_shouldReturnParticipant() throws Exception {
        when(participantServices.getParticipantById(1))
                .thenReturn(buildParticipant("Tounsi", "Ahmed", Tache.INVITE));

        mockMvc.perform(get("/participant/1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.prenom").value("Ahmed"));
    }

    @Test
    void getById_notFound_shouldReturn404() throws Exception {
        when(participantServices.getParticipantById(999))
                .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND, "not found"));

        mockMvc.perform(get("/participant/999"))
                .andExpect(status().isNotFound());
    }

    @Test
    void update_shouldReturnUpdatedParticipant() throws Exception {
        when(participantServices.updateParticipant(eq(1), any(Participant.class)))
                .thenReturn(buildParticipant("Tounsi", "Ahmed", Tache.SERVEUR));

        mockMvc.perform(put("/participant/update/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nom\":\"Tounsi\",\"prenom\":\"Ahmed\",\"tache\":\"SERVEUR\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tache").value("SERVEUR"));
    }

    @Test
    void changeTache_shouldCallServiceWithEnum() throws Exception {
        when(participantServices.changeTache(1, Tache.ANIMATEUR))
                .thenReturn(buildParticipant("Tounsi", "Ahmed", Tache.ANIMATEUR));

        mockMvc.perform(put("/participant/1/tache/ANIMATEUR"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tache").value("ANIMATEUR"));
    }

    @Test
    void changeTache_invalidValue_shouldReturn400() throws Exception {
        mockMvc.perform(put("/participant/1/tache/NOT_A_TACHE"))
                .andExpect(status().isBadRequest());

        verify(participantServices, never()).changeTache(anyInt(), any());
    }

    @Test
    void delete_shouldCallService() throws Exception {
        doNothing().when(participantServices).deleteParticipant(1);

        mockMvc.perform(delete("/participant/delete/1"))
                .andExpect(status().isOk());

        verify(participantServices).deleteParticipant(1);
    }
}
