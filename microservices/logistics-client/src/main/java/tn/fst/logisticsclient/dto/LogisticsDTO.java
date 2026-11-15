package tn.fst.logisticsclient.dto;

import lombok.*;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class LogisticsDTO {
    private Integer idLog;
    private String description;
    private Boolean reserve;
    private Float prixUnit;
    private Integer quantite;
}