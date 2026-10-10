package tn.esprit.eventsproject.services;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.repositories.ParticipantRepository;

import java.util.Arrays;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

/**
 * Unit test WITH Mockito: the repository is mocked, no database is used.
 */
@ExtendWith(MockitoExtension.class)
class ParticipantServicesImplMockitoTest {

    @Mock
    private ParticipantRepository participantRepository;

    @InjectMocks
    private ParticipantServicesImpl service;

    private Participant buildParticipant(String nom, String prenom, Tache tache) {
        Participant p = new Participant();
        p.setNom(nom);
        p.setPrenom(prenom);
        p.setTache(tache);
        return p;
    }

    @Test
    void addParticipant_shouldSaveAndReturn() {
        Participant p = buildParticipant("Tounsi", "Ahmed", Tache.ORGANISATEUR);
        when(participantRepository.save(p)).thenReturn(p);

        Participant result = service.addParticipant(p);

        assertEquals("Tounsi", result.getNom());
        verify(participantRepository, times(1)).save(p);
    }

    @Test
    void getAllParticipants_shouldReturnList() {
        List<Participant> list = Arrays.asList(
                buildParticipant("A", "A", Tache.INVITE),
                buildParticipant("B", "B", Tache.SERVEUR));
        when(participantRepository.findAll()).thenReturn(list);

        List<Participant> result = service.getAllParticipants();

        assertEquals(2, result.size());
        verify(participantRepository).findAll();
    }

    @Test
    void getParticipantById_found_shouldReturnParticipant() {
        Participant p = buildParticipant("Tounsi", "Ahmed", Tache.INVITE);
        when(participantRepository.findById(1)).thenReturn(Optional.of(p));

        Participant result = service.getParticipantById(1);

        assertSame(p, result);
    }

    @Test
    void getParticipantById_notFound_shouldThrow404() {
        when(participantRepository.findById(99)).thenReturn(Optional.empty());

        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> service.getParticipantById(99));

        assertEquals(404, ex.getStatus().value());
    }

    @Test
    void updateParticipant_shouldChangeFieldsAndSave() {
        Participant existing = buildParticipant("Old", "Name", Tache.INVITE);
        Participant changes = buildParticipant("New", "Person", Tache.ANIMATEUR);
        when(participantRepository.findById(1)).thenReturn(Optional.of(existing));
        when(participantRepository.save(existing)).thenReturn(existing);

        Participant result = service.updateParticipant(1, changes);

        assertEquals("New", result.getNom());
        assertEquals("Person", result.getPrenom());
        assertEquals(Tache.ANIMATEUR, result.getTache());
        verify(participantRepository).save(existing);
    }

    @Test
    void updateParticipant_notFound_shouldThrowAndNotSave() {
        when(participantRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(ResponseStatusException.class,
                () -> service.updateParticipant(99, new Participant()));

        verify(participantRepository, never()).save(any());
    }

    @Test
    void changeTache_shouldUpdateTache() {
        Participant p = buildParticipant("Tounsi", "Ahmed", Tache.INVITE);
        when(participantRepository.findById(1)).thenReturn(Optional.of(p));
        when(participantRepository.save(p)).thenReturn(p);

        Participant result = service.changeTache(1, Tache.SERVEUR);

        assertEquals(Tache.SERVEUR, result.getTache());
    }

    @Test
    void deleteParticipant_shouldCallDelete() {
        Participant p = buildParticipant("Tounsi", "Ahmed", Tache.INVITE);
        when(participantRepository.findById(1)).thenReturn(Optional.of(p));

        service.deleteParticipant(1);

        verify(participantRepository).delete(p);
    }

    @Test
    void deleteParticipant_notFound_shouldThrowAndNotDelete() {
        when(participantRepository.findById(99)).thenReturn(Optional.empty());

        assertThrows(ResponseStatusException.class, () -> service.deleteParticipant(99));

        verify(participantRepository, never()).delete(any());
    }
}
