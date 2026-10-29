package tn.fst.eventsproject.dto;

import lombok.Data;

@Data
public class LogisticsDTO {
    private int idLog;
    private String description;
    private boolean reserve;
    private float prixUnit;
    private int quantite;
}
