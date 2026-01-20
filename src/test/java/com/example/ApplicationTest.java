package com.example;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Integration tests for the Application class.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ApplicationTest {

    @LocalServerPort
    private int port;

    @Autowired
    private TestRestTemplate restTemplate;

    /**
     * Test that the application context loads successfully.
     */
    @Test
    void contextLoads() {
        assertNotNull(restTemplate);
    }

    /**
     * Test the home endpoint returns expected response.
     */
    @Test
    void homeEndpointReturnsApplicationInfo() {
        String url = "http://localhost:" + port + "/";
        ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("Python Maven Application", response.getBody().get("application"));
        assertEquals("running", response.getBody().get("status"));
    }

    /**
     * Test the API status endpoint returns operational status.
     */
    @Test
    void apiStatusEndpointReturnsOperationalStatus() {
        String url = "http://localhost:" + port + "/api/status";
        ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("operational", response.getBody().get("api"));
        assertTrue(response.getBody().containsKey("timestamp"));
        assertTrue(response.getBody().containsKey("uptime"));
    }

    /**
     * Test the actuator health endpoint is available.
     */
    @Test
    void actuatorHealthEndpointIsAvailable() {
        String url = "http://localhost:" + port + "/actuator/health";
        ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);

        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        assertEquals("UP", response.getBody().get("status"));
    }
}
