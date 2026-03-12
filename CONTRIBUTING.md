# Contributing

## Scope

This repository contains the public codebase for the BeLocal iOS app. Contributions should improve product quality, reliability, maintainability, or documentation.

## Before you start

- Open an issue for substantial product or architectural changes before writing code.
- Keep pull requests focused. Avoid bundling UI work, infrastructure changes, and cleanup in the same PR.
- Never commit credentials, tokens, or filled production config files.

## Local development

1. Install the required Xcode version and open the project.
2. Configure local API credentials using the placeholder plist files or scheme environment variables.
3. Run the app locally before opening a PR.

## Code expectations

- Follow existing SwiftUI, SwiftData, and service-layer patterns already used in the app.
- Prefer small, testable changes with clear naming.
- Preserve accessibility, localization, and offline behavior when touching product flows.
- Document new configuration, dependencies, or operational constraints.

## Pull request checklist

- The change has a clear purpose.
- UI changes include screenshots or short screen recordings when relevant.
- Setup or configuration changes are reflected in the documentation.
- Sensitive data is not included in code, plist files, logs, or screenshots.
- The branch is rebased or merged cleanly against the current default branch.

## Review criteria

Maintainers will prioritize:

- correctness
- product behavior and regressions
- security and secrets hygiene
- readability and maintainability
- documentation completeness

