package tn.fst.eventsproject.services;

import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;

import java.time.LocalDate;
import java.util.List;

public interface IEventServices {
    Event addEvent(Event event);
    Event retrieveEvent(int idEvent);
    Event updateEvent(Event event);
    void deleteEvent(int idEvent);
    public Participant addParticipant(Participant participant);
    public Event addAffectEvenParticipant(Event event, int idParticipant);
    public Event addAffectEvenParticipant(Event event);
    public Logistics addAffectLog(Logistics logistics, String descriptionEvent);
    public List<Logistics> getLogisticsDates(LocalDate date_debut, LocalDate date_fin);
    public void calculCout();
}
