package ee.buerokratt.cronmanager.services;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;

class HttpHelperTest {

    private HttpServer server;
    private String baseUrl;

    @BeforeEach
    void setUp() throws IOException {
        server = HttpServer.create(new InetSocketAddress("localhost", 0), 0);
        server.createContext("/echo", exchange -> {
            String responseBody = "method=" + exchange.getRequestMethod();
            byte[] bytes = responseBody.getBytes(StandardCharsets.UTF_8);
            exchange.sendResponseHeaders(200, bytes.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(bytes);
            }
        });
        server.start();
        baseUrl = "http://localhost:" + server.getAddress().getPort();
    }

    @AfterEach
    void tearDown() {
        server.stop(0);
    }

    @Test
    void doRequestReturnsBodyAndStatusForGet() {
        ResponseEntity<String> response = HttpHelper.doRequest("GET", baseUrl + "/echo");

        assertEquals(200, response.getStatusCode().value());
        assertEquals("method=GET", response.getBody());
    }

    @Test
    void doRequestReturnsBodyAndStatusForPost() {
        ResponseEntity<String> response = HttpHelper.doRequest("POST", baseUrl + "/echo");

        assertEquals(200, response.getStatusCode().value());
        assertEquals("method=POST", response.getBody());
    }
}
