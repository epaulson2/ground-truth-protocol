# Contributing to Ground Truth Protocol

Thank you for your interest in improving the Ground Truth Protocol. This framework benefits from real-world experience across different teams, tools, and project types.

## How to Contribute

### Report a Failure Pattern

If you have encountered a context drift failure that the protocol does not address, open an issue with:

- **What happened**: The specific failure (e.g., agent created a duplicate resource)
- **What guardrails were in place**: Rules, documents, or mechanisms that should have prevented it
- **Why they failed**: Root cause analysis (was it a document the agent did not read, a rule it ignored, or a gap in mechanical enforcement?)
- **Proposed mechanism**: A script, hook, or gate that would mechanically prevent the failure

### Add an Example

The `examples/` directory benefits from integration patterns for different tools and stacks. Contributions welcome for:

- Pre-flight probes for additional stacks (e.g., Go + MongoDB, Rust + SQLite)
- Assertion gate patterns for additional tools
- Integration configurations for AI coding tools not yet covered

### Improve Documentation

If something is unclear, incomplete, or could be better explained, submit a pull request. Maintain these principles:

- **Mechanisms over documents**: Do not add advisory rules. Add mechanical enforcement patterns.
- **Concreteness over abstraction**: Include specific commands, specific scripts, specific outputs.
- **Evidence over assertion**: Cite research, measurements, or real-world failure data.

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b add-django-probe`)
3. Make your changes
4. Ensure all examples are syntactically valid (`shellcheck examples/*.sh`)
5. Submit a pull request with a clear description of what you are adding and why

## Code of Conduct

Be direct, be specific, be helpful. This project values clarity over politeness and mechanisms over intentions.

## Questions?

Open an issue. Questions that reveal gaps in the documentation are especially valuable -- they may indicate places where a mechanism is needed instead of a document.
