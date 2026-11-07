package tn.fst.eventsproject.controllers;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.format.datetime.standard.DateTimeFormatterRegistrar;
import org.springframework.format.support.DefaultFormattingConversionService;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.services.IEventServices;

import java.time.LocalDate;
import java.util.Collections;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Test du contrôleur AVEC Mockito : le service est simulé,
 * aucune base de données et aucun contexte Spring complet.
 */
@RunWith(MockitoJUnitRunner.class)
public class EventRestControllerMockTest {

    @Mock
    IEventServices eventServices;

    @InjectMocks
    EventRestController eventRestController;

    MockMvc mockMvc;
    ObjectMapper objectMapper = new ObjectMapper();

    @Before
    public void setUp() {
        // Dates des chemins au format ISO (yyyy-MM-dd), comme spring.mvc.format.date de l'application
        DefaultFormattingConversionService conversion = new DefaultFormattingConversionService();
        DateTimeFormatterRegistrar registrar = new DateTimeFormatterRegistrar();
        registrar.setUseIsoFormat(true);
        registrar.registerFormatters(conversion);
        mockMvc = MockMvcBuilders.standaloneSetup(eventRestController)
                .setConversionService(conversion)
                .build();
    }

    private Event buildEvent() {
        Event e = new Event();
        e.setIdEvent(1);
        e.setDescription("Hackathon");
        return e;
    }

    @Test
    public void testAddParticipant() throws Exception {
        Participant p = new Participant();
        p.setIdPart(1);
        p.setNom("Tounsi");
        when(eventServices.addParticipant(any(Participant.class))).thenReturn(p);

        mockMvc.perform(post("/event/addPart")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(p)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idPart").value(1))
                .andExpect(jsonPath("$.nom").value("Tounsi"));
    }

    @Test
    public void testAddEventPart() throws Exception {
        when(eventServices.addAffectEvenParticipant(any(Event.class), eq(7))).thenReturn(buildEvent());

        mockMvc.perform(post("/event/addEvent/7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(buildEvent())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").value("Hackathon"));

        verify(eventServices).addAffectEvenParticipant(any(Event.class), eq(7));
    }

    @Test
    public void testAddEvent() throws Exception {
        when(eventServices.addAffectEvenParticipant(any(Event.class))).thenReturn(buildEvent());

        mockMvc.perform(post("/event/addEvent")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(buildEvent())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idEvent").value(1));
    }

    @Test
    public void testAddAffectLog() throws Exception {
        Logistics l = new Logistics();
        l.setIdLog(3);
        l.setDescription("Chaises");
        when(eventServices.addAffectLog(any(Logistics.class), eq("Hackathon"))).thenReturn(l);

        mockMvc.perform(put("/event/addAffectLog/Hackathon")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(l)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idLog").value(3));
    }

    @Test
    public void testGetLogistiquesDates() throws Exception {
        Logistics l = new Logistics();
        l.setDescription("Stands");
        l.setReserve(true);
        LocalDate debut = LocalDate.of(2025, 5, 1);
        LocalDate fin = LocalDate.of(2025, 5, 31);
        when(eventServices.getLogisticsDates(debut, fin)).thenReturn(Collections.singletonList(l));

        mockMvc.perform(get("/event/getLogs/2025-05-01/2025-05-31"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].description").value("Stands"));
    }
}
