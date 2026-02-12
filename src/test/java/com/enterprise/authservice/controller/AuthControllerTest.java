package com.enterprise.authservice.controller;

import com.enterprise.authservice.domain.dto.request.LoginRequest;
import com.enterprise.authservice.domain.dto.request.RegisterRequest;
import com.enterprise.authservice.domain.dto.response.AuthResponse;
import com.enterprise.authservice.service.AuthService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Set;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private AuthService authService;

    private RegisterRequest registerRequest;
    private LoginRequest loginRequest;
    private AuthResponse authResponse;

    @BeforeEach
    void setUp() {
        registerRequest = RegisterRequest.builder()
            .username("testuser")
            .email("test@example.com")
            .password("Test123!")
            .firstName("Test")
            .lastName("User")
            .build();

        loginRequest = LoginRequest.builder()
            .usernameOrEmail("testuser")
            .password("Test123!")
            .build();

        AuthResponse.UserInfo userInfo = AuthResponse.UserInfo.builder()
            .id("123")
            .username("testuser")
            .email("test@example.com")
            .roles(Set.of("USER"))
            .permissions(Set.of())
            .build();

        authResponse = AuthResponse.builder()
            .accessToken("accessToken")
            .refreshToken("refreshToken")
            .tokenType("Bearer")
            .expiresIn(3600L)
            .user(userInfo)
            .build();
    }

    @Test
    void register_Success() throws Exception {
        when(authService.register(any(RegisterRequest.class))).thenReturn(authResponse);

        mockMvc.perform(post("/api/v1/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(registerRequest)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.accessToken").value("accessToken"))
            .andExpect(jsonPath("$.refreshToken").value("refreshToken"))
            .andExpect(jsonPath("$.user.username").value("testuser"));
    }

    @Test
    void register_InvalidRequest() throws Exception {
        RegisterRequest invalidRequest = RegisterRequest.builder()
            .username("ab")
            .email("invalid-email")
            .password("weak")
            .build();

        mockMvc.perform(post("/api/v1/auth/register")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(invalidRequest)))
            .andExpect(status().isBadRequest());
    }

    @Test
    void login_Success() throws Exception {
        when(authService.login(any(LoginRequest.class))).thenReturn(authResponse);

        mockMvc.perform(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(loginRequest)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.accessToken").value("accessToken"))
            .andExpect(jsonPath("$.user.username").value("testuser"));
    }

    @Test
    @WithMockUser(username = "testuser")
    void logout_Success() throws Exception {
        mockMvc.perform(post("/api/v1/auth/logout"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.message").value("Logout successful"));
    }

    @Test
    @WithMockUser(username = "testuser", roles = {"USER"})
    void getCurrentUser_Success() throws Exception {
        mockMvc.perform(get("/api/v1/auth/me"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.username").value("testuser"));
    }

    @Test
    void getCurrentUser_Unauthorized() throws Exception {
        mockMvc.perform(get("/api/v1/auth/me"))
            .andExpect(status().isUnauthorized());
    }
}
