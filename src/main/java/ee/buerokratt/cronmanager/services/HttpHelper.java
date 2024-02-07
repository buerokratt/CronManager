package ee.buerokratt.cronmanager.services;

import lombok.NoArgsConstructor;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Service
@NoArgsConstructor
public class HttpHelper {

    public static ResponseEntity<String> doRequest(String method, String url) {
        RestClient client = RestClient.create();

        return client.method(HttpMethod.valueOf(method))
                .uri(url)
                .retrieve()
                .toEntity(String.class);

    }
}
