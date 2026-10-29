package tn.fst.eventsproject.controllers;

import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.services.ILogisticsService;

import java.util.Collections;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@RunWith(MockitoJUnitRunner.class)
public class LogisticsControllerListMockTest {

    @Mock
    ILogisticsService logisticsService;

    @InjectMocks
    LogisticsController controller;

    MockMvc mockMvc;

    @Before
    public void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(controller).build();
    }

    private Logistics tables() {
        Logistics l = new Logistics();
        l.setIdLog(2);
        l.setDescription("Tables");
        l.setReserve(true);
        return l;
    }

    @Test
    public void getAll() throws Exception {
        when(logisticsService.getAllLogistics()).thenReturn(Collections.singletonList(tables()));
        mockMvc.perform(get("/logistics"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].description").value("Tables"));
    }

    @Test
    public void getReserved() throws Exception {
        when(logisticsService.getReservedLogistics()).thenReturn(Collections.singletonList(tables()));
        mockMvc.perform(get("/logistics/reserved"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].reserve").value(true));
    }
}
