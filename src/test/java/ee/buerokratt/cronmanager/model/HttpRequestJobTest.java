package ee.buerokratt.cronmanager.model;

import ee.buerokratt.cronmanager.services.HttpHelper;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.quartz.JobDataMap;
import org.quartz.JobDetail;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

class HttpRequestJobTest {

    @Test
    void getTypeIsHttp() {
        assertEquals("http", new HttpRequestJob().getType());
    }

    @Test
    void getJobDataIncludesMethodAndUrl() {
        HttpRequestJob job = new HttpRequestJob();
        job.setName("myjob");
        job.setMethod("GET");
        job.setUrl("https://example.com");

        JobDataMap data = job.getJobData();

        assertEquals("GET", data.getString("method"));
        assertEquals("https://example.com", data.getString("url"));
    }

    @Test
    void toStringFormatsFields() {
        HttpRequestJob job = new HttpRequestJob();
        job.setName("myjob");
        job.setTrigger("0 0 * * * ?");
        job.setMethod("GET");
        job.setUrl("https://example.com");
        job.setStartDate(1000L);
        job.setEndDate(2000L);

        assertEquals("myjob (0 0 * * * ?) => GET: https://example.com [1000 -> 2000]", job.toString());
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
    void executeThrowsWhenOutsideDateRangeWithoutCallingHttpHelper() {
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");

        JobExecutionContext context = contextWithDataMap(jdm, ">");

        HttpRequestJob job = new HttpRequestJob();

        try (MockedStatic<HttpHelper> httpHelper = mockStatic(HttpHelper.class)) {
            assertThrows(JobExecutionException.class, () -> job.execute(context));
            httpHelper.verifyNoInteractions();
        }
    }

    @Test
    void executeCallsHttpHelperWithMethodAndUrlWhenWithinDateRange() {
        JobDataMap jdm = new JobDataMap();
        jdm.put("name", "myjob");
        jdm.put("trigger", "0 0 * * * ?");
        jdm.put("method", "GET");
        jdm.put("url", "https://example.com");

        JobExecutionContext context = contextWithDataMap(jdm, "");

        HttpRequestJob job = new HttpRequestJob();

        try (MockedStatic<HttpHelper> httpHelper = mockStatic(HttpHelper.class)) {
            httpHelper.when(() -> HttpHelper.doRequest("GET", "https://example.com"))
                    .thenReturn(ResponseEntity.ok("body"));

            assertDoesNotThrow(() -> job.execute(context));

            httpHelper.verify(() -> HttpHelper.doRequest(eq("GET"), eq("https://example.com")));
        }
    }
}
