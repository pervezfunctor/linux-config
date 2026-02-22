# Nushell Best Practices

A condensed guide to writing clean and idiomatic Nushell code, based on the official [Style Guide](https://www.nushell.sh/book/style_guide.html).

## Formatting

### General Rules
- **One-line Format**: Default to writing pipelines on a single line unless writing scripts, the line exceeds 80 characters, or there are nested lists/records.
- **Multi-line Format**: Use when writing scripts, exceeding 80 characters, or dealing with nested lists/records. Omit trailing spaces and place block bodies, record pairs, and list items on their own respective lines.

### Spacing and Punctuation
- **Pipes & Commands**: Put exactly one space before and after the pipe `|` symbol, commands, subcommands, options, and arguments.
- **Consecutive Spaces**: Avoid multiple consecutive spaces unless they are inside a string.
- **Lists**: Omit commas between list items (e.g., `[1 2 3]`).
- **Commas**: If using a comma (e.g., parameters or key-value structures), place exactly one space after it.
- **Records**: Put exactly one space after the colon `:` in a record key.
- **Surrounding Constructs**: Put one space inside opening and closing brackets, braces, and parentheses `[ { (` and `) } ]`, unless the adjacent symbol is identical. For multi-line formats, place these constructs on singular lines using newlines.

## Naming Conventions

- **Avoid Abbreviations**: Use full, concise words unless the abbreviation is universally well-known.
- **Commands & Sub-commands**: Use `kebab-case` (e.g., `fetch-user`, `date list-timezone`).
- **Flags**: Use `kebab-case` (e.g., `--all-caps`). Note that Nushell maps dashes to underscores when defining variables for flags inside commands.
- **Variables & Parameters**: Use `snake_case` (e.g., `let user_id = 123`, `def fetch-user [user_id: int]`).
- **Environment Variables**: Use `SCREAMING_SNAKE_CASE` (e.g., `$env.APP_VERSION`).

## Custom commands

- **Positional Parameters**: Default to using positional parameters when possible, but keep the total positional count to 2 or fewer (e.g., source and target).
- **Options**: Use options/flags for any remaining variables, or when variables are optional but at least one is required. Provide both long and short option flags whenever possible.
- **Documentation**: Provide documentation strings for all exported entities and their specific inputs.
