# Neovim Language Tooling

This configuration uses Neovim 0.12's native LSP configuration and enablement APIs.
The server registry is the ordered allowlist in `lua/config/lsp.lua`.
Every server command resolves through `PATH` so the same editor files work across supported package providers.

## Configured Servers

| Language | Native config | Executable command | Filetypes |
| --- | --- | --- | --- |
| Bash and POSIX shell | `lsp/bashls.lua` | `bash-language-server start` | `bash`, `sh` |
| JSON | `lsp/jsonls.lua` | `vscode-json-language-server --stdio` | `json`, `jsonc` |
| Lua | `lsp/lua_ls.lua` | `lua-language-server` | `lua` |
| Python | `lsp/pyright.lua` | `pyright-langserver --stdio` | `python` |
| TOML | `lsp/taplo.lua` | `taplo lsp stdio` | `toml` |
| YAML | `lsp/yamlls.lua` | `yaml-language-server --stdio` | YAML variants configured in `lsp/yamlls.lua` |

The registry enables all six names lazily.
A language-server process starts only after Neovim opens a matching buffer.

## Providers

Homebrew and Arch use native packages.
Debian-family systems use the repository's managed exact-version fallbacks when an existing command is absent or unsatisfactory.

| Platform profile | Bash, JSON, Lua, Python, and YAML | Taplo |
| --- | --- | --- |
| Homebrew | Formulae `bash-language-server`, `vscode-langservers-extracted`, `lua-language-server`, `pyright`, and `yaml-language-server` | Formula `taplo` |
| Arch Linux | Packages `bash-language-server`, `vscode-json-languageserver`, `lua-language-server`, `pyright`, and `yaml-language-server` | Package `taplo-cli` |
| Debian-family Linux | Managed Node 24.19.0 with exact npm packages `bash-language-server@5.6.0`, `vscode-langservers-extracted@4.10.0`, `pyright@1.1.411`, and `yaml-language-server@1.24.0`; managed LuaLS 3.19.1 | Exact Taplo 0.10.0 release artifact for x86_64 or ARM64 |

The Debian fallback publishes commands below the managed local-bin boundary only after verified staging and collision checks.
It does not install language-server packages through apt.
The Taplo consumer contract requires a stable version 0.10.0 or newer and a working `lsp stdio` subcommand.

## Taplo Roots and Single Files

Taplo root discovery uses this order:

1. `.taplo.toml`
2. `taplo.toml`
3. `.git`

A nested Taplo project configuration therefore wins over an outer Git marker.
No `workspace_required` field is set, so a standalone TOML file remains eligible for Neovim's native single-file workspace behavior.

## TOML Schemas

The Taplo configuration deliberately has no `settings` table.
This preserves Taplo's project configuration, schema directives, root `$schema` key, and built-in SchemaStore catalog behavior.

Use a local directive when a project needs deterministic or private schema selection:

```toml
#:schema ./schema.json
```

Project rules may also live in `.taplo.toml` or `taplo.toml`.
Taplo's built-in remote SchemaStore catalog remains available by default, but remote lookup is fail-soft.
A catalog or remote-schema failure may remove catalog-derived diagnostics or completion for that document, but it must not break Neovim startup, start another server, or disable a local schema directive.

## Formatting

Taplo advertises document formatting, but this configuration never formats automatically.
There is no format-on-save autocmd, formatting keymap, formatting command, or Taplo-specific attach callback.

Request formatting explicitly when wanted:

```vim
:lua vim.lsp.buf.format({ name = "taplo" })
```

An explicit request edits the buffer.
It does not write the file unless the buffer is saved separately.

## Health Checks

Check the executable and capability in a shell:

```sh
command -v taplo
taplo --version
taplo lsp stdio --help
```

Check Neovim's resolved clients and configurations with:

```vim
:checkhealth vim.lsp
:lua print(vim.inspect(require("config.lsp").servers()))
:LspInfo
```

The ordered registry output must be:

```text
bashls, jsonls, lua_ls, pyright, taplo, yamlls
```

## Tests

Focused native-LSP suites live in:

```text
tests/bashls.lua
tests/jsonls.lua
tests/lsp.lua
tests/pyright.lua
tests/taplo.lua
tests/yamlls.lua
```

Every focused runner creates private HOME, XDG, log, runtime, and fixture roots.
The terminal-stack checker runs the Taplo focused proof plus its existing language-server and integrated-startup gates:

```sh
env -u TMUX -u TMUX_PANE ~/.config/dotfiles/check-terminal-stack
```

The Taplo suite uses a local JSON schema and does not require a successful SchemaStore request.
It proves root precedence, diagnostics, completion, hover, two-buffer client reuse, absence of implicit formatting, explicit formatting edits, client shutdown, fixture removal, and no new surviving Taplo process.

## Missing Commands

A missing language-server command does not prevent Neovim startup and does not affect unrelated buffers because the registry is lazy.
A matching buffer cannot start its server until the command is available.
Use `:checkhealth vim.lsp` and the terminal-stack checker to identify the missing command.

Run the bootstrap in planning mode to see the platform-specific remediation:

```sh
~/.config/dotfiles/bootstrap --window-manager none
```

Applying package or managed-tool changes requires explicit approval and the bootstrap's normal `--apply` flow.
Do not add an editor plugin fallback for a missing server.

## Validation Scope

The integrated Linux gate requires a real Taplo process and validates local-schema diagnostics, completion, hover, reuse, and explicit formatting.
Provider fixtures exercise Homebrew, Pacman, and Debian-family selection and failure contracts without mutating the host.
Simulated provider evidence is not native runtime evidence.
Native macOS attachment remains pending until the focused suite runs on a real Mac.
