package com.enterprise.authservice.domain.dto.response;

import com.fasterxml.jackson.annotation.JsonInclude;
import io.swagger.v3.oas.annotations.media.Schema;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
@JsonInclude(JsonInclude.Include.NON_NULL)
@Schema(description = "Error response")
public class ErrorResponse {

    @Schema(description = "HTTP status code", example = "400")
    private Integer status;

    @Schema(description = "Error message", example = "Invalid request")
    private String message;

    @Schema(description = "Error code", example = "INVALID_REQUEST")
    private String error;

    @Schema(description = "Request path", example = "/api/v1/auth/login")
    private String path;

    @Schema(description = "Timestamp", example = "2024-01-15T10:30:00")
    @Builder.Default
    private LocalDateTime timestamp = LocalDateTime.now();

    @Schema(description = "Validation errors")
    private Map<String, List<String>> errors;

    @Schema(description = "Additional details")
    private String details;
}
