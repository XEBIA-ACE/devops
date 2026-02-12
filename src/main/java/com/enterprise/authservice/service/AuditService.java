package com.enterprise.authservice.service;

import com.enterprise.authservice.domain.entity.AuditLog;
import com.enterprise.authservice.repository.AuditLogRepository;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class AuditService {

    private final AuditLogRepository auditLogRepository;

    @Async
    public void logAction(UUID userId, String action, String resource, boolean success, String errorMessage) {
        try {
            HttpServletRequest request = getCurrentRequest();

            AuditLog auditLog = AuditLog.builder()
                .userId(userId)
                .action(action)
                .resource(resource)
                .ipAddress(getClientIpAddress(request))
                .userAgent(request != null ? request.getHeader("User-Agent") : null)
                .success(success)
                .errorMessage(errorMessage)
                .build();

            auditLogRepository.save(auditLog);
            log.debug("Audit log created: {} - {} - {}", action, resource, success);
        } catch (Exception ex) {
            log.error("Failed to create audit log", ex);
        }
    }

    private HttpServletRequest getCurrentRequest() {
        try {
            ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            return attributes != null ? attributes.getRequest() : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private String getClientIpAddress(HttpServletRequest request) {
        if (request == null) {
            return null;
        }

        String xForwardedFor = request.getHeader("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isEmpty()) {
            return xForwardedFor.split(",")[0].trim();
        }

        String xRealIp = request.getHeader("X-Real-IP");
        if (xRealIp != null && !xRealIp.isEmpty()) {
            return xRealIp;
        }

        return request.getRemoteAddr();
    }
}
