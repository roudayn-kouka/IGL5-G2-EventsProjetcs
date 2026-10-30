package tn.fst.eventsproject.services;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;
import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;
import tn.fst.eventsproject.entities.Tache;
import tn.fst.eventsproject.repositories.EventRepository;
import tn.fst.eventsproject.repositories.LogisticsRepository;
import tn.fst.eventsproject.repositories.ParticipantRepository;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
@Slf4j
@RequiredArgsConstructor
@Service
public class EventServicesImpl implements IEventServices{

    private final EventRepository eventRepository;
    private final ParticipantRepository participantRepository;
    private final LogisticsRepository logisticsRepository;

    @Override
    public Participant addParticipant(Participant participant) {
        return participantRepository.save(participant);
    }

    @Override
    public Event addAffectEvenParticipant(Event event, int idParticipant) {
        Participant participant = participantRepository.findById(idParticipant)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Participant not found"));
        if(participant.getEvents() == null){
            Set<Event> events = new HashSet<>();
            events.add(event);
            participant.setEvents(events);
        }else {
            participant.getEvents().add(event);
        }
        return eventRepository.save(event);
    }

    @Override
    public Event addAffectEvenParticipant(Event event) {
        Set<Participant> participants = event.getParticipants();
        if (participants == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Event participants are required");
        }
        for(Participant aParticipant:participants){
            Participant participant = participantRepository.findById(aParticipant.getIdPart())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Participant not found"));
            if(participant.getEvents() == null){
                Set<Event> events = new HashSet<>();
                events.add(event);
                participant.setEvents(events);
            }else {
                participant.getEvents().add(event);
            }
        }
        return eventRepository.save(event);
    }

    @Override
    public Logistics addAffectLog(Logistics logistics, String descriptionEvent) {
      Event event = eventRepository.findByDescription(descriptionEvent);
      if(event.getLogistics() == null){
          Set<Logistics> logisticsSet = new HashSet<>();
          logisticsSet.add(logistics);
          event.setLogistics(logisticsSet);
          eventRepository.save(event);
      }
      else{
          event.getLogistics().add(logistics);
      }
        return logisticsRepository.save(logistics);
    }

    @Override
    public List<Logistics> getLogisticsDates(LocalDate dateDebut, LocalDate dateFin) {
        List<Event> events = eventRepository.findByDateDebutBetween(dateDebut, dateFin);

        List<Logistics> logisticsList = new ArrayList<>();
        for (Event event:events){
            if (!event.getLogistics().isEmpty()) {
                Set<Logistics> logisticsSet = event.getLogistics();
                for (Logistics logistics:logisticsSet){
                    if(logistics.isReserve())
                        logisticsList.add(logistics);
                }
            }
        }
        return logisticsList;
    }

    @Scheduled(cron = "*/60 * * * * *")
    @Override
    public void calculCout() {
        List<Event> events = eventRepository.findByParticipants_NomAndParticipants_PrenomAndParticipants_Tache("Tounsi","Ahmed", Tache.ORGANISATEUR);
        for(Event event:events){
            float somme = 0f; // remis à zéro pour chaque événement
            log.info(event.getDescription());
            Set<Logistics> logisticsSet = event.getLogistics() != null
                    ? event.getLogistics() : new HashSet<>();
            for (Logistics logistics:logisticsSet){
                if(logistics.isReserve())
                    somme+=logistics.getPrixUnit()*logistics.getQuantite();
            }
            event.setCout(somme);
            eventRepository.save(event);
            log.info("Cout de l'Event "+event.getDescription()+" est "+ somme);

        }
    }

    @Override
    public Event addEvent(Event event) {
        return eventRepository.save(event);
    }

    @Override
    public Event retrieveEvent(int idEvent) {
        return eventRepository.findById(idEvent).orElse(null);
    }

    @Override
    public Event updateEvent(Event event) {
        return eventRepository.save(event);
    }

    @Override
    public void deleteEvent(int idEvent) {
        eventRepository.deleteById(idEvent);
    }


}
