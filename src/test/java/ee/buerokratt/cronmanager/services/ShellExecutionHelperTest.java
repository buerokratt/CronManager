package ee.buerokratt.cronmanager.services;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.file.Path;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;

// appRootPath is a static field only ever set once per JVM, so it's reset via reflection around each test.
class ShellExecutionHelperTest {

    @TempDir
    Path tempDir;

    @BeforeEach
    void resetStaticRootPathBefore() throws Exception {
        setAppRootPath(null);
    }

    @AfterEach
    void resetStaticRootPathAfter() throws Exception {
        setAppRootPath(null);
    }

    private static void setAppRootPath(String value) throws Exception {
        Field field = ShellExecutionHelper.class.getDeclaredField("appRootPath");
        field.setAccessible(true);
        field.set(null, value);
    }

    @Test
    void executeRunsCommandWithConfiguredEnvironmentAndRootPath() throws IOException {
        ShellExecutionHelper helper = new ShellExecutionHelper(List.of("PARAM1=value1"), tempDir.toString());

        List<String> output = helper.execute("echo hello");

        assertTrue(output.contains("hello"));
    }

    @Test
    void executeWithoutEnvironmentRunsCommandUsingConfiguredRootPath() throws IOException {
        new ShellExecutionHelper(List.of(), tempDir.toString());

        List<String> output = ShellExecutionHelper.executeWithoutEnvironment("echo hello");

        assertTrue(output.contains("hello"));
    }
}
