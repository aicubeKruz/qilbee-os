# Contributing to Qilbee OS

Thank you for your interest in contributing to Qilbee OS! This document provides guidelines and information for contributors.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please be respectful and constructive in all interactions.

## Getting Started

### Prerequisites

- Python 3.11 or higher
- Docker and Docker Compose
- Kubernetes cluster (for deployment testing)
- Git

### Development Setup

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/your-username/qilbee-os.git
   cd qilbee-os
   ```

3. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

4. Install dependencies:
   ```bash
   pip install -r requirements.txt -e .
   pip install -r requirements-dev.txt
   ```

5. Set up pre-commit hooks:
   ```bash
   pre-commit install
   ```

## Development Guidelines

### Code Style

- Follow PEP 8 style guidelines
- Use Black for code formatting: `black src/ tests/`
- Use flake8 for linting: `flake8 src/ tests/`
- Use mypy for type checking: `mypy src/`

### Testing

- Write tests for all new functionality
- Maintain test coverage above 80%
- Run tests with: `pytest`
- Run specific test categories: `pytest -m unit` or `pytest -m integration`

### Documentation

- Update documentation for any API changes
- Follow Google-style docstrings
- Update README.md if needed
- Add entries to CHANGELOG.md

## Pull Request Process

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes and commit them:
   ```bash
   git add .
   git commit -m "feat: add new feature description"
   ```

3. Push to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

4. Create a Pull Request on GitHub

### Commit Message Format

Use conventional commits format:
- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `test:` for test additions/changes
- `refactor:` for code refactoring
- `chore:` for maintenance tasks

## Architecture Guidelines

### Component Structure

Each major component should follow this structure:
```
src/component_name/
├── __init__.py
├── main.py          # Entry point
├── api/            # API endpoints
├── models/         # Data models
├── services/       # Business logic
├── utils/          # Utilities
└── tests/          # Component-specific tests
```

### Security Considerations

- All external inputs must be validated
- Use parameterized queries for database operations
- Implement proper authentication and authorization
- Follow principle of least privilege
- Document security implications of changes

### Tool Development

To create a new tool plugin:

1. Create a new package in `tools/`
2. Implement the tool interface
3. Add entry point in `pyproject.toml`
4. Include comprehensive tests
5. Document usage and security requirements

Example tool structure:
```python
def get_tool_function():
    return my_tool_function

def get_tool_schema():
    return {
        "name": "my_tool",
        "description": "What the tool does",
        "input_schema": {
            "type": "object",
            "properties": {...},
            "required": [...]
        }
    }

def my_tool_function(param1: str, param2: int = 0) -> dict:
    """Tool implementation."""
    # Your code here
    return {"result": "success"}
```

## Issue Guidelines

### Bug Reports

Please include:
- Clear description of the bug
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Python version, etc.)
- Relevant logs or error messages

### Feature Requests

Please include:
- Clear description of the feature
- Use case and motivation
- Proposed implementation approach
- Any breaking changes

## Security

If you discover a security vulnerability, please email security@aicube.technology instead of opening a public issue.

## Questions?

- Check existing issues and discussions
- Join our community channels
- Contact maintainers directly

Thank you for contributing to Qilbee OS!