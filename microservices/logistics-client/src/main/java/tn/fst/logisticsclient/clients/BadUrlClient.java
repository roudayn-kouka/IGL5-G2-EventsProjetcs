package tn.fst.logisticsclient.clients;

import org.springframework.cloud.openfeign.FeignClient;
import org.springframework.web.bind.annotation.GetMapping;
import tn.fst.logisticsclient.dto.LogisticsDTO;

@FeignClient(name = "bad-url", url = "http://localhost:9999")
public interface BadUrlClient {

    @GetMapping("/logistics/1")
    LogisticsDTO get();
}