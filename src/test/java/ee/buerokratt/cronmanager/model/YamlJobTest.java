package ee.buerokratt.cronmanager.model;

import org.junit.jupiter.api.Test;
import org.quartz.JobDataMap;
import org.quartz.JobDetail;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class YamlJobTest {

    static class NoopYamlJob extends YamlJob {
        @Override
        public String getType() {
            return "noop";
        }
    }

    private JobExecutionContext contextWithDataMap(JobDataMap jdm) {
        JobDetail jobDetail = mock(JobDetail.class);
        when(jobDetail.getJobDataMap()).thenReturn(jdm);
        JobExecutionContext context = mock(JobExecutionContext.class);
        when(context.getJobDetail()).thenReturn(jobDetail);
        return context;
    }

    @Test
    void getTriggerNameAppendsSuffix() {
        NoopYamlJob job = new NoopYamlJob();
        job.setName("myjob");

        assertEquals("myjob_trigger", job.getTriggerName());
    }

    @Test
    void getJobDataOmitsNullStartAndEndDates() {
        NoopYamlJob job = new NoopYamlJob();
        job.setName("myjob");
        job.setTrigger("0 0 * * * ?");

        JobDataMap data = job.getJobData();

        assertEquals("myjob", data.getString("name"));
        assertEquals("0 0 * * * ?", data.getString("trigger"));
        assertFalse(data.containsKey("startDate"));
        assertFalse(data.containsKey("endDate"));
    }

    @Test
    void getJobDataIncludesStartAndEndDatesWhenSet() {
        NoopYamlJob job = new NoopYamlJob();
        job.setName("myjob");
        job.setStartDate(1000L);
        job.setEndDate(2000L);

        JobDataMap data = job.getJobData();

        assertEquals(1000L, data.getLong("startDate"));
        assertEquals(2000L, data.getLong("endDate"));
    }

    @Test
    void executeSetsResultBelowRangeWhenBeforeStartDate() throws JobExecutionException {
        long future = System.currentTimeMillis() + 100_000;
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");
        jdm.put("startDate", future);

        JobExecutionContext context = contextWithDataMap(jdm);

        NoopYamlJob job = new NoopYamlJob();
        job.execute(context);

        verifyResult(context, "<");
    }

    @Test
    void executeSetsResultAboveRangeWhenAfterEndDate() throws JobExecutionException {
        long past = System.currentTimeMillis() - 100_000;
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");
        jdm.put("endDate", past);

        JobExecutionContext context = contextWithDataMap(jdm);

        NoopYamlJob job = new NoopYamlJob();
        job.execute(context);

        verifyResult(context, ">");
    }

    @Test
    void executeSetsEmptyResultWhenWithinRangeOrUnbounded() throws JobExecutionException {
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");

        JobExecutionContext context = contextWithDataMap(jdm);

        NoopYamlJob job = new NoopYamlJob();
        job.execute(context);

        verifyResult(context, "");
        assertNull(job.getStartDate());
        assertNull(job.getEndDate());
        assertTrue(true);
    }

    private void verifyResult(JobExecutionContext context, String expected) {
        org.mockito.Mockito.verify(context).setResult(expected);
    }
}
