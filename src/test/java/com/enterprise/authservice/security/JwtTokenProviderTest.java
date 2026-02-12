package com.enterprise.authservice.security;

import com.enterprise.authservice.config.ApplicationConfig;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class JwtTokenProviderTest {

    @Mock
    private ApplicationConfig applicationConfig;

    @Mock
    private ApplicationConfig.Jwt jwtConfig;

    private JwtTokenProvider tokenProvider;
    private UserPrincipal userPrincipal;

    @BeforeEach
    void setUp() {
        when(applicationConfig.getJwt()).thenReturn(jwtConfig);
        when(jwtConfig.getSecret()).thenReturn("test-secret-key-for-jwt-token-generation-must-be-256-bits");
        when(jwtConfig.getExpiration()).thenReturn(3600000L);
        when(jwtConfig.getRefreshExpiration()).thenReturn(86400000L);

        tokenProvider = new JwtTokenProvider(applicationConfig);

        userPrincipal = new UserPrincipal(
            UUID.randomUUID(),
            "testuser",
            "test@example.com",
            "password",
            List.of(new SimpleGrantedAuthority("ROLE_USER")),
            true,
            true,
            true,
            true
        );
    }

    @Test
    void generateAccessToken_Success() {
        String token = tokenProvider.generateAccessToken(userPrincipal);

        assertNotNull(token);
        assertFalse(token.isEmpty());
        assertTrue(token.split("\\.").length == 3);
    }

    @Test
    void generateRefreshToken_Success() {
        String token = tokenProvider.generateRefreshToken(userPrincipal);

        assertNotNull(token);
        assertFalse(token.isEmpty());
    }

    @Test
    void validateToken_ValidToken() {
        String token = tokenProvider.generateAccessToken(userPrincipal);

        assertTrue(tokenProvider.validateToken(token));
    }

    @Test
    void validateToken_InvalidToken() {
        assertFalse(tokenProvider.validateToken("invalid.token.here"));
    }

    @Test
    void getUsernameFromToken_Success() {
        String token = tokenProvider.generateAccessToken(userPrincipal);
        String username = tokenProvider.getUsernameFromToken(token);

        assertEquals("testuser", username);
    }

    @Test
    void getExpirationDateFromToken_Success() {
        String token = tokenProvider.generateAccessToken(userPrincipal);
        var expirationDate = tokenProvider.getExpirationDateFromToken(token);

        assertNotNull(expirationDate);
        assertTrue(expirationDate.after(new java.util.Date()));
    }
}
