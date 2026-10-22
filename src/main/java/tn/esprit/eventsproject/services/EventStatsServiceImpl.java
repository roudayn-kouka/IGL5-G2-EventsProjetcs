package tn.esprit.eventsproject.services;

import lombok.AccessLevel;
import lombok.RequiredArgsConstructor;
import lombok.experimental.FieldDefaults;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import tn.esprit.eventsproject.dto.EventStatsDTO;
import tn.esprit.eventsproject.entities.Event;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.entities.Participant;
import tn.esprit.eventsproject.entities.Tache;
import tn.esprit.eventsproject.repositories.EventRepository;

import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE, makeFinal = true)
@Transactional(readOnly = true) // nécessaire pour charger la collection LAZY "participants"
public class EventStatsServiceImpl implements IEventStatsService {

    EventRepository eventRepository;

    @Override
    public EventStatsDTO getEventStats(int idEvent) {
        Event event = eventRepository.findById(idEvent)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Event not found with id " + idEvent));
        EventStatsDTO stats = buildStats(event);
        log.info("Stats de l'event {} : {} participants, coût logistique réservée = {}",
                event.getDescription(), stats.getNbParticipants(), stats.getCoutLogistiqueReservee());
        return stats;
    }

    @Override
    public List<EventStatsDTO> getUpcomingEventsStats() {
        return eventRepository.findByDateDebutGreaterThanEqualOrderByDateDebutAsc(LocalDate.now())
                .stream()
                .map(this::buildStats)
                .collect(Collectors.toList());
    }

    @Override
    public List<EventStatsDTO> getEventsStatsBetween(LocalDate d1, LocalDate d2) {
        if (d1 == null || d2 == null || d1.isAfter(d2)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Intervalle de dates invalide : " + d1 + " -> " + d2);
        }
        return eventRepository.findByDateDebutBetween(d1, d2)
                .stream()
                .map(this::buildStats)
                .collect(Collectors.toList());
    }

    /** Construit le DTO statistique à partir de l'entité Event. */
    EventStatsDTO buildStats(Event event) {
        Set<Participant> participants = event.getParticipants() != null
                ? event.getParticipants() : Collections.<Participant>emptySet();
        Set<Logistics> logistics = event.getLogistics() != null
                ? event.getLogistics() : Collections.<Logistics>emptySet();

        // Toutes les tâches apparaissent dans la réponse, même avec 0 participant
        Map<Tache, Long> parTache = new EnumMap<>(Tache.class);
        for (Tache t : Tache.values()) {
            parTache.put(t, 0L);
        }
        for (Participant p : participants) {
            if (p.getTache() != null) {
                parTache.put(p.getTache(), parTache.get(p.getTache()) + 1);
            }
        }

        int nbReservees = 0;
        float cout = 0f;
        for (Logistics l : logistics) {
            if (l.isReserve()) {
                nbReservees++;
                cout += l.getPrixUnit() * l.getQuantite();
            }
        }

        long duree = 0;
        if (event.getDateDebut() != null && event.getDateFin() != null) {
            duree = ChronoUnit.DAYS.between(event.getDateDebut(), event.getDateFin()) + 1;
        }

        return EventStatsDTO.builder()
                .idEvent(event.getIdEvent())
                .description(event.getDescription())
                .dateDebut(event.getDateDebut())
                .dateFin(event.getDateFin())
                .dureeJours(duree)
                .nbParticipants(participants.size())
                .participantsParTache(parTache)
                .nbLogistics(logistics.size())
                .nbLogisticsReservees(nbReservees)
                .coutLogistiqueReservee(cout)
                .build();
    }
}
