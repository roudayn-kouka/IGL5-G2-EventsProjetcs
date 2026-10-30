package tn.fst.eventsproject.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import tn.fst.eventsproject.entities.Logistics;

@Getter
@Setter
@NoArgsConstructor
public class LogisticsWriteRequest {
    private int idLog;
    private String description;
    private boolean reserve;
    private float prixUnit;
    private int quantite;

    public Logistics toEntity() {
        Logistics logistics = new Logistics();
        logistics.setIdLog(idLog);
        logistics.setDescription(description);
        logistics.setReserve(reserve);
        logistics.setPrixUnit(prixUnit);
        logistics.setQuantite(quantite);
        return logistics;
    }
}
