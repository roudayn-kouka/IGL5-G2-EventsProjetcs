package tn.fst.eventsproject.config;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.Arrays;
import java.util.HashSet;

/**
 * Remplit une base VIDE avec des données de démonstration pour que le dashboard
 * ne soit pas vide au premier lancement.
 *
 * Activé uniquement si app.demo-data=true (dans src/main/resources/application.properties).
 * Désactivé pendant les tests (la propriété n'existe pas dans src/test/resources).
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.demo-data", havingValue = "true")
public class DemoDataLoader implements CommandLineRunner {

    private final EventRepository eventRepository;
    private final ParticipantRepository participantRepository;
    private final LogisticsRepository logisticsRepository;

    @Override
    @Transactional
    public void run(String... args) {
        if (eventRepository.count() > 0) {
            log.info("Données déjà présentes : aucune donnée de démo insérée");
            return;
        }
        LocalDate today = LocalDate.now();

        Event jpo = event("Journée Portes Ouvertes FST", today.plusDays(5), today.plusDays(5),
                logistique("Chaises", true, 2.5f, 300), logistique("Stands", true, 120f, 12),
                logistique("Sonorisation", true, 450f, 1), logistique("Navettes", false, 200f, 3));
        Event hackathon = event("Hackathon DevOps IGL5", today.plusDays(14), today.plusDays(15),
                logistique("Pause-café", true, 6f, 120), logistique("Rallonges & multiprises", true, 15f, 30),
                logistique("Goodies", false, 4f, 150));
        Event cloud = event("Conférence Cloud & DevSecOps", today.plusDays(30), today.plusDays(30),
                logistique("Vidéoprojecteur", true, 80f, 2), logistique("Badges", true, 0.8f, 200),
                logistique("Déjeuner intervenants", false, 35f, 10));
        Event forum = event("Forum Entreprises FST", today.plusDays(52), today.plusDays(53),
                logistique("Stands", true, 120f, 25), logistique("Tables", true, 10f, 60), logistique("Traiteur", false, 18f, 250));
        Event ia = event("Séminaire IA & Data Science", today.minusDays(20), today.minusDays(19),
                logistique("Salle amphi", true, 0f, 1), logistique("Pause-café", true, 6f, 80));
        Event diplomes = event("Cérémonie de remise des diplômes", today.minusDays(60), today.minusDays(60),
                logistique("Chaises", true, 2.5f, 500), logistique("Décoration", true, 900f, 1), logistique("Photographe", true, 600f, 1));

        participant("Tounsi", "Ahmed", Tache.ORGANISATEUR, jpo, hackathon, forum, diplomes);
        participant("Ben Salah", "Mariem", Tache.ORGANISATEUR, cloud, ia);
        participant("Trabelsi", "Yassine", Tache.ANIMATEUR, jpo, hackathon, cloud);
        participant("Gharbi", "Sarra", Tache.ANIMATEUR, forum, diplomes);
        participant("Jaziri", "Omar", Tache.SERVEUR, jpo, forum, diplomes);
        participant("Mabrouk", "Ines", Tache.SERVEUR, hackathon, ia);
        participant("Hammami", "Khalil", Tache.INVITE, jpo, cloud, ia);
        participant("Ayari", "Nour", Tache.INVITE, hackathon, cloud, forum);
        participant("Chaabane", "Aziz", Tache.INVITE, jpo, hackathon, diplomes);
        participant("Bouazizi", "Lina", Tache.INVITE, forum, cloud);
        participant("Karray", "Amine", Tache.INVITE, jpo, ia, diplomes);
        participant("Sassi", "Rim", Tache.INVITE, hackathon, forum);

        log.info("Données de démo insérées : {} événements, {} participants, {} logistiques",
                eventRepository.count(), participantRepository.count(), logisticsRepository.count());
    }

    private Logistics logistique(String description, boolean reserve, float prixUnit, int quantite) {
        Logistics l = new Logistics();
        l.setDescription(description);
        l.setReserve(reserve);
        l.setPrixUnit(prixUnit);
        l.setQuantite(quantite);
        return logisticsRepository.save(l);
    }

    private Event event(String description, LocalDate debut, LocalDate fin, Logistics... logistics) {
        Event e = new Event();
        e.setDescription(description);
        e.setDateDebut(debut);
        e.setDateFin(fin);
        e.setLogistics(new HashSet<>(Arrays.asList(logistics)));
        return eventRepository.save(e);
    }

    private void participant(String nom, String prenom, Tache tache, Event... events) {
        Participant p = new Participant();
        p.setNom(nom);
        p.setPrenom(prenom);
        p.setTache(tache);
        p.setEvents(new HashSet<>(Arrays.asList(events))); // Participant = côté propriétaire
        participantRepository.save(p);
    }
}
