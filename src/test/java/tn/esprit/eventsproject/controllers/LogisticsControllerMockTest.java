package tn.esprit.eventsproject.controllers;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.services.ILogisticsService;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Test du contrôleur AVEC Mockito : le service est simulé,
 * aucune base de données et aucun contexte Spring complet.
 */
@RunWith(MockitoJUnitRunner.class)
public class LogisticsControllerMockTest {

    @Mock
    ILogisticsService logisticsService;

    @InjectMocks
    LogisticsController logisticsController;

    MockMvc mockMvc;
    ObjectMapper objectMapper = new ObjectMapper();

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(logisticsController).build();
    }

    private Logistics buildLogistics() {
        Logistics l = new Logistics();
        l.setIdLog(1);
        l.setDescription("Chaises");
        l.setReserve(true);
        l.setPrixUnit(12.5f);
        l.setQuantite(40);
        return l;
    }

    @Test
    public void testAddLogistics() throws Exception {
        Logistics l = buildLogistics();
        when(logisticsService.addLogistics(any(Logistics.class))).thenReturn(l);

        mockMvc.perform(post("/logistics")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(l)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.idLog").value(1))
                .andExpect(jsonPath("$.description").value("Chaises"));

        verify(logisticsService, times(1)).addLogistics(any(Logistics.class));
    }

    @Test
    public void testRetrieveLogistics() throws Exception {
        when(logisticsService.getLogisticsById(1)).thenReturn(buildLogistics());

        mockMvc.perform(get("/logistics/{id}", 1))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idLog").value(1))
                .andExpect(jsonPath("$.quantite").value(40));

        verify(logisticsService).getLogisticsById(1);
    }

    @Test
    public void testUpdateLogistics() throws Exception {
        Logistics l = buildLogistics();
        l.setDescription("Tables");
        when(logisticsService.updateLogistics(any(Logistics.class))).thenReturn(l);

        mockMvc.perform(put("/logistics")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(l)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").value("Tables"));

        verify(logisticsService).updateLogistics(any(Logistics.class));
    }

    @Test
    public void testDeleteLogistics() throws Exception {
        mockMvc.perform(delete("/logistics/{id}", 1))
                .andExpect(status().isNoContent());

        verify(logisticsService, times(1)).deleteLogistics(1);
    }
}
