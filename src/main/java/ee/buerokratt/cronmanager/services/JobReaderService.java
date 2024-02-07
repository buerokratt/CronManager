package ee.buerokratt.cronmanager.services;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import ee.buerokratt.cronmanager.model.HttpRequestJob;
import ee.buerokratt.cronmanager.model.YamlJob;

import ee.buerokratt.cronmanager.utils.LoggingUtils;
import lombok.extern.slf4j.Slf4j;
import org.quartz.SchedulerException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Slf4j
@Service
public class JobReaderService {

    final ObjectMapper mapper;
    final CronService cron;

    String configPath;

    @Autowired
    public JobReaderService(@Qualifier("ymlMapper") ObjectMapper mapper,
                            CronService cron,
                            @Value("${application.configPath}") String configPath) {
        this.mapper = mapper;
        this.cron = cron;
        this.configPath = configPath;

        readServices();
    }

    public void readServices() {
        readServices(configPath);
    }

    public void readServices(String path) {
        try {
            Files.walk(Paths.get(path))
                    .filter(f -> !f.toFile().isDirectory())
                    .forEach(file -> readServicesFromFile(file));
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    private String fileNameToGroupName(String filename) {
        return filename.substring(0, filename.indexOf(".y"));
    }

    public void readServicesFromFile(Path filePath) {
        File file = filePath.toFile();
        log.info("Loading jobs from " + file.getAbsolutePath());
        String groupName = fileNameToGroupName(file.getName());
        List<YamlJob> jobs = readService(groupName, file);
        log.info("Group " + groupName + ", jobs:" + LoggingUtils.listToString(jobs));
        try {
            for (YamlJob job : jobs) {
                cron.scheduleJob(groupName, job);
            }
        } catch (SchedulerException schx) {
            throw new RuntimeException(schx);
        }
    }

    public List<YamlJob> readService(String groupName, File serviceFile) {
        try {
            Map<String, JsonNode> map = mapper.readValue(serviceFile, new TypeReference<>() {
            });
            return map.entrySet().stream().map(
                    this::nodeToJob).collect(Collectors.toList());
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    private YamlJob nodeToJob(Map.Entry<String, JsonNode> entry) {
        try {
            HttpRequestJob job = mapper.treeToValue(entry.getValue(), HttpRequestJob.class);
            job.setName(entry.getKey());
            return job;
        } catch (JsonProcessingException ex) {
            throw new RuntimeException(ex);
        }
    }

}
