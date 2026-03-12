# Security Policy

## Supported scope

Security reports are welcome for:

- exposed API keys or credentials
- authentication or authorization issues
- insecure data handling
- sensitive data leaks in logs, builds, or screenshots
- client behavior that can compromise backend integrity

## Reporting a vulnerability

Do not open a public GitHub issue for security problems.

Instead:

1. Contact the maintainers privately.
2. Include the affected area, reproduction steps, and impact.
3. If credentials may have been exposed, rotate them immediately and mention what was rotated.

## Secrets policy

- Never commit live credentials to the repository.
- Keep committed configuration files on placeholder values only.
- Use local scheme environment variables or local-only overrides for sensitive values.

## Disclosure

We will validate reports, assess impact, and coordinate a fix before any public disclosure when possible.

