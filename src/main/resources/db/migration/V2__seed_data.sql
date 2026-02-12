-- Insert default roles
INSERT INTO roles (id, name, description, created_at) VALUES
    (gen_random_uuid(), 'USER', 'Default user role', NOW()),
    (gen_random_uuid(), 'ADMIN', 'Administrator role', NOW()),
    (gen_random_uuid(), 'MODERATOR', 'Moderator role', NOW());

-- Insert default permissions
INSERT INTO permissions (id, name, description, resource, action, created_at) VALUES
    (gen_random_uuid(), 'user:read', 'Read user information', 'user', 'read', NOW()),
    (gen_random_uuid(), 'user:write', 'Create or update user information', 'user', 'write', NOW()),
    (gen_random_uuid(), 'user:delete', 'Delete user', 'user', 'delete', NOW()),
    (gen_random_uuid(), 'role:read', 'Read role information', 'role', 'read', NOW()),
    (gen_random_uuid(), 'role:write', 'Create or update role', 'role', 'write', NOW()),
    (gen_random_uuid(), 'role:delete', 'Delete role', 'role', 'delete', NOW()),
    (gen_random_uuid(), 'audit:read', 'Read audit logs', 'audit', 'read', NOW());

-- Assign permissions to ADMIN role
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'ADMIN';

-- Assign limited permissions to USER role
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'USER' AND p.name = 'user:read';

-- Assign moderate permissions to MODERATOR role
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'MODERATOR' AND p.name IN ('user:read', 'user:write', 'audit:read');

-- Create default admin user (password: Admin123!)
-- Note: This is a bcrypt hash of "Admin123!" - change this in production
INSERT INTO users (id, username, email, password, first_name, last_name, enabled, email_verified, account_non_expired, account_non_locked, credentials_non_expired, failed_login_attempts, password_changed_at, created_at)
VALUES (gen_random_uuid(), 'admin', 'admin@example.com', '$2a$10$XPL3qv8xE8E0wXvZkqCJBeJ0EqUFu5tWqcL1RHgZmJNdVGJR5JXOW', 'Admin', 'User', TRUE, TRUE, TRUE, TRUE, TRUE, 0, NOW(), NOW());

-- Assign ADMIN role to admin user
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u
CROSS JOIN roles r
WHERE u.username = 'admin' AND r.name = 'ADMIN';
