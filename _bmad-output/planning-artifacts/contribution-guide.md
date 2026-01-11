# Contribution Guide - Android-CI-builder

## Code Style and Conventions

### Shell Scripting Standards
- Use `#!/usr/bin/env bash` shebang for all bash scripts
- Include `set -euo pipefail` at the beginning of scripts for error handling
- Use 2-space indentation (no tabs)
- Use descriptive variable and function names
- Add comments for complex operations and business logic
- Keep functions focused on a single responsibility

### Naming Conventions
- Use snake_case for variable and function names
- Use lowercase for script filenames
- Use descriptive names that indicate the script's purpose
- Prefix helper functions with an underscore if they're not meant to be called externally

### Error Handling
- Use `|| true` for commands that may fail but shouldn't stop the workflow
- Use `set +e` and `set -e` appropriately for commands that may intentionally fail
- Log errors to appropriate files when needed
- Use meaningful error messages for debugging

## PR Process

### Pre-Submission Checklist
- [ ] Code follows the established style guidelines
- [ ] Changes have been tested with a kernel build
- [ ] New functionality is documented if applicable
- [ ] No hardcoded values that should be parameters
- [ ] Error handling is appropriate for the change
- [ ] Changes don't break existing functionality

### Creating a Pull Request
1. Fork the repository and create a feature branch
2. Make your changes following the code style guidelines
3. Test your changes with actual kernel builds if applicable
4. Commit your changes with clear, descriptive commit messages
5. Push your branch to your fork
6. Create a pull request with a clear description of the changes

### Pull Request Description Template
When creating a pull request, please include:
- A clear description of what the changes do
- Why these changes are needed
- How the changes were tested
- Any breaking changes or migration notes if applicable

## Testing Requirements

### Unit Testing
- Test individual scripts with various inputs
- Verify error handling paths
- Test with both valid and invalid parameters

### Integration Testing
- Test the complete build workflow with a small kernel repository
- Verify that artifacts are generated correctly
- Check that environment variables are set properly
- Test notification systems if modified

### Testing Environment
- Use GitHub Actions for full integration testing
- Test with multiple kernel sources if the change affects compatibility
- Verify caching mechanisms still work properly

## Development Workflow

### Setting Up Local Development
1. Fork and clone the repository
2. Make CI scripts executable: `chmod +x ci/*.sh`
3. Test changes with a small kernel repository before submitting

### Making Changes
1. Create a new branch for your feature or bug fix
2. Make focused changes that address a single issue
3. Add or update tests as needed
4. Verify your changes work as expected
5. Commit with a clear, descriptive message
6. Push and create a pull request

### Code Review Process
- All submissions require review before merging
- Reviewers will check for code quality, functionality, and adherence to guidelines
- Address feedback promptly and thoroughly
- Updates to the PR should be added as new commits for easier review

## Documentation Standards

### Commenting Code
- Add comments for complex operations
- Document function purposes and parameters
- Update comments when changing functionality
- Use consistent comment style throughout

### Updating Documentation
- Update README if user-facing changes are made
- Add documentation for new features
- Update examples if parameters or workflow changes

## Commit Message Standards

### Format
Use the format: `type(scope): description`

Examples:
- `feat(ci): add support for new compiler version`
- `fix(build): resolve issue with ccache initialization`
- `docs: update parameter documentation in README`

### Types
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code changes that don't fix bugs or add features
- `test`: Adding or modifying tests
- `chore`: Other changes

## Areas for Contribution

### High Priority
- Improving build performance and optimization
- Adding support for additional kernel configurations
- Enhancing error handling and debugging capabilities
- Improving documentation and examples

### Medium Priority
- Adding new notification integrations
- Improving caching strategies
- Adding more comprehensive testing
- Enhancing security practices

### Good First Issues
- Fixing typos in documentation
- Improving comments in scripts
- Adding examples to README
- Updating outdated information

## Communication Standards

### Issues
- Use clear, descriptive titles
- Provide detailed steps to reproduce bugs
- Include expected vs. actual behavior
- Tag with appropriate labels

### Pull Requests
- Link to related issues when applicable
- Provide clear description of changes
- Respond to review comments in a timely manner
- Be respectful and constructive in discussions

## Security Considerations

### Reporting Security Issues
- Report security vulnerabilities responsibly
- Do not disclose security issues in public forums
- Follow responsible disclosure practices

### Code Security
- Avoid executing untrusted input
- Validate all parameters and inputs
- Be cautious with file operations
- Review changes for potential security implications