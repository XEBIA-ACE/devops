package com.enterprise.authservice.domain.dto.request;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@Schema(description = "Login request with username/email and password")
public class LoginRequest {

    @NotBlank(message = "Username or email is required")
    @Schema(description = "Username or email", example = "user@example.com")
    private String usernameOrEmail;

    @NotBlank(message = "Password is required")
    @Schema(description = "User password", example = "SecurePassword123!")
    private String password;
}
