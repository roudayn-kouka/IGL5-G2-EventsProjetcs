package tn.esprit.eventsproject.controllers;

import lombok.AccessLevel;
import lombok.RequiredArgsConstructor;
import lombok.experimental.FieldDefaults;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;
import tn.esprit.eventsproject.dto.EventStatsDTO;
import tn.esprit.eventsproject.services.IEventStatsService;

import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/event-stats")
@RequiredArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE, makeFinal = true)
public class EventStatsController {

    IEventStatsService eventStatsService;

    // GET /event-stats/{id}
    @GetMapping("/{id}")
    public EventStatsDTO getEventStats(@PathVariable("id") int idEvent) {
        return eventStatsService.getEventStats(idEvent);
    }

    // GET /event-stats/upcoming
    @GetMapping("/upcoming")
    public List<EventStatsDTO> getUpcomingEventsStats() {
        return eventStatsService.getUpcomingEventsStats();
    }

    // GET /event-stats/between/2025-05-01/2025-05-31
    @GetMapping("/between/{d1}/{d2}")
    public List<EventStatsDTO> getEventsStatsBetween(
            @PathVariable("d1") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate d1,
            @PathVariable("d2") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate d2) {
        return eventStatsService.getEventsStatsBetween(d1, d2);
    }
}
