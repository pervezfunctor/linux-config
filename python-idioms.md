## Python idioms for this repo

These are the default preferences to follow when editing Python here, especially `setup.py`.

### Core constraints

- Use the Python standard library only unless explicitly told otherwise.
- Keep the code friendly to strict type checking (`# pyright: strict`).
- Prefer simple, obvious code over clever abstractions.
- Reduce line count when it improves readability.

### Structure

- Prefer top-level functions over classes.
- Keep classes only when they clearly add value (for example, small dataclasses for real data grouping).
- Inline thin wrapper functions that only forward arguments.
- Inline single-use helper functions unless they substantially improve readability.
- Avoid helper families like `build_*`, `run_*`, `capture_*`, etc. when they are only pass-through layers.
- Do not introduce architecture for its own sake.

### Logging and output

- If logging is needed, use minimal stdlib `logging`.
- No color output.
- No custom formatter/filter/handler class boilerplate unless there is a concrete need.
- Small helper functions like `log`, `warn`, and `error` are fine if they keep call sites clean.
- Send warnings and errors to `stderr`.

### Subprocesses

- Prefer direct `subprocess.run(...)` calls over tiny wrapper functions.
- Only keep a subprocess helper if it adds real behavior, not just argument forwarding.
- Keep command execution readable at the call site.

### Generators and comprehensions

- Use generator expressions when they are clearly better, especially with `any(...)`, `all(...)`, and `"".join(...)`.
- Do not introduce generator functions or generator-heavy abstractions unless they make the code simpler.
- Prefer normal loops when they are clearer.

### Style preferences

- Prefer fewer moving parts.
- Prefer explicit control flow.
- Prefer local logic over indirection.
- Avoid over-engineering.
- Keep import-time behavior minimal.

### Validation after edits

For `setup.py`-style changes, usually run:

- `python3 -m py_compile setup.py`
- `python3 setup.py --help`
- IDE diagnostics
- small targeted assertions for pure/helper logic when useful

### Decision rule

When choosing between two valid Python styles, prefer the one that is:

1. shorter,
2. more direct,
3. easier to read in one pass,
4. less abstract,
5. still type-check-friendly.
