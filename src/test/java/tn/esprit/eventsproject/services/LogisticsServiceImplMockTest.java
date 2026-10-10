package tn.esprit.eventsproject.services;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.repositories.LogisticsRepository;

import java.util.Optional;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

/**
 * Test AVEC Mockito : le repository est simulé, aucune base de données n'est utilisée.
 */
@RunWith(MockitoJUnitRunner.class)
public class LogisticsServiceImplMockTest {

    @Mock
    LogisticsRepository logisticsRepository;

    @InjectMocks
    LogisticsServiceImpl logisticsService;

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
    public void testAddLogistics() {
        Logistics l = buildLogistics();
        when(logisticsRepository.save(l)).thenReturn(l);

        Logistics result = logisticsService.addLogistics(l);

        assertNotNull(result);
        assertEquals("Chaises", result.getDescription());
        verify(logisticsRepository, times(1)).save(l);
    }

    @Test
    public void testRetrieveLogistics() {
        Logistics l = buildLogistics();
        when(logisticsRepository.findById(1)).thenReturn(Optional.of(l));

        Logistics result = logisticsService.getLogisticsById(1);

        assertNotNull(result);
        assertEquals(1, result.getIdLog());
        assertEquals(500f, logisticsService.calculerCoutTotal(1), 0.001f); // 12.5 x 40
        verify(logisticsRepository, atLeastOnce()).findById(1);
    }

    @Test
    public void testUpdateLogistics() {
        Logistics l = buildLogistics();
        l.setDescription("Tables");
        when(logisticsRepository.save(l)).thenReturn(l);

        Logistics result = logisticsService.updateLogistics(l);

        assertEquals("Tables", result.getDescription());
        verify(logisticsRepository).save(l);
    }

    @Test
    public void testDeleteLogistics() {
        logisticsService.deleteLogistics(1);

        verify(logisticsRepository, times(1)).deleteById(1);
    }
}
