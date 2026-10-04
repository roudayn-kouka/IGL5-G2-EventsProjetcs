package tn.esprit.eventsproject.services;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.web.server.ResponseStatusException;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Test WITHOUT Mockito: the real service talks to a real repository
 * backed by an in-memory H2 database (needs the H2 test dependency).
 * Each test is rolled back automatically by @DataJpaTest.
 */
@DataJpaTest
@Import(ParticipantServicesImpl.class)
class ParticipantServicesImplIntegrationTest {

    @Autowired
    private ParticipantServicesImpl service;

    private Participant newParticipant(String nom, String prenom, Tache tache) {
        Participant p = new Participant();
        p.setNom(nom);
        p.setPrenom(prenom);
        p.setTache(tache);
        return p;
    }

    @Test
    void addParticipant_shouldGenerateId() {
        Participant saved = service.addParticipant(newParticipant("Tounsi", "Ahmed", Tache.ORGANISATEUR));

        assertTrue(saved.getIdPart() > 0);
        assertEquals("Tounsi", saved.getNom());
    }

    @Test
    void getAllParticipants_shouldReturnSavedOnes() {
        service.addParticipant(newParticipant("A", "A", Tache.INVITE));
        service.addParticipant(newParticipant("B", "B", Tache.SERVEUR));

        List<Participant> all = service.getAllParticipants();

        assertEquals(2, all.size());
    }

    @Test
    void getParticipantById_shouldReturnParticipant() {
        Participant saved = service.addParticipant(newParticipant("Tounsi", "Ahmed", Tache.INVITE));

        Participant found = service.getParticipantById(saved.getIdPart());

        assertEquals("Ahmed", found.getPrenom());
    }

    @Test
    void getParticipantById_unknownId_shouldThrow404() {
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> service.getParticipantById(9999));

        assertEquals(404, ex.getStatus().value());
    }

    @Test
    void updateParticipant_shouldPersistChanges() {
        Participant saved = service.addParticipant(newParticipant("Old", "Name", Tache.INVITE));

        service.updateParticipant(saved.getIdPart(), newParticipant("New", "Person", Tache.ANIMATEUR));
        Participant reloaded = service.getParticipantById(saved.getIdPart());

        assertEquals("New", reloaded.getNom());
        assertEquals("Person", reloaded.getPrenom());
        assertEquals(Tache.ANIMATEUR, reloaded.getTache());
    }

    @Test
    void changeTache_shouldPersistNewTache() {
        Participant saved = service.addParticipant(newParticipant("Tounsi", "Ahmed", Tache.INVITE));

        service.changeTache(saved.getIdPart(), Tache.SERVEUR);

        assertEquals(Tache.SERVEUR, service.getParticipantById(saved.getIdPart()).getTache());
    }

    @Test
    void deleteParticipant_shouldRemoveIt() {
        Participant saved = service.addParticipant(newParticipant("Tounsi", "Ahmed", Tache.INVITE));
        int id = saved.getIdPart();

        service.deleteParticipant(id);

        assertThrows(ResponseStatusException.class, () -> service.getParticipantById(id));
    }
}
