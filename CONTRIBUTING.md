# Contributing to Pedantic

Thank you for your interest in contributing to Pedantic! We welcome contributions from the community to help build the DSC ecosystem hub.

## Vision

Pedantic aims to be **the Ansible Galaxy for DSC** - a central platform where the DSC community can discover, share, and collaborate on DSC resources and configurations. Your contributions help make this vision a reality.

## Ways to Contribute

### 1. Share DSC Resources
- Publish your DSC configurations and resources
- Document best practices and patterns
- Share real-world use cases and examples

### 2. Improve Tooling
- Enhance the PowerShell module functionality
- Contribute to the VS Code extension development
- Improve documentation and examples

### 3. Report Issues
- Bug reports with detailed reproduction steps
- Feature requests aligned with our roadmap
- Documentation improvements

### 4. Join Discussions
- Share your DSC experiences and challenges
- Help others in the community
- Provide feedback on new features

## Getting Started

### Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/plures/pedantic.git
   cd pedantic
   ```

2. **PowerShell Module Development:**
   ```powershell
   # Import the module in development mode
   Import-Module ./Pedantic.psd1
   
   # Run tests (when available)
   Invoke-Pester ./tests
   ```

3. **VS Code Extension Development:**
   ```bash
   cd extension
   npm install
   npm run build
   npm test
   ```

### Testing Your Changes

Before submitting a pull request:

1. **Test the PowerShell module:**
   ```powershell
   Import-Module ./Pedantic.psd1
   
   # Test basic functionality
   Get-Command -Module Pedantic
   
   # Test utilities
   @(1..5) | Get-Head -Count 3
   ```

2. **Run linting/formatting:**
   ```powershell
   # PowerShell script analysis
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1
   ```

3. **Verify examples still work:**
   - Test examples from README.md
   - Ensure documentation matches code behavior

## Pull Request Process

1. **Fork the repository** and create a feature branch
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes** following our coding standards:
   - PowerShell: Follow the style in existing code
   - Documentation: Clear, concise, with examples
   - Comments: Explain "why" not "what"

3. **Commit your changes** with clear messages:
   ```bash
   git commit -m "Add feature: brief description"
   ```

4. **Push to your fork** and create a Pull Request:
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Describe your changes** in the PR:
   - What problem does it solve?
   - How does it work?
   - Any breaking changes?
   - Related issues (if any)

## Coding Standards

### PowerShell
- Use approved verbs (`Get-Verb` for list)
- Follow PascalCase for functions and parameters
- Include comment-based help for all public functions
- Use `Write-Verbose` for informational messages
- Use `Write-Warning` for warnings
- Throw exceptions for errors

### Documentation
- Keep README.md up-to-date with major changes
- Update ROADMAP documents if adding significant features
- Include examples in documentation
- Use clear, accessible language

### Commits
- Use present tense ("Add feature" not "Added feature")
- Keep first line under 72 characters
- Reference issues and PRs when relevant

## Roadmap Alignment

Please review our roadmap documents to ensure your contribution aligns with project direction:

- [NEXT-STEPS.md](NEXT-STEPS.md) - Current priorities
- [MVP-PLAN.md](MVP-PLAN.md) - Next phase development
- [RELEASE-1.0-PLAN.md](RELEASE-1.0-PLAN.md) - 1.0 release targets
- [FULL-ROADMAP-PLAN.md](FULL-ROADMAP-PLAN.md) - Long-term vision

## Community Guidelines

### Be Respectful
- Treat everyone with respect and kindness
- Welcome newcomers and help them contribute
- Assume good intentions
- Provide constructive feedback

### Be Collaborative
- Share knowledge and learn from others
- Help review pull requests
- Participate in discussions thoughtfully
- Credit others' work

### Focus on Value
- Prioritize features that benefit the community
- Consider maintenance burden of new features
- Document decisions and rationale
- Test thoroughly before submitting

## Questions?

- **Issues**: For bug reports and feature requests
- **Discussions**: For questions and general discussion
- **Plures Organization**: Check out other projects at [github.com/plures](https://github.com/plures)

## License

By contributing to Pedantic, you agree that your contributions will be licensed under the Apache-2.0 License.

---

Thank you for helping build the DSC community hub! 🚀
