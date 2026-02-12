# Contributing to Authentication Service

Thank you for your interest in contributing to the Authentication Service! This document provides guidelines and instructions for contributing.

## Code of Conduct

Please be respectful and constructive in all interactions.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/auth-service.git`
3. Create a branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes
6. Commit and push
7. Create a Pull Request

## Development Setup

See the README.md for detailed setup instructions.

## Coding Standards

### Java Code Style

- Follow standard Java naming conventions
- Use meaningful variable and method names
- Keep methods small and focused
- Write self-documenting code
- Add comments for complex logic only

### Code Formatting

- Use 4 spaces for indentation (no tabs)
- Maximum line length: 120 characters
- Use the provided IDE formatter configuration

### Best Practices

- Follow SOLID principles
- Write unit tests for new features
- Maintain test coverage above 80%
- Handle exceptions appropriately
- Use dependency injection
- Avoid code duplication

## Testing

- Write unit tests for all new code
- Write integration tests for API endpoints
- Ensure all tests pass before submitting PR
- Run `mvn test` to execute tests

## Commit Messages

Use conventional commit format:

```
type(scope): subject

body

footer
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Build/tooling changes

Example:
```
feat(auth): add password reset functionality

Implements password reset via email token.
Includes validation and expiration handling.

Closes #123
```

## Pull Request Process

1. Update documentation for any changed functionality
2. Add tests for new features
3. Ensure all tests pass
4. Update the CHANGELOG.md
5. Request review from maintainers
6. Address review feedback
7. Squash commits if requested

## Pull Request Checklist

- [ ] Code follows project style guidelines
- [ ] Tests added/updated and passing
- [ ] Documentation updated
- [ ] No merge conflicts
- [ ] Commits are well-formatted
- [ ] PR description explains the changes

## Areas for Contribution

- Bug fixes
- Feature enhancements
- Documentation improvements
- Test coverage improvements
- Performance optimizations
- Security enhancements

## Questions?

Open an issue for questions or clarifications.
