# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-02-05

### Added
- Initial Android kernel CI/CD system
- GitHub Actions workflow for kernel building
- Proton Clang toolchain integration
- AnyKernel ZIP packaging
- Telegram notifications support
- NetHunter kernel configuration support (basic and full levels)
- Comprehensive test suite for NetHunter configurations

### Features
- Automated kernel building with retry mechanism
- Polly flag patching for compatibility
- GKI (Generic Kernel Image) detection
- Custom Kconfig branding options
- Multi-level NetHunter configuration (basic/full)

### Security
- Input validation on all user-provided parameters
- Path traversal prevention
- Command injection protection
- Secure temporary file handling

### Documentation
- README.md with comprehensive usage guide
- AGENTS.md for AI coding agents
- NetHunter-specific documentation

## [0.9.0] - 2026-02-04

### Added
- Initial project structure
- Basic CI scripts

[Unreleased]: https://github.com/evrahimkhan/Android-CI-builder/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/evrahimkhan/Android-CI-builder/releases/tag/v1.0.0
[0.9.0]: https://github.com/evrahimkhan/Android-CI-builder/releases/tag/v0.9.0
