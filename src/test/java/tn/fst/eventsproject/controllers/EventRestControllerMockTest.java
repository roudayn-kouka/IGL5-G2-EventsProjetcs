package tn.fst.eventsproject.controllers;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.services.IEventServices;

import java.time.LocalDate;
import java.util.Collections;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@RunWith(MockitoJUnitRunner.class)
public class EventRestControllerMockTest {

    @Mock
    IEventServices eventServices;

    @InjectMocks
    EventRestController controller;

    MockMvc mockMvc;

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    private Event event() {
        Participant p = new Participant();
        p.setIdPart(1);
        p.setNom("Tounsi");
        p.setTache(Tache.SERVEUR);
        Logistics l = new Logistics();
        l.setIdLog(5);
        l.setDescription("Chaises");
        Event e = new Event();
        e.setIdEvent(2);
        e.setDescription("Gala");
        e.setDateDebut(LocalDate.of(2026, 5, 1));
        e.setParticipants(Collections.singleton(p));
        e.setLogistics(Collections.singleton(l));
        return e;
    }

    private static final String EVENT_JSON =
            "{\"description\":\"Gala\",\"dateDebut\":\"2026-05-01\",\"participants\":[{\"idPart\":1}]}";

    @Test
    public void addEvent() throws Exception {
        when(eventServices.addAffectEvenParticipant(any(Event.class))).thenReturn(event());
        mockMvc.perform(post("/event/addEvent").contentType(MediaType.APPLICATION_JSON).content(EVENT_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").value("Gala"))
                .andExpect(jsonPath("$.participants[0].nom").value("Tounsi"))
                .andExpect(jsonPath("$.logistics[0].description").value("Chaises"));
    }

    @Test
    public void addEventForParticipant() throws Exception {
        when(eventServices.addAffectEvenParticipant(any(Event.class), anyInt())).thenReturn(event());
        mockMvc.perform(post("/event/addEvent/1").contentType(MediaType.APPLICATION_JSON).content(EVENT_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.idEvent").value(2));
    }

    @Test
    public void addParticipant() throws Exception {
        Participant p = new Participant();
        p.setNom("Ben Ali");
        when(eventServices.addParticipant(any(Participant.class))).thenReturn(p);
        mockMvc.perform(post("/event/addPart").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nom\":\"Ben Ali\",\"prenom\":\"Sami\",\"tache\":\"INVITE\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nom").value("Ben Ali"));
    }

    @Test
    public void addAffectLog() throws Exception {
        Logistics l = new Logistics();
        l.setDescription("Tables");
        when(eventServices.addAffectLog(any(Logistics.class), anyString())).thenReturn(l);
        mockMvc.perform(put("/event/addAffectLog/Gala").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"description\":\"Tables\",\"reserve\":true,\"prixUnit\":5,\"quantite\":2}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.description").value("Tables"));
    }

    @Test
    public void getLogs() throws Exception {
        Logistics l = new Logistics();
        l.setDescription("Tables");
        when(eventServices.getLogisticsDates(any(LocalDate.class), any(LocalDate.class)))
                .thenReturn(Collections.singletonList(l));
        mockMvc.perform(get("/event/getLogs/2026-01-01/2026-12-31"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].description").value("Tables"));
    }
}
