package com.example;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

/**
 * Main application class for the Python Maven Application.
 * This is a sample Spring Boot application demonstrating CI/CD pipeline integration.
 */
@SpringBootApplication
@RestController
public class Application {

    /**
     * Main entry point for the application.
     *
     * @param args Command line arguments
     */
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    /**
     * Root endpoint returning application information.
     *
     * @return Map containing application details
     */
    @GetMapping("/")
    public Map<String, String> home() {
        Map<String, String> response = new HashMap<>();
        response.put("application", "Python Maven Application");
        response.put("version", "1.0.0");
        response.put("status", "running");
        response.put("message", "CI/CD Pipeline Demo Application");
        return response;
    }

    /**
     * API endpoint for testing.
     *
     * @return Map containing API response
     */
    @GetMapping("/api/status")
    public Map<String, Object> apiStatus() {
        Map<String, Object> response = new HashMap<>();
        response.put("api", "operational");
        response.put("timestamp", System.currentTimeMillis());
        response.put("uptime", getUptime());
        return response;
    }

    /**
     * Calculate application uptime.
     *
     * @return Uptime in milliseconds
     */
    private long getUptime() {
        return System.currentTimeMillis() - startTime;
    }

    private static final long startTime = System.currentTimeMillis();
}
