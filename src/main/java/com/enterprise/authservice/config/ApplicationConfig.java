package com.enterprise.authservice.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@ConfigurationProperties(prefix = "app")
@Data
public class ApplicationConfig {

    private Jwt jwt = new Jwt();
    private Auth0 auth0 = new Auth0();
    private Keycloak keycloak = new Keycloak();
    private Cors cors = new Cors();
    private RateLimit rateLimit = new RateLimit();

    @Data
    public static class Jwt {
        private String secret;
        private Long expiration;
        private Long refreshExpiration;
    }

    @Data
    public static class Auth0 {
        private Boolean enabled = false;
        private String domain;
        private String clientId;
        private String clientSecret;
        private String audience;
    }

    @Data
    public static class Keycloak {
        private Boolean enabled = false;
        private String authServerUrl;
        private String realm;
        private String clientId;
        private String clientSecret;
    }

    @Data
    public static class Cors {
        private String allowedOrigins;
        private String allowedMethods;
        private String allowedHeaders;
    }

    @Data
    public static class RateLimit {
        private Boolean enabled = true;
        private Integer requestsPerMinute = 60;
    }
}
