package tn.esprit.eventsproject.services;

import lombok.AccessLevel;
import lombok.RequiredArgsConstructor;
import lombok.experimental.FieldDefaults;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import tn.esprit.eventsproject.entities.Logistics;
import tn.esprit.eventsproject.repositories.LogisticsRepository;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE, makeFinal = true)
public class LogisticsServiceImpl implements ILogisticsService {

    LogisticsRepository logisticsRepository;

    @Override
    public Logistics addLogistics(Logistics logistics) {
        return logisticsRepository.save(logistics);
    }

    @Override
    public Logistics updateLogistics(Logistics logistics) {
        return logisticsRepository.save(logistics); // save() fait un update si l'id existe
    }

    @Override
    public void deleteLogistics(int idLog) {
        logisticsRepository.deleteById(idLog);
    }

    @Override
    public Logistics getLogisticsById(int idLog) {
        return logisticsRepository.findById(idLog)
                .orElseThrow(() -> new IllegalArgumentException("Logistics introuvable : " + idLog));
    }

    @Override
    public List<Logistics> getAllLogistics() {
        return logisticsRepository.findAll();
    }

    @Override
    public List<Logistics> getReservedLogistics() {
        return logisticsRepository.findByReserveTrue();
    }

    @Override
    public float calculerCoutTotal(int idLog) {
        Logistics l = getLogisticsById(idLog);
        float total = l.getPrixUnit() * l.getQuantite();
        log.info("Coût total de {} = {}", l.getDescription(), total);
        return total;
    }
}