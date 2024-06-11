package ee.buerokratt.cronmanager.services;

import com.fasterxml.jackson.databind.ObjectMapper;
import ee.buerokratt.cronmanager.model.ShellExecuteJob;
import ee.buerokratt.cronmanager.model.YamlJob;
import ee.buerokratt.cronmanager.utils.LoggingUtils;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.quartz.*;
import org.quartz.impl.matchers.GroupMatcher;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import static org.apache.logging.log4j.message.ParameterizedMessage.deepToString;

@Slf4j
@Service
@AllArgsConstructor
public class CronService {

    private final Scheduler scheduler;
    private final ObjectMapper mapper;

    public void scheduleJob(String groupname, YamlJob job) throws SchedulerException {

        JobDetail jobDetail = JobBuilder.newJob(job.getClass())
                .withIdentity(job.getName(), groupname)
                .usingJobData(job.getJobData())
                .storeDurably()
                .build();

        log.info("Adding job %s with trigger %s".formatted(job.getName(), job.getTrigger()));
        if (! "false".equals(job.getTrigger())) {
            Trigger jobTrigger = TriggerBuilder.newTrigger()
                    .withIdentity(job.getTriggerName(), groupname)
                    .startNow()
                    .withSchedule(CronScheduleBuilder.cronSchedule(job.getTrigger()))
                    .build();

            scheduler.scheduleJob(jobDetail, Set.of(jobTrigger), true);
        } else {
            scheduler.addJob(jobDetail, true);
        }
        scheduler.start();
        log.info("Jobs: "+LoggingUtils.listToString(getJobDescriptions()));
    }

    public long getJobCount() {
        try {
            return scheduler.getCurrentlyExecutingJobs().size();
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }

    private String jobInfo(JobKey key) throws SchedulerException {
        return LoggingUtils.listToString(scheduler.getTriggersOfJob(key));
    }

    public List<String> getJobDescriptions() throws SchedulerException {
        Set<JobKey> jobs = scheduler.getJobKeys(GroupMatcher.anyGroup());

        return jobs.stream().map(job -> {
            try {
                return job.getName() + "("+ scheduler.getJobDetail(job).getJobClass().getName() + ")"+ ": "+jobInfo(job);
            } catch (SchedulerException e) {
                throw new RuntimeException(e);
            }
        }).collect(Collectors.toList());
    }

    @AllArgsConstructor
    @Data
    class JobDTO {
        String name;
        String schedule;
        long lastExecution;
        long nextExecution;
        String lastResult;
    }

    private String jobsToJson(Collection<JobKey> jobs) {
        try {
            Map<String, List<JobDTO>> dtos = new HashMap<>();
            for (JobKey job : jobs) {
                if (!dtos.containsKey(job.getGroup()))
                    dtos.put(job.getGroup(), new ArrayList<JobDTO>());
                if(!scheduler.getTriggersOfJob(job).isEmpty()) {
                    CronTrigger trigger = ((CronTrigger) scheduler.getTriggersOfJob(job).get(0));
                    dtos.get(job.getGroup()).add(new JobDTO(job.getName(),
                            trigger.getCronExpression(),
                            trigger.getPreviousFireTime()!= null ? trigger.getPreviousFireTime().getTime() : 0,
                            trigger.getNextFireTime().getTime(),
                            ""));
                }
            }
            return mapper.writeValueAsString(dtos);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public String getJobs(String groupName) throws SchedulerException {
        GroupMatcher<JobKey> matcher = groupName == null || groupName.isEmpty() ? GroupMatcher.anyGroup() : GroupMatcher.groupEquals(groupName);
        Set<JobKey> jobs = scheduler.getJobKeys(matcher);
        return jobsToJson(jobs);
    }

    public String getRunningJobs(String groupName) throws SchedulerException {
        Stream<JobKey> jobs = scheduler.getCurrentlyExecutingJobs().stream()
                .map(context -> context.getJobDetail().getKey());
        if (groupName != null && !groupName.isEmpty())
                jobs = jobs.filter(key -> key.getGroup().equals(groupName));
        return jobsToJson(jobs.collect(Collectors.toList()));
    }

    public String executeJob(String groupName, String jobName,
                             Map<String, String[]> params) throws SchedulerException {
        GroupMatcher<JobKey> matcher = groupName == null || groupName.isEmpty() ? GroupMatcher.anyGroup() : GroupMatcher.groupEquals(groupName);
        log.debug("Params: "+deepToString(params));
        JobKey job = scheduler.getJobKeys(matcher).stream()
                .filter(key -> key.getName().equals(jobName)).findFirst().orElseGet(null);
        JobDetail jobDetail = scheduler.getJobDetail(job);
        JobDataMap jdm = jobDetail.getJobDataMap();

        if (jobDetail.getJobClass() == ShellExecuteJob.class && jdm.containsKey("allowedEnvs")) {
            List<String> allowedParams = Arrays.asList(((String)jobDetail.getJobDataMap().get("allowedEnvs")).split(","));
            String env = params.entrySet().stream()
                    .filter(entry -> allowedParams.contains(entry.getKey()))
                    .map(entry-> entry.getKey() + "=" + entry.getValue()[0])
                    .collect(Collectors.joining(","));
            jobDetail.getJobDataMap().put("params", env);
            log.debug("Env: "+deepToString(env) + " stored: "+ jobDetail.getJobDataMap().get("params"));
            scheduler.addJob(jobDetail, true);
        }


        scheduler.triggerJob(job);

        return getRunningJobs(groupName);
    }

    public String stopJob(String groupName, String jobName) throws SchedulerException {
        JobKey job = scheduler.getCurrentlyExecutingJobs().stream()
                .map(context -> context.getJobDetail().getKey())
                .filter(key -> key.getGroup().equals(groupName))
                .findFirst().orElseGet(null);

        scheduler.interrupt(job);
        return getRunningJobs(groupName);
    }

}
