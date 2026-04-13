# AGENTS.md — shemacs (`em`)

## Project Summary

`em` is an Emacs/mg-compatible text editor implemented as a **single shell
function**. The editor logic (~2300 lines) is written in pure Scheme (`em.scm`)
and AOT-compiled to native bash or zsh by [sheme](https://github.com/jordanhubbard/sheme).
After the first-run compile it starts instantly with no fork/exec overhead.

**Dependency**: [sheme](https://github.com/jordanhubbard/sheme) (`bs.sh`) is
required. It must be installed before shemacs can run.

License: BSD 2-Clause. Author: Jordan Hubbard.

## Repository Layout

```
em.scm          — The editor, ~2300 lines of pure Scheme
em.sh           — Bash launcher: AOT-compiles em.scm and sources the result
em.zsh          — Zsh launcher: same, targeting zsh output via bs-compile-zsh
Makefile        — install/uninstall/check/test targets
README.md       — User-facing documentation and keybinding reference
LICENSE         — BSD 2-Clause
AGENTS.md       — This file (LLM-oriented project documentation)
.github/        — Issue templates (bug_report.md, feature_request.md)
tests/          — expect-based integration tests and bench scripts
```

There is **one source file**: `em.scm` (Scheme). `em.sh` and `em.zsh` are
thin launchers — they contain no editor logic.

## The Implementation

### `em.scm` — The editor (Scheme)

~2300 lines of pure Scheme. Shell-neutral: all terminal I/O, file I/O, and
key reading are handled through sheme's built-in primitives (`read-byte`,
`write-stdout`, `terminal-raw!`, etc.). The source itself contains no
bash- or zsh-specific code.

### `em.sh` — Bash launcher

Thin wrapper (~130 lines). On first run it:
1. Locates `bs.sh` (sheme interpreter)
2. Locates `em.scm`
3. Compiles `em.scm` to native bash via `bs-compile` and writes the result
   to `em.scm.cache`
4. Sources the cache and calls `em_main`

Subsequent runs skip steps 1–3 (cache is valid) and go straight to step 4,
giving instant startup. Can be sourced into `~/.bashrc` to define `em()` as
a shell function, or run standalone as `bash em.sh file.txt`.

### `em.zsh` — Zsh launcher

Same as `em.sh` but uses `bs-compile-zsh` and writes `em.scm.zsh.cache`.
Sources into `~/.zshrc` or runs standalone as `zsh em.zsh file.txt`.

### Cache invalidation

The cache is skipped and regenerated if:
- `em.scm` is newer than the cache file
- `bs.sh` (the interpreter) is newer than the cache file
- The cache file fails validation

Delete caches to force rebuild:
```bash
rm -f ~/.em.scm.cache ~/.em.scm.zsh.cache
# or in the repo:
rm -f em.scm.cache em.scm.zsh.cache
```

## Architecture

### State Model

All editor state is held in Scheme variables inside `em.scm`:

| Variable(s) | Purpose |
|---|---|
| `em-lines` | Buffer content — list of strings, one per line |
| `em-cy`, `em-cx` | Cursor position (0-indexed line, 0-indexed column) |
| `em-top` | First visible line (scroll offset) |
| `em-rows`, `em-cols` | Terminal dimensions |
| `em-mark-y`, `em-mark-x` | Mark position (-1 = unset) |
| `em-modified` | Dirty flag for current buffer |
| `em-filename` | File path of current buffer |
| `em-bufname` | Display name of current buffer |
| `em-message` | Minibuffer/echo-area message |
| `em-kill-ring` | Kill ring (max 60 entries) |
| `em-undo-stack` | Undo stack (max 200 entries, auto-trimmed) |
| `em-bufs` | Multi-buffer storage (alist keyed by buffer id) |
| `em-macro-keys` | Keyboard macro recording |
| `em-goal-col` | Sticky column for vertical movement |

### Subsystems (in source order)

1. **Terminal Setup / Cleanup** (`em-init`, `em-cleanup`)
   - Saves/restores terminal state and traps
   - Enters raw mode via `terminal-raw!` / `terminal-restore!`
   - Uses the alternate screen buffer (`\e[?1049h`)

2. **Undo System** (`em-undo-push`, `em-undo`)
   - Record types: `insert-char`, `delete-char`, `join-lines`, `split-line`, `replace-line`, `replace-region`

3. **Rendering** (`em-render`)
   - Full-screen redraw on every keystroke
   - Tab expansion, region highlighting (ANSI reverse video)
   - Status line in Emacs format (`-UUU:**-- bufname (Fundamental) L## %%`)

4. **Input / Key Reading** (`em-read-key`)
   - Reads raw bytes via `read-byte`
   - Decodes control chars, ESC sequences, Meta key

5. **Movement** — char, word, line, page, buffer-level; goal-column tracking

6. **Editing** — self-insert, newline, open-line, delete, backward-delete

7. **Kill/Yank** — 60-entry kill ring; consecutive `C-k` appends

8. **Mark/Region** — set mark, exchange, mark whole buffer, kill/copy region

9. **Incremental Search** (`em-isearch`) — forward and backward

10. **Minibuffer** (`em-minibuffer-start`) — line editor with tab completion

11. **File I/O** — atomic save, load, find-file, write-file, insert-file

12. **Buffer Management** — multiple buffers, switch, kill, list

13. **Word Operations** — forward/backward word, kill word

14. **Transpose, Universal Argument, Quoted Insert**

15. **Query Replace** — interactive y/n/!/q/. (emacs-compatible)

16. **M-x Extended Commands** — goto-line, what-line, query-replace, etc.

17. **Help / Describe Bindings**

18. **Case Conversion** — capitalize, upcase, downcase word

19. **Fill Paragraph** — blank-line delimited, wraps at fill column (default 72)

20. **Keyboard Macros** — record/playback

21. **Key Dispatch** (`em-dispatch`, `em-read-cx-key`, `em-read-meta-key`)

22. **Eval Buffer** (`em-eval-buffer`) — evaluate current buffer as Scheme code

## Key Design Decisions & Constraints

- **Pure Scheme editor logic**: No shell-specific code in `em.scm`. All I/O
  goes through sheme primitives.
- **AOT compilation**: `em.scm` is compiled once to native shell code. At
  runtime the cache is sourced directly — no interpreter overhead.
- **No EXIT trap**: Shell functions that set EXIT traps are dangerous (the
  trap lingers after the function returns). Cleanup is called explicitly and
  via INT/TERM/HUP traps.
- **Full redraw**: Every keystroke triggers a complete screen redraw. No
  dirty-line tracking.
- **Atomic saves**: File writes go to a temp file first, then `mv` to target.
- **Push gate**: Before any push, `make test` and `make example` must pass.

## Naming Conventions

- Scheme functions: `em-<name>` (dash-separated)
- Scheme globals: `em-<name>`
- Key names: `C-x` (control), `M-x` (meta/alt), `SELF:x` (printable self-insert)

## Keybindings

The editor aims for mg/emacs compatibility. All bindings are documented in
the header comment of `em.scm` (lines 1–35) and in `README.md`. The dispatch
table is in `em-dispatch` and `em-read-cx-key`.

## Building and Testing

```bash
make check                       # syntax-check em.sh and em.zsh
make install                     # install launchers and em.scm to ~/
make uninstall                   # remove all installed shemacs files/source lines
make test                        # run integration tests (requires expect + sheme)
make example                     # run smoke example (requires expect + sheme)
```

The launchers can also be run standalone:
```bash
bash em.sh file.txt
zsh em.zsh file.txt
```

## Common Modification Patterns

**Adding a new keybinding**: Add a case to `em-dispatch` (or `em-read-cx-key`
for C-x prefix bindings). Write the handler as a new `em-*` function.
Remember to push undo records for any buffer mutations.

**Adding an M-x command**: Add a case in `em-execute-extended` and add the
command name to the completion list in `em-all-commands`.

**Adding a new undo type**: Add a case to `em-undo` and call `em-undo-push`
with the new type from the mutation function. `replace-region` is the most
general existing type.

**Modifying buffer state**: Always push an undo record *before* mutating
`em-lines`. Set `em-modified` to `#t`. Call `em-ensure-visible` if the
cursor moved. Reset `em-goal-col` to -1 if horizontal position changed.

## Gotchas

- Lines are 0-indexed internally; line numbers displayed to the user are 1-indexed.
- `em-lines` always has at least one element (empty string for empty buffer).
- The undo stack auto-trims at 200 entries (drops oldest 100).
- The kill ring caps at 60 entries.
- Tab characters are expanded for *display* only — stored as literal `\t`.
- The sheme cache files (`em.scm.cache`, `em.scm.zsh.cache`) are listed in
  `.gitignore` and should not be committed.
- If the editor behaves strangely after updating sheme or em.scm, delete the
  cache files to force regeneration.
