package ee.buerokratt.cronmanager.utils;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class LoggingUtilsTest {

    @Test
    void listToStringJoinsItemsWithSemicolon() {
        assertEquals("a;b;c", LoggingUtils.listToString(List.of("a", "b", "c")));
    }

    @Test
    void listToStringOfEmptyListIsEmptyString() {
        assertEquals("", LoggingUtils.listToString(List.of()));
    }

    @Test
    void listToStringUsesToStringOfItems() {
        assertEquals("1;2", LoggingUtils.listToString(List.of(1, 2)));
    }

    @Test
    void mapDeepToStringOfNullIsEmptyString() {
        assertEquals("", LoggingUtils.mapDeepToString(null));
    }

    @Test
    void mapDeepToStringFormatsFlatMap() {
        Map<String, String> map = new LinkedHashMap<>();
        map.put("key1", "value1");
        map.put("key2", "value2");

        assertEquals("{ key1 => value1 },{ key2 => value2 }", LoggingUtils.mapDeepToString(map));
    }

    @Test
    void mapDeepToStringRecursesIntoNestedMaps() {
        Map<String, Object> inner = new LinkedHashMap<>();
        inner.put("innerKey", "innerValue");

        Map<String, Object> outer = new LinkedHashMap<>();
        outer.put("outerKey", inner);

        assertEquals("{ outerKey => { innerKey => innerValue } }", LoggingUtils.mapDeepToString(outer));
    }
}
