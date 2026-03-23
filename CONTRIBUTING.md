# Contributing to plushie-ruby

## Setup

```bash
git clone https://github.com/plushie-ui/plushie-ruby.git
cd plushie-ruby
bundle install
rake plushie:download   # precompiled renderer binary
```

Requires Ruby 3.2+. No Rust toolchain needed unless building from
source or writing native extensions.

## Running checks

```bash
bundle exec rake              # tests + linter + type check
bundle exec rake test         # tests only
bundle exec rake standard     # linter only
bundle exec rake steep        # type check only
bundle exec rake yard         # generate API docs to doc/
rake plushie:preflight        # full CI mirror (standard, steep, test, yard)
```

### Test backends

Tests run against the renderer binary. Three interchangeable backends:

```bash
bundle exec rake test                                # mock (default, fastest)
PLUSHIE_TEST_BACKEND=headless bundle exec rake test   # real rendering, no display
PLUSHIE_TEST_BACKEND=windowed bundle exec rake test   # real windows (needs display)
```

Mock is fast enough for TDD loops. CI runs both mock and headless.

## Commits

Run `bundle exec rake` before committing. CI runs the same checks.

### Message format

Use imperative mood. Describe what changed and why, not how.

```
feat: add on_resize subscription for window resize events

The renderer already emits resize events but the SDK had no
subscription type for them. Apps had to poll window dimensions
on a timer, which was wasteful and laggy.
```

Prefix with a category when it clarifies intent:

| Prefix     | Use for                                    |
|------------|--------------------------------------------|
| `feat:`    | new user-facing functionality               |
| `fix:`     | bug fix                                    |
| `docs:`    | documentation only                         |
| `test:`    | test additions or corrections              |
| `refactor:`| restructuring without behaviour change     |
| `chore:`   | deps, CI, tooling, release prep            |

# Pull requests

- One logical change per PR. If a refactor enables a feature, consider
  splitting them unless the refactor is small and tightly coupled.
- PR title follows the same format as commit messages.
- Include a brief description of what and why. If there's a visual
  change, a screenshot or before/after helps.
- All CI checks must pass.

## Code style

[Standard](https://github.com/standardrb/standard) handles formatting
and linting. No configuration to argue about.

Beyond what Standard enforces:

- **Let the code speak.** Only comment when intent isn't obvious from
  the code itself.
- **Prefer real implementations over mocks in tests.** The mock backend
  is already fast; mocking Ruby internals hides real bugs.
- **Tests are documentation.** Write them so the next person
  understands the behaviour, not just that it "passes".
- **ID is always the first argument** for widget builders.

## Type signatures

RBS signatures live in `sig/`. When adding or changing public API
methods, update the corresponding `.rbs` file. Run `bundle exec rake
steep` to verify.

## Documentation

Public API methods use YARD-style doc comments (`@param`, `@return`,
`@example`). Guides live in `docs/` as Markdown. Generate and browse
locally:

```bash
bundle exec rake yard
open doc/index.html
```

## Architecture overview

See the [project layout and architecture](README.md#how-it-works) in
the README, or the detailed guide docs:

- [Getting started](docs/getting-started.md)
- [App behaviour](docs/app-behaviour.md)
- [Events](docs/events.md)
- [Commands](docs/commands.md)
- [Testing](docs/testing.md)
