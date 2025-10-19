# Contributing to Zarc

Thank you for your interest in contributing to Zarc! We appreciate your effort to make this project better.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Coding Standards](#coding-standards)
- [Submitting Changes](#submitting-changes)
- [Issue Guidelines](#issue-guidelines)
- [Community](#community)

## Code of Conduct

This project adheres to a Code of Conduct. By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

## Getting Started

### Prerequisites

- Zig 0.13.0 or later
- Git
- Basic knowledge of the Zig programming language

### Setting Up the Development Environment

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/zarc.git
   cd zarc
   ```
3. Add the upstream repository as a remote:
   ```bash
   git remote add upstream https://github.com/itsakeyfut/zarc.git
   ```
4. Build the project:
   ```bash
   zig build
   ```
5. Run tests to ensure everything is working:
   ```bash
   zig build test
   ```

## Development Workflow

### Creating a Branch

Always create a new branch for your work:

```bash
git checkout -b feature/your-feature-name
```

Branch naming conventions:
- `feature/` - New features
- `fix/` - Bug fixes
- `docs/` - Documentation updates
- `refactor/` - Code refactoring
- `test/` - Test additions or updates

### Making Changes

1. Make your changes in your feature branch
2. Write or update tests as necessary
3. Ensure all tests pass:
   ```bash
   zig build test
   ```
4. Build the project to check for compilation errors:
   ```bash
   zig build
   ```

### Committing Changes

Write clear, concise commit messages that describe what changed and why:

```bash
git commit -m "Add feature: brief description of the change"
```

Good commit message examples:
- `Add support for custom configuration files`
- `Fix memory leak in archive extraction`
- `Refactor parser logic for better maintainability`
- `Update documentation for installation process`

## Coding Standards

### Zig Style Guide

Follow the official [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide):

- Use 4 spaces for indentation (not tabs)
- Maximum line length: 100 characters
- Use `camelCase` for function and variable names
- Use `PascalCase` for type names
- Add doc comments for public APIs using `///`
- Keep functions focused and small

### Code Quality

- Write self-documenting code with clear variable and function names
- Add comments for complex logic or algorithms
- Avoid premature optimization - prioritize readability first
- Handle errors explicitly - avoid `catch unreachable` unless absolutely justified
- Use Zig's safety features (bounds checking, overflow detection, etc.)

### Testing

- Write tests for new features and bug fixes
- Place tests in the same file as the code being tested or in `src/tests/`
- Use descriptive test names that explain what is being tested
- Aim for good test coverage of critical paths

Example test:
```zig
test "feature description" {
    const result = yourFunction(input);
    try std.testing.expectEqual(expected, result);
}
```

## Submitting Changes

### Before Submitting a Pull Request

1. Ensure all tests pass:
   ```bash
   zig build test
   ```
2. Build the project successfully:
   ```bash
   zig build
   ```
3. Update documentation if you've added or changed features
4. Rebase your branch on the latest upstream main:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

### Creating a Pull Request

1. Push your changes to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
2. Go to the original repository on GitHub
3. Click "New Pull Request"
4. Select your fork and branch
5. Fill out the pull request template with:
   - Clear description of the changes
   - Related issue number (if applicable)
   - Any breaking changes
   - Screenshots or examples (if applicable)
6. Submit the pull request

### Pull Request Review Process

- Maintainers will review your PR and may request changes
- Address feedback by pushing new commits to your branch
- Once approved, a maintainer will merge your PR
- Your contribution will be included in the next release

## Issue Guidelines

### Reporting Bugs

Use the [bug report template](../../issues/new?template=bug_report.yaml) and include:
- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Zig version, etc.)
- Relevant error messages or logs

### Requesting Features

Use the [feature request template](../../issues/new?template=feature_request.yaml) and include:
- Clear description of the proposed feature
- Use case and motivation
- Possible implementation approach (if you have ideas)
- Alternatives you've considered

### Working on Issues

- Check existing issues before creating a new one
- Comment on an issue if you'd like to work on it
- For first-time contributors, look for issues labeled `good first issue`
- Ask questions if anything is unclear

## Community

### Getting Help

- Open an issue for bugs or feature requests
- Start a discussion for general questions
- Be respectful and patient with maintainers and other contributors

### Recognition

Contributors will be acknowledged in:
- Release notes
- Project documentation
- GitHub contributors page

Thank you for contributing to Zarc! Your efforts help make this project better for everyone.
