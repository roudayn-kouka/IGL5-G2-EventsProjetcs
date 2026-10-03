package tn.esprit.eventsproject.services;

import tn.esprit.eventsproject.entities.Logistics;

import java.util.List;

public interface ILogisticsService {
    Logistics addLogistics(Logistics logistics);
    Logistics updateLogistics(Logistics logistics);
    void deleteLogistics(int idLog);
    Logistics getLogisticsById(int idLog);
    List<Logistics> getAllLogistics();
    List<Logistics> getReservedLogistics();
    float calculerCoutTotal(int idLog);
}
