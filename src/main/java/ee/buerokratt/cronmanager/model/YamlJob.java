package ee.buerokratt.cronmanager.model;

import lombok.Data;
import org.quartz.Job;
import org.quartz.JobDataMap;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

@Data
public abstract class YamlJob implements Job {

    private String name;
    private String trigger;

    public YamlJob() {
    }

    public abstract String getType();

    public String getTriggerName() {
        return getName() + "_trigger";
    }

    public void execute(JobExecutionContext context) throws JobExecutionException {
        name = context.getJobDetail().getJobDataMap().getString("name");
        trigger = context.getJobDetail().getJobDataMap().getString("trigger");
    }

    public JobDataMap getJobData() {
        JobDataMap map = new JobDataMap();
        map.put("name", name);
        map.put("trigger", trigger);
        return map;
    }
}
