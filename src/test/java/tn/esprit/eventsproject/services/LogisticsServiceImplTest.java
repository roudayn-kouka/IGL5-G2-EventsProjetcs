package tn.esprit.eventsproject.services;

import lombok.extern.slf4j.Slf4j;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.junit4.SpringRunner;
import tn.esprit.eventsproject.entities.Logistics;

import static org.junit.Assert.*;

/**
 * Test SANS Mockito : on utilise le vrai service et la vraie base de données.
 */
@RunWith(SpringRunner.class)
@SpringBootTest
@Slf4j
public class LogisticsServiceImplTest {

    @Autowired
    ILogisticsService logisticsService;

    private Logistics buildLogistics() {
        Logistics l = new Logistics();
        l.setDescription("Chaises");
        l.setReserve(true);
        l.setPrixUnit(12.5f);
        l.setQuantite(40);
        return l;
    }

    @Test
    public void testAddLogistics() {
        Logistics saved = logisticsService.addLogistics(buildLogistics());
        log.info("Logistics ajoutée : {}", saved);

        assertNotEquals(0, saved.getIdLog());
        assertEquals("Chaises", saved.getDescription());
        assertTrue(saved.isReserve());

        logisticsService.deleteLogistics(saved.getIdLog()); // nettoyage
    }

    @Test
    public void testRetrieveLogistics() {
        Logistics saved = logisticsService.addLogistics(buildLogistics());

        Logistics found = logisticsService.getLogisticsById(saved.getIdLog());
        assertNotNull(found);
        assertEquals(saved.getIdLog(), found.getIdLog());
        assertEquals(40, found.getQuantite());

        logisticsService.deleteLogistics(saved.getIdLog());
    }

    @Test
    public void testUpdateLogistics() {
        Logistics saved = logisticsService.addLogistics(buildLogistics());

        saved.setDescription("Tables");
        saved.setQuantite(10);
        Logistics updated = logisticsService.updateLogistics(saved);

        assertEquals(saved.getIdLog(), updated.getIdLog());
        assertEquals("Tables", updated.getDescription());
        assertEquals(10, updated.getQuantite());

        logisticsService.deleteLogistics(saved.getIdLog());
    }

    @Test
    public void testDeleteLogistics() {
        Logistics saved = logisticsService.addLogistics(buildLogistics());
        int id = saved.getIdLog();

        logisticsService.deleteLogistics(id);

        // Le service lance une exception quand l'id n'existe plus
        assertThrows(IllegalArgumentException.class,
                () -> logisticsService.getLogisticsById(id));
    }
}
