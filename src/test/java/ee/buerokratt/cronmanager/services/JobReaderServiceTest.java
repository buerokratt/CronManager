package ee.buerokratt.cronmanager.services;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import ee.buerokratt.cronmanager.model.HttpRequestJob;
import ee.buerokratt.cronmanager.model.ShellExecuteJob;
import ee.buerokratt.cronmanager.model.YamlJob;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.quartz.SchedulerException;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

class JobReaderServiceTest {

    @TempDir
    Path tempDir;

    private ObjectMapper ymlMapper;
    private CronService cron;
    private JobReaderService jobReaderService;

    @BeforeEach
    void setUp() {
        ymlMapper = new ObjectMapper(new YAMLFactory())
                .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
        cron = mock(CronService.class);
        // configPath points at the (initially empty) temp dir, so the constructor's
        // eager readServices() call is a no-op and doesn't interfere with the tests below.
        jobReaderService = new JobReaderService(ymlMapper, cron, tempDir.toString());
    }

    private Path writeYaml(String filename, String content) throws IOException {
        Path file = tempDir.resolve(filename);
        Files.writeString(file, content);
        return file;
    }

    @Test
    void readServiceParsesHttpAndExecJobTypes() throws IOException {
        Path file = writeYaml("mygroup.yaml", """
                job1:
                  type: http
                  method: GET
                  url: https://example.com
                  trigger: "0 0 * * * ?"
                job2:
                  type: exec
                  command: ./run.sh
                  trigger: "0 0 * * * ?"
                """);

        List<YamlJob> jobs = jobReaderService.readService("mygroup", file.toFile());

        assertEquals(2, jobs.size());

        YamlJob httpJob = jobs.stream().filter(j -> "job1".equals(j.getName())).findFirst().orElseThrow();
        assertInstanceOf(HttpRequestJob.class, httpJob);
        assertEquals("GET", ((HttpRequestJob) httpJob).getMethod());
        assertEquals("https://example.com", ((HttpRequestJob) httpJob).getUrl());

        YamlJob execJob = jobs.stream().filter(j -> "job2".equals(j.getName())).findFirst().orElseThrow();
        assertInstanceOf(ShellExecuteJob.class, execJob);
        assertEquals("./run.sh", ((ShellExecuteJob) execJob).getCommand());
    }

    @Test
    void readServiceThrowsOnUnknownJobType() throws IOException {
        Path file = writeYaml("badgroup.yaml", """
                job1:
                  type: bogus
                """);

        assertThrows(RuntimeException.class, () -> jobReaderService.readService("badgroup", file.toFile()));
    }

    @Test
    void readServicesFromFileDerivesGroupNameFromFilenameAndSchedulesEachJob() throws IOException, SchedulerException {
        Path file = writeYaml("mygroup.yaml", """
                job1:
                  type: exec
                  command: ./run.sh
                  trigger: "0 0 * * * ?"
                """);

        jobReaderService.readServicesFromFile(file);

        verify(cron, times(1)).scheduleJob(eq("mygroup"), any(YamlJob.class));
    }

    @Test
    void readServicesWalksDirectorySkippingSubdirectories() throws IOException, SchedulerException {
        writeYaml("group1.yaml", """
                job1:
                  type: exec
                  command: ./run1.sh
                  trigger: "0 0 * * * ?"
                """);
        writeYaml("group2.yaml", """
                job2:
                  type: exec
                  command: ./run2.sh
                  trigger: "0 0 * * * ?"
                """);
        Files.createDirectory(tempDir.resolve("subdir"));

        jobReaderService.readServices(tempDir.toString());

        verify(cron, times(1)).scheduleJob(eq("group1"), any(YamlJob.class));
        verify(cron, times(1)).scheduleJob(eq("group2"), any(YamlJob.class));
    }
}
