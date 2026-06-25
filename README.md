# GUTCheck: Code coverage for Godot Unit Test

[![CI](https://github.com/andypoorman/GUTCheck/actions/workflows/ci.yml/badge.svg)](https://github.com/andypoorman/GUTCheck/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/andypoorman/GUTCheck/graph/badge.svg)](https://codecov.io/gh/andypoorman/GUTCheck)

Code coverage for [GUT](https://github.com/bitwes/Gut) (Godot Unit Test).

GUTCheck instruments your GDScript source files at runtime, tracks which lines and branches execute during your test run, and outputs LCOV or Cobertura XML coverage reports compatible with GitHub Actions, Codecov, Coveralls, and other standard CI tools.

## How It Works

GUTCheck includes a GDScript tokenizer and statement-level parser written entirely in GDScript. The pipeline:

1. **Tokenize** - Lexes GDScript source into tokens, handling strings (single, double, triple-quoted, raw, StringName, NodePath), comments, annotations, operators, keywords, number literals (hex, binary, octal, scientific, underscores), indentation tracking, line continuations, and multiline expressions.
2. **Classify** - Each source line is classified as executable, branch (`if`/`elif`/`else`), loop (`for`/`while`), match pattern, function def, class def, property accessor, or non-executable (comments, blanks, `class_name`, `extends`, `signal`, `enum`, `const` with literals, annotations).
3. **Instrument** - Source-to-source transformation injects coverage probes while preserving line numbers exactly. Simple statements get a semicolon-prepended `hit()` call. Compound statements (`if`, `while`, `for`, `match`) get their condition/iterable wrapped so the probe doesn't break syntax.
4. **Collect** - As tests run, probes call static methods on `GUTCheckCollector` which records hits in `PackedInt32Array` for fast indexed access.
5. **Export** - Generates standard LCOV tracefiles with function records (`FN`/`FNDA`), branch records (`BRDA`/`BRF`/`BRH`), and line records (`DA`). Optionally exports Cobertura XML.

All instrumentation happens in memory via Godot's dynamic `GDScript` API. Your source files are never modified on disk.

## Why a GDScript parser in GDScript?

Godot has a full GDScript parser internally (`GDScriptParser` in `modules/gdscript/`), but it's a plain C++ class that isn't registered with ClassDB. That means it's not accessible from GDExtension or from GDScript at runtime. There's an [open proposal](https://github.com/godotengine/godot-proposals/issues/4958) to expose AST access and an [unmerged PR](https://github.com/godotengine/godot/pull/104417) for a `--script-dump-ast` CLI flag, but neither provides a runtime API usable by addons.

Building a custom engine module would give full parser access, but that requires every user to compile a custom Godot build, which isn't viable for a distributed addon.

So GUTCheck implements its own tokenizer and statement-level parser in pure GDScript. It doesn't need a full expression parser or type resolution. It just needs to know which lines are executable, where branches and loops are, and where it's safe to inject probes. The GDScript grammar is simple enough (Python-like, roughly LL(1)) that a hand-written tokenizer and line classifier can handle it reliably.

The tokenizer was cross-referenced against Godot's `gdscript_tokenizer.h` token enum and `gdscript_parser.h` node types to make sure we're not missing syntax that would cause misparsing.

## Requirements

- Godot 4.6+
- GUT 9.x+

## Installation

1. Copy the `addons/gut_check/` directory into your project's `addons/` folder
2. Enable the plugin in **Project > Project Settings > Plugins**

## Configuration

Create a `.gutcheck.json` file in your project root:

```json
{
  "source_dirs": ["res://src/", "res://scripts/"],
  "exclude_patterns": ["**/test_*.gd", "**/addons/**"],
  "lcov_output": "res://coverage.lcov",
  "coverage_target": 0
}
```

### Config Options

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `source_dirs` | `Array[String]` | `["res://"]` | Directories to scan for source scripts to instrument |
| `exclude_patterns` | `Array[String]` | `["**/test_*.gd", "**/addons/**", "**/autoload/**"]` | Glob patterns for files to exclude from coverage |
| `lcov_output` | `String` | `"res://coverage.lcov"` | Path to write the LCOV tracefile |
| `coverage_target` | `float` | `0` | Minimum coverage percentage (0-100). Post-run hook sets exit code 1 if not met |
| `cobertura_output` | `String` | `""` | Path to write Cobertura XML. Empty string disables Cobertura export |

## GUT Integration

GUTCheck integrates with GUT through pre-run and post-run hook scripts. Add these to your `.gutconfig.json`:

```json
{
  "pre_run_script": "res://addons/gut_check/hooks/pre_run_hook.gd",
  "post_run_script": "res://addons/gut_check/hooks/post_run_hook.gd"
}
```

GUTCheck will instrument your source scripts before tests run and export coverage after they finish.

If you already have custom hook scripts, call GUTCheck from within them:

```gdscript
# your_pre_run_hook.gd
extends GutHookScript

func run():
    var gut_check = GUTCheck.new()
    gut_check.load_config()
    gut_check.instrument_scripts()
    # ... your other pre-run logic
```

```gdscript
# your_post_run_hook.gd
extends GutHookScript

func run():
    var gut_check = GUTCheck.new()
    gut_check.load_config()
    gut_check.export_coverage()
    gut_check.print_summary(gut.logger)
    # ... your other post-run logic
```

## Viewing Coverage

After running tests, you'll have a `coverage.lcov` file. Use `genhtml` (from the `lcov` package) to generate an HTML report:

```bash
genhtml coverage.lcov -o coverage_html --ignore-errors category
open coverage_html/index.html
```

Install `lcov` with `brew install lcov` (macOS) or `apt install lcov` (Linux).

## Instrumentation Details

GUTCheck preserves source line numbers exactly. No lines are added or removed. The instrumentation strategy varies by statement type:

**Simple executable lines** (assignments, calls, return, etc.) get a semicolon-prepended probe:
```gdscript
# Original                    # Instrumented
var x = 10                    GUTCheckCollector.hit(0,1);var x = 10
print("hello")                GUTCheckCollector.hit(0,2);print("hello")
```

**Compound statements** get their condition/iterable wrapped so the probe doesn't break GDScript's block syntax:
```gdscript
# Original                    # Instrumented
if x > 5:                     if GUTCheckCollector.hit_br2(0,3,4,5,x > 5):
for i in range(10):           for i in GUTCheckCollector.hit_br2rng(0,6,7,8,range(10)):
while running:                while GUTCheckCollector.hit_br2(0,9,10,11,running):
match state:                  match GUTCheckCollector.br(0,12,state):
```

`hit_br2()` records the line probe plus the true- or false-branch probe depending on the condition's truthiness; `hit_br2rng()` does the same keyed on whether the iterable is empty. `br()` records a single hit for a `match` subject. (When only one side of a branch is measurable, the simpler `br()` / `rng()` forms are emitted instead.) All return the value unchanged, so there's no semantic change to your code.

**`else:` and match patterns** can't have their header wrapped (they're not expressions). When the body is a block, coverage is inferred from the block's first line; when the body is inline (`else: x()` or `"up": return v`), a probe is injected after the colon so the branch only counts when the body actually runs:
```gdscript
# Original                    # Instrumented
else: x()                     else: GUTCheckCollector.hit(0,7);x()
"up": return v                "up": GUTCheckCollector.hit(0,8);return v
```

**Multiline statements** (conditions split across lines with parentheses or `\`) are instrumented as a whole logical statement — the wrapped condition keeps its original line breaks, so line numbers still match your source.

**Property accessors** with block bodies (`get:` / `set(value):`) are tracked as functions and their bodies are instrumented. Inline accessors (`get: return _x`) are excluded from coverage.

**Member variable declarations** (`var health := 100` at class level) are declarations, not statements — a probe there would be a syntax error. They're excluded from line coverage entirely rather than reported as permanently uncovered.

**Semicolon-separated statements** (`var a = 1; var b = 2; var c = 3`) get one probe per statement. Trailing semicolons don't create phantom statements.

## CI Usage

### PR Coverage Comment (no external services)

Post a coverage summary as a PR comment using just `gh` and `GITHUB_TOKEN`:

```yaml
- name: Run tests
  run: godot --headless --path . -s addons/gut/gut_cmdln.gd

- name: Post coverage comment
  if: always() && github.event_name == 'pull_request'
  run: |
    lcov="coverage.lcov"
    if [ ! -f "$lcov" ]; then exit 0; fi
    total=$(grep -c '^DA:' "$lcov")
    hit=$(grep '^DA:' "$lcov" | grep -cv ',0$')
    scripts=$(grep -c '^SF:' "$lcov")
    pct=$((hit * 100 / total))
    gh pr comment ${{ github.event.pull_request.number }} \
      --body "**Coverage:** ${hit}/${total} lines (${pct}%) across ${scripts} scripts"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Requires `pull-requests: write` permission on the job.

### GitHub Actions with Codecov

```yaml
- name: Run tests with coverage
  run: godot --headless -s addons/gut/gut_cmdln.gd -gexit

- name: Upload coverage
  uses: codecov/codecov-action@v4
  with:
    files: coverage.lcov
    token: ${{ secrets.CODECOV_TOKEN }}
```

### GitHub Actions with Coveralls

```yaml
- name: Upload coverage
  uses: coverallsapp/github-action@v2
  with:
    file: coverage.lcov
```

## Output Format

GUTCheck generates standard LCOV tracefiles with line, function, and branch coverage. Example:

```
TN:
SF:/absolute/path/to/player.gd
FN:5,move
FN:12,take_damage
FNDA:3,move
FNDA:0,take_damage
FNF:2
FNH:1
BRDA:6,0,0,3
BRDA:6,0,1,1
BRDA:9,0,2,0
BRF:3
BRH:2
DA:6,3
DA:7,3
DA:8,3
DA:13,0
DA:14,0
LF:5
LH:3
end_of_record
```

### Cobertura XML

Set `cobertura_output` in `.gutcheck.json` to also generate Cobertura XML:

```json
{
  "cobertura_output": "res://coverage.xml"
}
```

The XML follows the [Cobertura DTD](http://cobertura.sourceforge.net/xml/coverage-04.dtd) and includes line and branch coverage with `condition-coverage` attributes.

### Console Summary

After each test run, GUTCheck prints an npm/jest-style coverage table:

```
GUTCheck: 1069/7562 lines covered (14.1%)
GUTCheck: 1077/2897 branches covered (37.2%)
GUTCheck: 239/700 functions covered (34.1%)

File                                     | % Lines | % Branch | % Funcs | Uncovered Lines
-----------------------------------------|---------|----------|---------|---------------------
scripts/ui/hud.gd                        |    0.0% |     0.0% |    0.0% | 17-22,65-70,75-80...
scripts/systems/npc_system.gd            |    7.9% |    50.8% |   29.0% | 84,87,96-98,103...
scripts/systems/game_manager.gd          |   26.1% |    51.0% |   52.3% | 20-34,40,43,48...
-----------------------------------------|---------|----------|---------|---------------------
All files                                |   14.1% |    37.2% |   34.1% |
```

If a previous LCOV file exists, the summary shows coverage delta (e.g., `+2.5%`).

## Architecture

```
addons/gut_check/
  tokenizer/
    token.gd            # Token class, TokenType enum, keyword/annotation tables
    tokenizer.gd        # Line-oriented GDScript lexer
  parser/
    line_classifier.gd  # Consumes token stream, classifies lines, tracks scopes
    script_map.gd       # ScriptMap container + branch-structure derivation
    line_info.gd        # Per-line classification record
    function_info.gd    # Function / lambda / accessor record
    class_info.gd       # Inner-class record
    branch_info.gd      # Branch (BRDA) record
  instrumenter/
    instrumenter.gd      # Source-to-source transformation orchestration
    probe_injector.gd    # Static string wrappers that inject collector calls
    probe_allocator.gd   # Single authority for probe-ID allocation (inject-time)
    instrument_result.gd # Result struct: source, probe_count, script_map
    script_registry.gd   # Maps script IDs to file paths
  collector/
    coverage_collector.gd  # Static hit counter (PackedInt32Array)
  report/
    coverage_computer.gd   # Coverage math, LCOV parsing, line-range formatting
  export/
    lcov_exporter.gd       # Generates LCOV tracefiles with FN/FNDA/BRDA/DA records
    lcov_merger.gd         # Merges multiple LCOV tracefiles (e.g., parallel test runs)
    cobertura_exporter.gd  # Generates Cobertura XML with line and branch coverage
  hooks/
    pre_run_hook.gd     # GUT pre-run hook (instruments scripts)
    post_run_hook.gd    # GUT post-run hook (exports + summary)
  gut_check.gd          # Facade: config, file discovery, orchestration
  gut_check_plugin.gd   # EditorPlugin registration
```

## Status

Early release

### Known Limitations

- **Inner classes** - Scripts containing inner class definitions (`class Foo` inside another script) are instrumented, but `reload()` creates new type identities for inner classes, which can break typed references in other scripts. GUTCheck attempts instrumentation and rolls back on compile failure. If you see type errors after instrumentation, refactor inner classes to separate files with their own `class_name`.
- **`@tool` scripts** - Scripts marked with `@tool` run in the editor. Instrumenting them can cause unexpected behavior since the modified source executes during editor operations, not just during test runs. Exclude them via `exclude_patterns`.
- **Autoloads** - Autoload singletons are instantiated before the pre-run hook fires. Their `_ready()` and any initialization code runs before instrumentation happens, so that code won't be covered. Methods called later during tests will be covered if the autoload script is in `source_dirs`.
- **`preload()` references** - If script A does `const B = preload("res://b.gd")`, Godot resolves that reference at parse time. The `load()` + `reload()` approach updates the cached script object in place, so preloaded references should pick up the instrumented version. However, if Godot has already compiled and cached the bytecode for A before the hook runs, the reference may point to the original. This has worked in testing but may have edge cases in large projects.
- **Static variables** - GDScript static variables persist across test runs. GUTCheck's own collector uses static state and clears it between runs, but if your instrumented scripts have static variables, their state carries over as it normally would.
- **Typed `for` loops** - Instrumenting a `for` loop wraps its iterable in a collector call, and GDScript can't preserve the iterable's element type through that call — so the loop variable becomes `Variant`. A body that infers a type from it, like `for node in get_children(): var pos := node.position`, then fails to compile (`:=` can't infer from `Variant`). When this happens GUTCheck automatically retries the file with conservative instrumentation (the `for` headers are left un-instrumented and excluded from coverage) so the rest of the file is still measured.
- **Compilation failures** - If instrumentation still produces source that won't compile after the conservative retry, the script is rolled back and skipped: the original source is restored and a warning is logged.
- **Performance** - Each instrumented line adds one static function call. Each branch point adds one call that checks truthiness. Should be negligible for test runs but hasn't been benchmarked beyond ~50 scripts w/ ~900 tests.

## License

MIT
