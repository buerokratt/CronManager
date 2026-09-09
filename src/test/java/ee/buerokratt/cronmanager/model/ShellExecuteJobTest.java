package ee.buerokratt.cronmanager.model;

import org.junit.jupiter.api.Test;
import org.quartz.JobDataMap;
import org.quartz.JobDetail;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assumptions.assumeTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ShellExecuteJobTest {

    @Test
    void getTypeIsExec() {
        assertEquals("exec", new ShellExecuteJob().getType());
    }

    @Test
    void getJobDataOmitsAllowedEnvsWhenNotSet() {
        ShellExecuteJob job = new ShellExecuteJob();
        job.setName("myjob");
        job.setCommand("./run.sh");

        JobDataMap data = job.getJobData();

        assertEquals("./run.sh", data.getString("command"));
        assertFalse(data.containsKey("allowedEnvs"));
    }

    @Test
    void getJobDataJoinsAllowedEnvsWithComma() {
        ShellExecuteJob job = new ShellExecuteJob();
        job.setName("myjob");
        job.setCommand("./run.sh");
        job.setAllowedEnvs(List.of("ENV1", "ENV2"));

        JobDataMap data = job.getJobData();

        assertEquals("ENV1,ENV2", data.getString("allowedEnvs"));
    }

    @Test
    void toStringFormatsFields() {
        ShellExecuteJob job = new ShellExecuteJob();
        job.setName("myjob");
        job.setTrigger("0 0 * * * ?");
        job.setCommand("./run.sh");
        job.setStartDate(1000L);
        job.setEndDate(2000L);

        assertEquals("myjob (0 0 * * * ?) => \"./run.sh\" [1000 -> 2000]", job.toString());
    }

    private JobExecutionContext contextWithDataMap(JobDataMap jdm, Object parentResult) {
        JobDetail jobDetail = mock(JobDetail.class);
        when(jobDetail.getJobDataMap()).thenReturn(jdm);
        JobExecutionContext context = mock(JobExecutionContext.class);
        when(context.getJobDetail()).thenReturn(jobDetail);
        when(context.getResult()).thenReturn(parentResult);
        return context;
    }

    @Test
    void executeThrowsWhenOutsideDateRangeWithoutRunningCommand() {
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");
        // command intentionally omitted: if execProcess were reached, it would blow up on a null command

        JobExecutionContext context = contextWithDataMap(jdm, "<");

        ShellExecuteJob job = new ShellExecuteJob();

        assertThrows(JobExecutionException.class, () -> job.execute(context));
    }

    @Test
    void executeRunsCommandWhenWithinDateRange() {
        // execProcess() hardcodes "/app/" as its working directory, so skip where that doesn't exist.
        assumeTrue(Files.isDirectory(Path.of("/app")), "requires /app directory, matching ShellExecuteJob's hardcoded working directory");

        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");
        jdm.put("command", "echo hello");

        JobExecutionContext context = contextWithDataMap(jdm, "");

        ShellExecuteJob job = new ShellExecuteJob();

        assertDoesNotThrow(() -> job.execute(context));
    }
}
