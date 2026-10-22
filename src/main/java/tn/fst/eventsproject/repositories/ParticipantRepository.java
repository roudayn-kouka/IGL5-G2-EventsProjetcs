package tn.fst.eventsproject.repositories;

import org.springframework.data.jpa.repository.JpaRepository;
import tn.fst.eventsproject.entities.Participant;

public interface ParticipantRepository extends JpaRepository<Participant, Integer> {
}