package tn.fst.logisticsclient.clients;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import tn.fst.logisticsclient.dto.LogisticsDTO;

@FeignClient(name = "logistics-service")
public interface LogisticsFeignClient {

    @GetMapping("/logistics/{id}")
    LogisticsDTO getById(@PathVariable("id") Integer id);

    @GetMapping("/logistics/{id}/cout")
    float getCout(@PathVariable("id") Integer id);
}