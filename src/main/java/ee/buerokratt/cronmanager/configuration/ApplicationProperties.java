package ee.buerokratt.cronmanager.configuration;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "application")
@EnableConfigurationProperties
public class ApplicationProperties {
    private String configPath;
}
