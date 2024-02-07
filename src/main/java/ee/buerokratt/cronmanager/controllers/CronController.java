package ee.buerokratt.cronmanager.controllers;

import ee.buerokratt.cronmanager.services.CronService;
import ee.buerokratt.cronmanager.services.JobReaderService;
import org.quartz.SchedulerException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
public class CronController {

    @Autowired
    JobReaderService jobReader;

    @Autowired
    CronService cron;

    @GetMapping("/")
    public String index() {
        return "BYK Cron started";
    }

    @GetMapping("/jobs/")
    public String jobs() {
        return jobs("");
    }

    @GetMapping("/jobs/{groupName}")
    public String jobs(@PathVariable(required = false) String groupName) {
        try {
            return cron.getJobs(groupName);
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }

    @GetMapping("/running/")
    public String runningJobs() {
        return runningJobs("");
    }

    @GetMapping("/running/{groupName}")
    public String runningJobs(@PathVariable(required = false) String groupName) {
        try {
            return cron.getRunningJobs(groupName);
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }

    @PostMapping("/execute/{groupName}/{jobName}")
    public String executeJob(@PathVariable String groupName, @PathVariable String jobName) {
        try {
            return cron.executeJob(groupName, jobName);
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }

    @PostMapping("/stop/{groupName}/{jobName}")
    public String stopJob(@PathVariable String groupName, @PathVariable String jobName) {
        try {
            return cron.stopJob(groupName, jobName);
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }


    @PostMapping("/reload/{groupName}")
    public String reloadJobs(@RequestParam(required = false) String groupName){
        jobReader.readServices();
        try {
            return cron.getJobs(groupName);
        } catch (SchedulerException e) {
            throw new RuntimeException(e);
        }
    }

}
