package tn.fst.eventsproject.dto;

import tn.fst.eventsproject.entities.Event;
import tn.fst.eventsproject.entities.Logistics;
import tn.fst.eventsproject.entities.Participant;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/** Conversion entité <-> DTO ; les contrôleurs n'exposent jamais une entité JPA. */
public final class Mapper {
    private Mapper() { }

    // ---- Logistics
    public static LogisticsDTO toDto(Logistics l) {
        if (l == null) return null;
        LogisticsDTO d = new LogisticsDTO();
        d.setIdLog(l.getIdLog());
        d.setDescription(l.getDescription());
        d.setReserve(l.isReserve());
        d.setPrixUnit(l.getPrixUnit());
        d.setQuantite(l.getQuantite());
        return d;
    }

    public static Logistics toEntity(LogisticsDTO d) {
        Logistics l = new Logistics();
        l.setIdLog(d.getIdLog());
        l.setDescription(d.getDescription());
        l.setReserve(d.isReserve());
        l.setPrixUnit(d.getPrixUnit());
        l.setQuantite(d.getQuantite());
        return l;
    }

    public static List<LogisticsDTO> toLogisticsDtos(List<Logistics> list) {
        return list == null ? null : list.stream().map(Mapper::toDto).collect(Collectors.toList());
    }

    // ---- Participant (events : version courte, sans participants ni logistique)
    public static ParticipantDTO toDto(Participant p) {
        if (p == null) return null;
        ParticipantDTO d = shallow(p);
        if (p.getEvents() != null) {
            d.setEvents(p.getEvents().stream().map(e -> shallow(e)).collect(Collectors.toSet()));
        }
        return d;
    }

    public static List<ParticipantDTO> toParticipantDtos(List<Participant> list) {
        return list.stream().map(Mapper::toDto).collect(Collectors.toList());
    }

    public static Participant toEntity(ParticipantDTO d) {
        Participant p = shallowEntity(d);
        if (d.getEvents() != null) {
            p.setEvents(d.getEvents().stream().map(Mapper::shallowEntity).collect(Collectors.toSet()));
        }
        return p;
    }

    // ---- Event (participants : version courte, sans leurs événements)
    public static EventDTO toDto(Event e) {
        if (e == null) return null;
        EventDTO d = shallow(e);
        if (e.getParticipants() != null) {
            d.setParticipants(e.getParticipants().stream().map(Mapper::shallow).collect(Collectors.toSet()));
        }
        if (e.getLogistics() != null) {
            d.setLogistics(e.getLogistics().stream().map(Mapper::toDto).collect(Collectors.toSet()));
        }
        return d;
    }

    public static Event toEntity(EventDTO d) {
        Event e = shallowEntity(d);
        // l'ancien code lisait participants sans null-check : on garde toujours un ensemble
        Set<Participant> parts = new HashSet<>();
        if (d.getParticipants() != null) {
            d.getParticipants().forEach(p -> parts.add(shallowEntity(p)));
        }
        e.setParticipants(parts);
        if (d.getLogistics() != null) {
            e.setLogistics(d.getLogistics().stream().map(Mapper::toEntity).collect(Collectors.toSet()));
        }
        return e;
    }

    private static ParticipantDTO shallow(Participant p) {
        ParticipantDTO d = new ParticipantDTO();
        d.setIdPart(p.getIdPart());
        d.setNom(p.getNom());
        d.setPrenom(p.getPrenom());
        d.setTache(p.getTache());
        return d;
    }

    private static Participant shallowEntity(ParticipantDTO d) {
        Participant p = new Participant();
        p.setIdPart(d.getIdPart());
        p.setNom(d.getNom());
        p.setPrenom(d.getPrenom());
        p.setTache(d.getTache());
        return p;
    }

    private static EventDTO shallow(Event e) {
        EventDTO d = new EventDTO();
        d.setIdEvent(e.getIdEvent());
        d.setDescription(e.getDescription());
        d.setDateDebut(e.getDateDebut());
        d.setDateFin(e.getDateFin());
        d.setCout(e.getCout());
        return d;
    }

    private static Event shallowEntity(EventDTO d) {
        Event e = new Event();
        e.setIdEvent(d.getIdEvent());
        e.setDescription(d.getDescription());
        e.setDateDebut(d.getDateDebut());
        e.setDateFin(d.getDateFin());
        e.setCout(d.getCout());
        return e;
    }
}
