package ee.buerokratt.cronmanager.controllers;

import ee.buerokratt.cronmanager.services.CronService;
import ee.buerokratt.cronmanager.services.JobReaderService;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.quartz.SchedulerException;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CronControllerTest {

    private JobReaderService jobReader;
    private CronService cron;
    private CronController controller;

    @BeforeEach
    void setUp() {
        jobReader = mock(JobReaderService.class);
        cron = mock(CronService.class);
        controller = new CronController();
        controller.jobReader = jobReader;
        controller.cron = cron;
    }

    @Test
    void indexReturnsStartupMessage() {
        assertEquals("BYK Cron started", controller.index());
    }

    @Test
    void jobsWithoutGroupDelegatesWithEmptyGroupName() throws SchedulerException {
        when(cron.getJobs("")).thenReturn("{}");

        assertEquals("{}", controller.jobs());

        verify(cron).getJobs("");
    }

    @Test
    void jobsWrapsSchedulerExceptionInRuntimeException() throws SchedulerException {
        SchedulerException cause = new SchedulerException("boom");
        when(cron.getJobs("group1")).thenThrow(cause);

        RuntimeException thrown = assertThrows(RuntimeException.class, () -> controller.jobs("group1"));
        assertEquals(cause, thrown.getCause());
    }

    @Test
    void runningJobsWithoutGroupDelegatesWithEmptyGroupName() throws SchedulerException {
        when(cron.getRunningJobs("")).thenReturn("{}");

        assertEquals("{}", controller.runningJobs());

        verify(cron).getRunningJobs("");
    }

    @Test
    void executeJobDelegatesWithRequestParameterMap() throws SchedulerException {
        HttpServletRequest request = mock(HttpServletRequest.class);
        Map<String, String[]> params = new HashMap<>();
        params.put("param1", new String[]{"value1"});
        when(request.getParameterMap()).thenReturn(params);
        when(cron.executeJob("group1", "job1", params)).thenReturn("{}");

        assertEquals("{}", controller.executeJob("group1", "job1", request));

        verify(cron).executeJob("group1", "job1", params);
    }

    @Test
    void stopJobDelegatesToService() throws SchedulerException {
        when(cron.stopJob("group1", "job1")).thenReturn("{}");

        assertEquals("{}", controller.stopJob("group1", "job1"));

        verify(cron).stopJob("group1", "job1");
    }

    @Test
    void reloadJobsRereadsServicesBeforeFetchingJobs() throws SchedulerException {
        when(cron.getJobs("group1")).thenReturn("{}");

        assertEquals("{}", controller.reloadJobs("group1"));

        var order = inOrder(jobReader, cron);
        order.verify(jobReader).readServices();
        order.verify(cron).getJobs(eq("group1"));
    }
}
