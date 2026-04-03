# Gitologist - Agent Guidelines

Gitologist is a Git implementation in multiple languages: TypeScript, Swift, and C#.

## Project Structure

```
/
├── web/          # TypeScript implementation (Vite+)
├── swift/        # Swift implementation (Swift Package Manager)
└── dotnet/       # C# implementation (.NET 8)
```

---

## Web (TypeScript)

Uses **Vite+**, a unified toolchain on top of Vite, Vitest, Oxlint, and Oxfmt.

### Build/Lint/Test Commands

All commands run from `web/` directory:

```bash
# Install dependencies
vp install

# Development
vp dev              # Run dev server
vp pack             # Build library
vp pack --watch     # Build in watch mode

# Testing
vp test             # Run all tests
vp test init        # Run single test file (pattern match)
vp test --run       # Run tests once (CI mode)

# Code quality
vp check            # Run format, lint, and type checks
vp lint             # Lint with Oxlint
vp lint --type-aware # Type-aware linting
vp fmt              # Format with Oxfmt
```

### Code Style (TypeScript)

- **Imports**: Use `node:` prefix for Node.js modules (`import { readFile } from "node:fs/promises"`)
- **Module imports**: Use `.ts` extensions (`import { init } from "./init.ts"`)
- **Formatter**: Oxfmt with tabs, 100 print width, trailing commas
- **Test imports**: Import from `vite-plus/test` (`import { describe, it, expect } from "vite-plus/test"`)

**File structure:**

1. Imports (external → internal)
2. Interfaces/types
3. Exported functions/classes (public API)
4. Helper functions (in call order)

**Naming:**

- Functions: camelCase (`initRepo`, `parseCommit`)
- Types/Interfaces: PascalCase (`LogEntry`, `MergeResult`)
- Constants: UPPER_SNAKE_CASE for true constants

### Key Rules

- Never use pnpm/npm/yarn directly - always use `vp`
- Don't install Vitest/Oxlint/Oxfmt directly - use Vite+ commands
- Import from `vite-plus`, not `vite` or `vitest`

---

## Swift

Uses **Swift Package Manager** with Swift 6.2+, macOS 13+ platform.

### Build/Lint/Test Commands

All commands run from `swift/` directory:

```bash
# Build
swift build
swift build -c release

# Testing
swift test                          # Run all tests
swift test --filter InitTests       # Run single test class
swift test --filter InitTests.shouldCreateGitDirectory  # Run single test

# Linting/Formatting
swift-format lint --recursive Sources/ Tests/
swift-format format --recursive --in-place Sources/ Tests/
```

### Code Style (Swift)

- **Indentation**: Tabs
- **Imports**: Foundation first, then others
- **Access control**: Implicit internal by default

**Naming:**

- Types: PascalCase (`LogEntry`, `MergeOptions`)
- Functions/variables: camelCase (`initRepo`, `abbreviatedSha`)
- Private constants: lowerCamelCase or UPPER_SNAKE_CASE for file-level constants

**Testing (Swift Testing framework):**

- Use `@Test` attribute on test functions
- Use `#expect()` for assertions
- Test naming: descriptive, starts with "should"
- Use `@testable import Gitologist` for internal access

---

## .NET (C#)

Uses **.NET 10** with SDK-style projects.

### Build/Lint/Test Commands

All commands run from `dotnet/` directory:

```bash
# Build
dotnet build
dotnet build -c Release

# Testing
dotnet test                         # Run all tests
dotnet test --filter "FullyQualifiedName~InitTests"  # Run single test class
dotnet test --filter "FullyQualifiedName~should_create_git_directory"  # Run single test

# Code quality
dotnet format                       # Format code
dotnet format --verify              # Check formatting (CI)
```

### Code Style (C#)

- **Target framework**: .NET 8.0
- **Implicit usings**: enabled
- **Nullable**: enabled

**Naming:**

- Classes/interfaces: PascalCase
- Methods: PascalCase
- Properties: PascalCase
- Fields: camelCase with `_` prefix for private fields
- Constants: PascalCase or UPPER_SNAKE_CASE

---

## Cross-Language Consistency

This project implements the same Git functionality across languages. When adding features:

1. Implement in all three languages when possible
2. Keep public APIs similar (same function names where idiomatic)
3. Types should have equivalent fields across implementations
4. Tests should cover the same scenarios

## Review Checklist

Before submitting changes:

- [ ] Run install command after pulling changes
- [ ] Run check/lint commands for the language
- [ ] Run all tests (or at least affected tests)
- [ ] Follow naming conventions for the language
- [ ] Keep code structure consistent with existing files
