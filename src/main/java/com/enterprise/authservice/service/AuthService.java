package com.enterprise.authservice.service;

import com.enterprise.authservice.domain.dto.request.LoginRequest;
import com.enterprise.authservice.domain.dto.request.RefreshTokenRequest;
import com.enterprise.authservice.domain.dto.request.RegisterRequest;
import com.enterprise.authservice.domain.dto.response.AuthResponse;
import com.enterprise.authservice.domain.entity.RefreshToken;
import com.enterprise.authservice.domain.entity.Role;
import com.enterprise.authservice.domain.entity.User;
import com.enterprise.authservice.exception.AuthenticationException;
import com.enterprise.authservice.exception.ResourceNotFoundException;
import com.enterprise.authservice.exception.ValidationException;
import com.enterprise.authservice.repository.RefreshTokenRepository;
import com.enterprise.authservice.repository.RoleRepository;
import com.enterprise.authservice.repository.UserRepository;
import com.enterprise.authservice.security.JwtTokenProvider;
import com.enterprise.authservice.security.UserPrincipal;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.Set;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class AuthService {

    private final UserRepository userRepository;
    private final RoleRepository roleRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final AuthenticationManager authenticationManager;
    private final AuditService auditService;

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        log.info("Registering new user: {}", request.getUsername());

        if (userRepository.existsByUsername(request.getUsername())) {
            throw new ValidationException("Username is already taken");
        }

        if (userRepository.existsByEmail(request.getEmail())) {
            throw new ValidationException("Email is already in use");
        }

        User user = User.builder()
            .username(request.getUsername())
            .email(request.getEmail())
            .password(passwordEncoder.encode(request.getPassword()))
            .firstName(request.getFirstName())
            .lastName(request.getLastName())
            .phoneNumber(request.getPhoneNumber())
            .enabled(true)
            .emailVerified(false)
            .accountNonExpired(true)
            .accountNonLocked(true)
            .credentialsNonExpired(true)
            .failedLoginAttempts(0)
            .passwordChangedAt(LocalDateTime.now())
            .build();

        Role userRole = roleRepository.findByName("USER")
            .orElseThrow(() -> new ResourceNotFoundException("Default role not found"));
        user.addRole(userRole);

        user = userRepository.save(user);
        auditService.logAction(user.getId(), "USER_REGISTERED", "User", true, null);

        UserPrincipal userPrincipal = UserPrincipal.create(user);
        String accessToken = tokenProvider.generateAccessToken(userPrincipal);
        String refreshToken = createRefreshToken(user, userPrincipal);

        return buildAuthResponse(accessToken, refreshToken, userPrincipal);
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {
        log.info("User login attempt: {}", request.getUsernameOrEmail());

        try {
            Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                    request.getUsernameOrEmail(),
                    request.getPassword()
                )
            );

            UserPrincipal userPrincipal = (UserPrincipal) authentication.getPrincipal();
            User user = userRepository.findById(userPrincipal.getId())
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

            user.setLastLoginAt(LocalDateTime.now());
            user.setFailedLoginAttempts(0);
            userRepository.save(user);

            String accessToken = tokenProvider.generateAccessToken(userPrincipal);
            String refreshToken = createRefreshToken(user, userPrincipal);

            auditService.logAction(user.getId(), "USER_LOGIN", "User", true, null);

            return buildAuthResponse(accessToken, refreshToken, userPrincipal);
        } catch (BadCredentialsException ex) {
            handleFailedLogin(request.getUsernameOrEmail());
            auditService.logAction(null, "USER_LOGIN_FAILED", "User", false, "Invalid credentials");
            throw new AuthenticationException("Invalid username or password");
        }
    }

    @Transactional
    public AuthResponse refreshAccessToken(RefreshTokenRequest request) {
        log.info("Refreshing access token");

        RefreshToken refreshToken = refreshTokenRepository.findByToken(request.getRefreshToken())
            .orElseThrow(() -> new AuthenticationException("Invalid refresh token"));

        if (!refreshToken.isValid()) {
            refreshTokenRepository.delete(refreshToken);
            throw new AuthenticationException("Refresh token is expired or revoked");
        }

        User user = refreshToken.getUser();
        UserPrincipal userPrincipal = UserPrincipal.create(user);

        String newAccessToken = tokenProvider.generateAccessToken(userPrincipal);
        String newRefreshToken = createRefreshToken(user, userPrincipal);

        refreshTokenRepository.delete(refreshToken);

        return buildAuthResponse(newAccessToken, newRefreshToken, userPrincipal);
    }

    @Transactional
    public void logout(String username) {
        log.info("User logout: {}", username);

        User user = userRepository.findByUsername(username)
            .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        refreshTokenRepository.deleteByUser(user);
        auditService.logAction(user.getId(), "USER_LOGOUT", "User", true, null);
    }

    private String createRefreshToken(User user, UserPrincipal userPrincipal) {
        String tokenString = tokenProvider.generateRefreshToken(userPrincipal);

        RefreshToken refreshToken = RefreshToken.builder()
            .token(tokenString)
            .user(user)
            .expiresAt(tokenProvider.getExpirationDateFromToken(tokenString)
                .toInstant()
                .atZone(java.time.ZoneId.systemDefault())
                .toLocalDateTime())
            .revoked(false)
            .build();

        refreshTokenRepository.save(refreshToken);
        return tokenString;
    }

    private void handleFailedLogin(String usernameOrEmail) {
        userRepository.findByUsernameOrEmail(usernameOrEmail, usernameOrEmail)
            .ifPresent(user -> {
                user.setFailedLoginAttempts(user.getFailedLoginAttempts() + 1);
                if (user.getFailedLoginAttempts() >= 5) {
                    user.setAccountNonLocked(false);
                    log.warn("Account locked due to failed login attempts: {}", user.getUsername());
                }
                userRepository.save(user);
            });
    }

    private AuthResponse buildAuthResponse(String accessToken, String refreshToken, UserPrincipal userPrincipal) {
        Set<String> roles = userPrincipal.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority)
            .filter(auth -> auth.startsWith("ROLE_"))
            .map(auth -> auth.substring(5))
            .collect(Collectors.toSet());

        Set<String> permissions = userPrincipal.getAuthorities().stream()
            .map(GrantedAuthority::getAuthority)
            .filter(auth -> !auth.startsWith("ROLE_"))
            .collect(Collectors.toSet());

        AuthResponse.UserInfo userInfo = AuthResponse.UserInfo.builder()
            .id(userPrincipal.getId().toString())
            .username(userPrincipal.getUsername())
            .email(userPrincipal.getEmail())
            .roles(roles)
            .permissions(permissions)
            .build();

        return AuthResponse.builder()
            .accessToken(accessToken)
            .refreshToken(refreshToken)
            .tokenType("Bearer")
            .expiresIn(3600L)
            .user(userInfo)
            .build();
    }
}
