package tn.fst.eventsproject.services;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.MockitoJUnitRunner;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;

import static org.junit.Assert.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * AVEC Mockito : règles métier d'EventServicesImpl (affectations, logistique, calcul du coût).
 * Chaque test couvre une des deux branches des conditions du service.
 */
@RunWith(MockitoJUnitRunner.class)
public class EventServicesAffectationMockTest {

    @Mock
    EventRepository eventRepository;
    @Mock
    ParticipantRepository participantRepository;
    @Mock
    LogisticsRepository logisticsRepository;

    @InjectMocks
    EventServicesImpl eventServices;

    private Event buildEvent(String description) {
        Event e = new Event();
        e.setDescription(description);
        e.setDateDebut(LocalDate.of(2025, 5, 10));
        e.setDateFin(LocalDate.of(2025, 5, 12));
        return e;
    }

    private Participant buildParticipant(int id) {
        Participant p = new Participant();
        p.setIdPart(id);
        p.setNom("Tounsi");
        p.setPrenom("Ahmed");
        p.setTache(Tache.ORGANISATEUR);
        return p;
    }

    private Logistics buildLogistics(String description, boolean reserve, float prixUnit, int quantite) {
        Logistics l = new Logistics();
        l.setDescription(description);
        l.setReserve(reserve);
        l.setPrixUnit(prixUnit);
        l.setQuantite(quantite);
        return l;
    }

    @Test
    public void testAddParticipant() {
        Participant participant = buildParticipant(1);
        when(participantRepository.save(participant)).thenReturn(participant);

        assertSame(participant, eventServices.addParticipant(participant));
        verify(participantRepository).save(participant);
    }

    @Test
    public void testAddAffectEvenParticipantSansEvenementsExistants() {
        Event event = buildEvent("Hackathon");
        Participant participant = buildParticipant(1); // events == null
        when(participantRepository.findById(1)).thenReturn(Optional.of(participant));
        when(eventRepository.save(event)).thenReturn(event);

        Event result = eventServices.addAffectEvenParticipant(event, 1);

        assertSame(event, result);
        assertEquals(1, participant.getEvents().size());
        assertTrue(participant.getEvents().contains(event));
    }

    @Test
    public void testAddAffectEvenParticipantAvecEvenementsExistants() {
        Event existant = buildEvent("Forum");
        Event event = buildEvent("Hackathon");
        Participant participant = buildParticipant(1);
        participant.setEvents(new HashSet<>(Collections.singletonList(existant)));
        when(participantRepository.findById(1)).thenReturn(Optional.of(participant));
        when(eventRepository.save(event)).thenReturn(event);

        eventServices.addAffectEvenParticipant(event, 1);

        assertEquals(2, participant.getEvents().size());
        assertTrue(participant.getEvents().contains(existant));
        assertTrue(participant.getEvents().contains(event));
    }

    @Test
    public void testAddAffectEvenParticipantPourTousLesParticipants() {
        Participant sansEvenement = buildParticipant(1);
        Participant avecEvenement = buildParticipant(2);
        Event existant = buildEvent("Forum");
        avecEvenement.setEvents(new HashSet<>(Collections.singletonList(existant)));

        Event event = buildEvent("Hackathon");
        event.setParticipants(new HashSet<>(Arrays.asList(buildParticipant(1), buildParticipant(2))));
        when(participantRepository.findById(1)).thenReturn(Optional.of(sansEvenement));
        when(participantRepository.findById(2)).thenReturn(Optional.of(avecEvenement));
        when(eventRepository.save(event)).thenReturn(event);

        Event result = eventServices.addAffectEvenParticipant(event);

        assertSame(event, result);
        assertEquals(Collections.singleton(event), sansEvenement.getEvents());
        assertEquals(2, avecEvenement.getEvents().size());
        assertTrue(avecEvenement.getEvents().contains(event));
        verify(eventRepository, times(1)).save(event);
    }

    @Test
    public void testAddAffectLogSurEvenementSansLogistique() {
        Event event = buildEvent("Hackathon"); // logistics == null
        Logistics chaises = buildLogistics("Chaises", true, 2.5f, 100);
        when(eventRepository.findByDescription("Hackathon")).thenReturn(event);
        when(logisticsRepository.save(chaises)).thenReturn(chaises);

        Logistics result = eventServices.addAffectLog(chaises, "Hackathon");

        assertSame(chaises, result);
        assertEquals(Collections.singleton(chaises), event.getLogistics());
        verify(eventRepository).save(event); // l'événement est sauvegardé avec son nouvel ensemble
    }

    @Test
    public void testAddAffectLogSurEvenementAvecLogistique() {
        Event event = buildEvent("Hackathon");
        Logistics stands = buildLogistics("Stands", true, 120f, 4);
        event.setLogistics(new HashSet<>(Collections.singletonList(stands)));
        Logistics chaises = buildLogistics("Chaises", true, 2.5f, 100);
        when(eventRepository.findByDescription("Hackathon")).thenReturn(event);
        when(logisticsRepository.save(chaises)).thenReturn(chaises);

        eventServices.addAffectLog(chaises, "Hackathon");

        assertEquals(2, event.getLogistics().size());
        assertTrue(event.getLogistics().contains(chaises));
        verify(eventRepository, never()).save(any(Event.class));
    }

    @Test
    public void testGetLogisticsDatesNeRetourneQueLaLogistiqueReservee() {
        LocalDate debut = LocalDate.of(2025, 5, 1);
        LocalDate fin = LocalDate.of(2025, 5, 31);
        Logistics reservee = buildLogistics("Chaises", true, 2.5f, 100);
        Logistics nonReservee = buildLogistics("Goodies", false, 4f, 50);
        Event event = buildEvent("Hackathon");
        event.setLogistics(new HashSet<>(Arrays.asList(reservee, nonReservee)));
        when(eventRepository.findByDateDebutBetween(debut, fin)).thenReturn(Collections.singletonList(event));

        List<Logistics> result = eventServices.getLogisticsDates(debut, fin);

        assertEquals(Collections.singletonList(reservee), result);
    }

    @Test
    public void testGetLogisticsDatesEvenementSansLogistique() {
        LocalDate debut = LocalDate.of(2025, 5, 1);
        LocalDate fin = LocalDate.of(2025, 5, 31);
        Event event = buildEvent("Hackathon");
        event.setLogistics(new HashSet<>());
        when(eventRepository.findByDateDebutBetween(debut, fin)).thenReturn(Collections.singletonList(event));

        assertNull(eventServices.getLogisticsDates(debut, fin));
    }

    @Test
    public void testGetLogisticsDatesAucunEvenement() {
        LocalDate debut = LocalDate.of(2025, 5, 1);
        LocalDate fin = LocalDate.of(2025, 5, 31);
        when(eventRepository.findByDateDebutBetween(debut, fin)).thenReturn(Collections.emptyList());

        assertTrue(eventServices.getLogisticsDates(debut, fin).isEmpty());
    }

    @Test
    public void testCalculCoutNeCompteQueLaLogistiqueReservee() {
        Event avecLogistique = buildEvent("Hackathon");
        avecLogistique.setLogistics(new HashSet<>(Arrays.asList(
                buildLogistics("Chaises", true, 2.5f, 100),   // 250
                buildLogistics("Stands", true, 120f, 2),      // 240
                buildLogistics("Goodies", false, 4f, 50))));  // ignoré : non réservé
        Event sansLogistique = buildEvent("Forum");           // logistics == null
        sansLogistique.setCout(999f);
        when(eventRepository.findByParticipants_NomAndParticipants_PrenomAndParticipants_Tache(
                "Tounsi", "Ahmed", Tache.ORGANISATEUR))
                .thenReturn(Arrays.asList(avecLogistique, sansLogistique));

        eventServices.calculCout();

        assertEquals(490f, avecLogistique.getCout(), 0.001);
        assertEquals(0f, sansLogistique.getCout(), 0.001); // somme remise à zéro par événement
        ArgumentCaptor<Event> saved = ArgumentCaptor.forClass(Event.class);
        verify(eventRepository, times(2)).save(saved.capture());
        assertEquals(Arrays.asList(avecLogistique, sansLogistique), saved.getAllValues());
    }
}
