package ee.buerokratt.cronmanager.model;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.quartz.JobDataMap;
import org.quartz.JobExecutionContext;
import org.quartz.JobExecutionException;

import java.io.*;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import static ee.buerokratt.cronmanager.utils.LoggingUtils.mapDeepToString;
import static org.apache.logging.log4j.message.ParameterizedMessage.deepToString;

@org.quartz.DisallowConcurrentExecution
@Slf4j
@Getter
@Setter
@RequiredArgsConstructor
public class ShellExecuteJob extends YamlJob {

    private String command;

    private List<String> allowedEnvs;

    @Override
    public String getType() {
        return "exec";
    }

    @Override
    public void execute(JobExecutionContext context) throws JobExecutionException {
        super.execute(context);

        String parentResult = (String) context.getResult();
        if (!parentResult.isEmpty()) {
            throw new JobExecutionException("Stopped execution: current time outside defined limits: %d [ %d -> %d ]".formatted(System.currentTimeMillis(), getStartDate(),  getEndDate()));
        }

        JobDataMap jdm = context.getMergedJobDataMap();
        command = jdm.getString("command");

        try {
            ProcessBuilder builder = new ProcessBuilder(command.trim().split("\\s+"));
            builder.directory(new File("/app/"));
            Object overrides = jdm.get("requestEnvironment");
            if (overrides instanceof java.util.Map<?, ?> values) {
                for (var entry : values.entrySet()) {
                    String key = (String) entry.getKey();
                    String value = (String) entry.getValue();
                    if (!key.matches("[A-Za-z_][A-Za-z0-9_]*") || value.indexOf('\0') >= 0 || value.length() > 65536) throw new IOException("Invalid job environment");
                    builder.environment().put(key, value);
                }
            }
            builder.redirectErrorStream(true);
            builder.redirectOutput(ProcessBuilder.Redirect.DISCARD);
            Process process = builder.start();
            if (!process.waitFor(90, java.util.concurrent.TimeUnit.SECONDS)) {
                process.destroyForcibly();
                throw new IOException("Job timeout; inspect retained task journal");
            }
            if (process.exitValue() != 0) throw new IOException("Job process returned nonzero status");
            context.setResult("completed");
            log.info("Job completed: {}", context.getJobDetail().getKey());
        } catch (IOException e) {
            throw new JobExecutionException("Job process failed", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new JobExecutionException("Job interrupted", e);
        }
    }

    @Override
    public JobDataMap getJobData() {
        JobDataMap map = super.getJobData();
        map.put("command", command);
        if (allowedEnvs != null)
            map.put("allowedEnvs", String.join(",", allowedEnvs));
        return map;
    }

    @Override
    public String toString() {
        return String.format("%s (%s) => \"%s\" [%d -> %d]",
                getName(),
                getTrigger(),
                getCommand(),
                getStartDate(),
                getEndDate());
    }
}
