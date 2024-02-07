package ee.buerokratt.cronmanager.utils;

import lombok.NoArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@NoArgsConstructor
public class LoggingUtils {

    public static <T> String mapDeepToString(Map<String, T> map) {
        return map == null ? "" : map.entrySet().stream()
                .map(e ->"{ " + e.getKey() + " => " + (e.getValue() instanceof Map ? mapDeepToString((Map)e.getValue()) : e.getValue().toString()) + " }")
                .collect(Collectors.joining(","));
    }

    public static <T> String listToString(List<T> list) {
        return list.stream().map(item -> item.toString()).collect(Collectors.joining(";"));
    }
}
