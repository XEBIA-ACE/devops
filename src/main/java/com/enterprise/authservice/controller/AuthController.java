package com.enterprise.authservice.controller;

import com.enterprise.authservice.domain.dto.request.LoginRequest;
import com.enterprise.authservice.domain.dto.request.RefreshTokenRequest;
import com.enterprise.authservice.domain.dto.request.RegisterRequest;
import com.enterprise.authservice.domain.dto.response.AuthResponse;
import com.enterprise.authservice.service.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
@Tag(name = "Authentication", description = "Authentication and authorization endpoints")
public class AuthController {

    private final AuthService authService;

    @PostMapping("/register")
    @Operation(summary = "Register a new user", description = "Creates a new user account with the provided details")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterRequest request) {
        AuthResponse response = authService.register(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @PostMapping("/login")
    @Operation(summary = "User login", description = "Authenticates user and returns access and refresh tokens")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        AuthResponse response = authService.login(request);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/refresh")
    @Operation(summary = "Refresh access token", description = "Generates a new access token using a valid refresh token")
    public ResponseEntity<AuthResponse> refreshToken(@Valid @RequestBody RefreshTokenRequest request) {
        AuthResponse response = authService.refreshAccessToken(request);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/logout")
    @Operation(summary = "User logout", description = "Invalidates all refresh tokens for the authenticated user")
    public ResponseEntity<Map<String, String>> logout(Authentication authentication) {
        authService.logout(authentication.getName());
        return ResponseEntity.ok(Map.of("message", "Logout successful"));
    }

    @GetMapping("/me")
    @Operation(summary = "Get current user", description = "Returns the authenticated user's information")
    public ResponseEntity<Map<String, Object>> getCurrentUser(Authentication authentication) {
        return ResponseEntity.ok(Map.of(
            "username", authentication.getName(),
            "authorities", authentication.getAuthorities()
        ));
    }
}
