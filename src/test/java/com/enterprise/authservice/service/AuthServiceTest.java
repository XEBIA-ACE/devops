package com.enterprise.authservice.service;

import com.enterprise.authservice.domain.dto.request.LoginRequest;
import com.enterprise.authservice.domain.dto.request.RegisterRequest;
import com.enterprise.authservice.domain.dto.response.AuthResponse;
import com.enterprise.authservice.domain.entity.Role;
import com.enterprise.authservice.domain.entity.User;
import com.enterprise.authservice.exception.AuthenticationException;
import com.enterprise.authservice.exception.ValidationException;
import com.enterprise.authservice.repository.RefreshTokenRepository;
import com.enterprise.authservice.repository.RoleRepository;
import com.enterprise.authservice.repository.UserRepository;
import com.enterprise.authservice.security.JwtTokenProvider;
import com.enterprise.authservice.security.UserPrincipal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.HashSet;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private RoleRepository roleRepository;

    @Mock
    private RefreshTokenRepository refreshTokenRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private JwtTokenProvider tokenProvider;

    @Mock
    private AuthenticationManager authenticationManager;

    @Mock
    private AuditService auditService;

    @InjectMocks
    private AuthService authService;

    private RegisterRequest registerRequest;
    private LoginRequest loginRequest;
    private User testUser;
    private Role userRole;

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

        userRole = Role.builder()
            .id(UUID.randomUUID())
            .name("USER")
            .permissions(new HashSet<>())
            .build();

        testUser = User.builder()
            .id(UUID.randomUUID())
            .username("testuser")
            .email("test@example.com")
            .password("encodedPassword")
            .enabled(true)
            .accountNonExpired(true)
            .accountNonLocked(true)
            .credentialsNonExpired(true)
            .roles(new HashSet<>())
            .build();
    }

    @Test
    void register_Success() {
        when(userRepository.existsByUsername(anyString())).thenReturn(false);
        when(userRepository.existsByEmail(anyString())).thenReturn(false);
        when(roleRepository.findByName("USER")).thenReturn(Optional.of(userRole));
        when(passwordEncoder.encode(anyString())).thenReturn("encodedPassword");
        when(userRepository.save(any(User.class))).thenReturn(testUser);
        when(tokenProvider.generateAccessToken(any(UserPrincipal.class))).thenReturn("accessToken");
        when(tokenProvider.generateRefreshToken(any(UserPrincipal.class))).thenReturn("refreshToken");

        AuthResponse response = authService.register(registerRequest);

        assertNotNull(response);
        assertEquals("accessToken", response.getAccessToken());
        assertEquals("refreshToken", response.getRefreshToken());
        assertEquals("Bearer", response.getTokenType());
        verify(userRepository).save(any(User.class));
        verify(auditService).logAction(any(UUID.class), eq("USER_REGISTERED"), eq("User"), eq(true), isNull());
    }

    @Test
    void register_UsernameTaken() {
        when(userRepository.existsByUsername(anyString())).thenReturn(true);

        assertThrows(ValidationException.class, () -> authService.register(registerRequest));
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void register_EmailTaken() {
        when(userRepository.existsByUsername(anyString())).thenReturn(false);
        when(userRepository.existsByEmail(anyString())).thenReturn(true);

        assertThrows(ValidationException.class, () -> authService.register(registerRequest));
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    void login_Success() {
        Authentication authentication = mock(Authentication.class);
        UserPrincipal userPrincipal = UserPrincipal.create(testUser);

        when(authenticationManager.authenticate(any(UsernamePasswordAuthenticationToken.class)))
            .thenReturn(authentication);
        when(authentication.getPrincipal()).thenReturn(userPrincipal);
        when(userRepository.findById(any(UUID.class))).thenReturn(Optional.of(testUser));
        when(tokenProvider.generateAccessToken(any(UserPrincipal.class))).thenReturn("accessToken");
        when(tokenProvider.generateRefreshToken(any(UserPrincipal.class))).thenReturn("refreshToken");

        AuthResponse response = authService.login(loginRequest);

        assertNotNull(response);
        assertEquals("accessToken", response.getAccessToken());
        verify(userRepository).save(any(User.class));
        verify(auditService).logAction(any(UUID.class), eq("USER_LOGIN"), eq("User"), eq(true), isNull());
    }

    @Test
    void login_InvalidCredentials() {
        when(authenticationManager.authenticate(any(UsernamePasswordAuthenticationToken.class)))
            .thenThrow(new BadCredentialsException("Invalid credentials"));
        when(userRepository.findByUsernameOrEmail(anyString(), anyString()))
            .thenReturn(Optional.of(testUser));

        assertThrows(AuthenticationException.class, () -> authService.login(loginRequest));
        verify(auditService).logAction(isNull(), eq("USER_LOGIN_FAILED"), eq("User"), eq(false), anyString());
    }

    @Test
    void logout_Success() {
        when(userRepository.findByUsername(anyString())).thenReturn(Optional.of(testUser));

        authService.logout("testuser");

        verify(refreshTokenRepository).deleteByUser(testUser);
        verify(auditService).logAction(any(UUID.class), eq("USER_LOGOUT"), eq("User"), eq(true), isNull());
    }
}
