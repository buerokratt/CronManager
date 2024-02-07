package ee.buerokratt.cronmanager;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.ComponentScan;

@SpringBootApplication
@ComponentScan("ee.buerokratt.cronmanager")
public class CronManagerApplication {

	public static void main(String[] args) {
		SpringApplication.run(CronManagerApplication.class, args);
	}

}
