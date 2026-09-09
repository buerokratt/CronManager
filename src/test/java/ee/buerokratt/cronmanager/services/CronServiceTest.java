package ee.buerokratt.cronmanager.services;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import ee.buerokratt.cronmanager.model.ShellExecuteJob;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.quartz.CronTrigger;
import org.quartz.JobDataMap;
import org.quartz.JobDetail;
import org.quartz.JobExecutionContext;
import org.quartz.JobKey;
import org.quartz.Scheduler;
import org.quartz.SchedulerException;
import org.quartz.Trigger;
import org.quartz.impl.matchers.GroupMatcher;

import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CronServiceTest {

    private Scheduler scheduler;
    private CronService cronService;
    private ObjectMapper mapper;

    @BeforeEach
    void setUp() {
        scheduler = mock(Scheduler.class);
        mapper = new ObjectMapper();
        cronService = new CronService(scheduler, mapper);
    }

    private CronTrigger cronTriggerWithSchedule(String expression, Date nextFireTime) {
        CronTrigger trigger = mock(CronTrigger.class);
        when(trigger.getCronExpression()).thenReturn(expression);
        when(trigger.getPreviousFireTime()).thenReturn(null);
        when(trigger.getNextFireTime()).thenReturn(nextFireTime);
        return trigger;
    }

    @Test
    void getJobsGroupsScheduledJobsByGroupAndOnlyIncludesThoseWithTriggers() throws SchedulerException, JsonProcessingException {
        JobKey scheduledJob = new JobKey("scheduledJob", "group1");
        JobKey unscheduledJob = new JobKey("unscheduledJob", "group2");

        when(scheduler.getJobKeys(any(GroupMatcher.class))).thenReturn(Set.of(scheduledJob, unscheduledJob));

        Date nextFireTime = new Date(5000L);
        List<Trigger> triggers = List.of(cronTriggerWithSchedule("0 0 * * * ?", nextFireTime));
        doReturn(triggers).when(scheduler).getTriggersOfJob(scheduledJob);
        doReturn(List.of()).when(scheduler).getTriggersOfJob(unscheduledJob);

        String json = cronService.getJobs(null);
        JsonNode root = mapper.readTree(json);

        assertEquals(1, root.get("group1").size());
        assertEquals("scheduledJob", root.get("group1").get(0).get("name").asText());
        assertEquals("0 0 * * * ?", root.get("group1").get(0).get("schedule").asText());
        assertEquals(5000L, root.get("group1").get(0).get("nextExecution").asLong());
        assertEquals(0L, root.get("group1").get(0).get("lastExecution").asLong());

        assertTrue(root.get("group2").isEmpty());
    }

    @Test
    void getRunningJobsFiltersByGroup() throws SchedulerException, JsonProcessingException {
        JobExecutionContext runningInGroup1 = mock(JobExecutionContext.class);
        JobDetail jobDetail1 = mock(JobDetail.class);
        when(jobDetail1.getKey()).thenReturn(new JobKey("job1", "group1"));
        when(runningInGroup1.getJobDetail()).thenReturn(jobDetail1);

        JobExecutionContext runningInGroup2 = mock(JobExecutionContext.class);
        JobDetail jobDetail2 = mock(JobDetail.class);
        when(jobDetail2.getKey()).thenReturn(new JobKey("job2", "group2"));
        when(runningInGroup2.getJobDetail()).thenReturn(jobDetail2);

        when(scheduler.getCurrentlyExecutingJobs()).thenReturn(List.of(runningInGroup1, runningInGroup2));
        doReturn(List.of()).when(scheduler).getTriggersOfJob(any());

        String json = cronService.getRunningJobs("group1");
        JsonNode root = mapper.readTree(json);

        assertTrue(root.has("group1"));
        assertTrue(root.get("group1").isEmpty());
        assertTrue(!root.has("group2"));
    }

    @Test
    void executeJobFiltersAllowedEnvsAndUpdatesJobBeforeTriggering() throws SchedulerException {
        JobKey jobKey = new JobKey("shellJob", "group1");
        when(scheduler.getJobKeys(any(GroupMatcher.class))).thenReturn(Set.of(jobKey));

        JobDetail jobDetail = mock(JobDetail.class);
        JobDataMap jdm = new JobDataMap();
        jdm.put("allowedEnvs", "ENV1,ENV2");
        when(jobDetail.getJobClass()).thenReturn((Class) ShellExecuteJob.class);
        when(jobDetail.getJobDataMap()).thenReturn(jdm);
        when(scheduler.getJobDetail(jobKey)).thenReturn(jobDetail);
        when(scheduler.getCurrentlyExecutingJobs()).thenReturn(List.of());

        Map<String, String[]> params = new HashMap<>();
        params.put("ENV1", new String[]{"value1"});
        params.put("IGNORED", new String[]{"ignoredValue"});

        cronService.executeJob("group1", "shellJob", params);

        assertEquals("ENV1=value1", jdm.get("params"));
        verify(scheduler).addJob(eq(jobDetail), eq(true));
        verify(scheduler).triggerJob(jobKey);
    }

    @Test
    void executeJobSkipsEnvFilteringForNonShellJobs() throws SchedulerException {
        JobKey jobKey = new JobKey("httpJob", "group1");
        when(scheduler.getJobKeys(any(GroupMatcher.class))).thenReturn(Set.of(jobKey));

        JobDetail jobDetail = mock(JobDetail.class);
        when(jobDetail.getJobClass()).thenReturn((Class) Object.class);
        when(jobDetail.getJobDataMap()).thenReturn(new JobDataMap());
        when(scheduler.getJobDetail(jobKey)).thenReturn(jobDetail);
        when(scheduler.getCurrentlyExecutingJobs()).thenReturn(List.of());

        cronService.executeJob("group1", "httpJob", Map.of());

        verify(scheduler, never()).addJob(any(JobDetail.class), any(Boolean.class));
        verify(scheduler).triggerJob(jobKey);
    }

    @Test
    void stopJobInterruptsMatchingRunningJob() throws SchedulerException {
        JobExecutionContext running = mock(JobExecutionContext.class);
        JobDetail jobDetail = mock(JobDetail.class);
        JobKey jobKey = new JobKey("job1", "group1");
        when(jobDetail.getKey()).thenReturn(jobKey);
        when(running.getJobDetail()).thenReturn(jobDetail);

        when(scheduler.getCurrentlyExecutingJobs()).thenReturn(List.of(running));
        doReturn(List.of()).when(scheduler).getTriggersOfJob(any());

        cronService.stopJob("group1", "job1");

        verify(scheduler).interrupt(jobKey);
    }
}
