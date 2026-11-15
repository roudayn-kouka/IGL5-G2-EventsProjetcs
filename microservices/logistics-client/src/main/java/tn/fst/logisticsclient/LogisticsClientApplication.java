package tn.fst.logisticsclient;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.openfeign.EnableFeignClients;

@SpringBootApplication
@EnableFeignClients
public class LogisticsClientApplication {
    public static void main(String[] args) {
        SpringApplication.run(LogisticsClientApplication.class, args);
    }
}