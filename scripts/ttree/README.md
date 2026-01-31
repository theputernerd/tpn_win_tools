# ttree

`ttree` is a Windows-style replacement for `tree.com` with real exclusion rules, JSON output,
and a self-test mode designed for inspection by humans or LLMs.

## Usage

From source:

```bat
python ttree.py
python ttree.py --help
```

After build/install:

```bat
ttree
ttree --help
```

## What it does

- Produces a directory tree of the current folder (or a given path)
- Supports basename-based excludes and includes
- Supports gitignore-aware traversal
- Emits text or JSON
- Can write output to files safely
- Includes a self-test mode that logs real command behavior

## Defaults

```bat
ttree
```

- Root: current directory
- Directories and files shown
- Unicode tree drawing
- Output to stdout

## Windows compatibility switches

| Switch | Meaning |
|------|--------|
| `/F` `-F` `--files` | Include files (already default) |
| `/A` `-A` `--ascii` | ASCII tree drawing |
| `/?` `-h` `--help` | Help |
| `/V` `-V` `--version` | Print version and exit |

## Exclusion and inclusion rules

Matching is basename-only, case-insensitive, using `*`, `%`, `?`.

### Exclude directories

```bat
ttree /XD .git .venv build dist
ttree -xd .git .venv
ttree --exclude-dirs .git .venv
ttree --exclude-folder .git .venv
```

### Exclude files

```bat
ttree /XF *.pyc *.log
ttree -xf *.tmp
ttree --exclude-files *.dll
```

### Exclude anything (files and folders)

```bat
ttree --exclude .git .venv build dist .*
```

### Include directories only

```bat
ttree --include-dirs scripts tools
ttree /ID scripts tools
```

## Showing or hiding content

| Switch | Effect |
|-----|-------|
| `--no-dirs` `/ND` | Hide directories |
| `--no-files` `/NF` | Hide files |
| `--show-dirs` | Force directories on |
| `--show-files` | Force files on |

## Gitignore support

```bat
ttree --gitignore
```

Best-effort subset of gitignore rules.

## Output control

### Write output to default file

```bat
ttree --out
```

Creates `<folder>-tree.txt` in the current directory.

### Specify output file

```bat
ttree --out mytree.txt
```

### Overwrite output file

```bat
ttree --out mytree.txt --overwrite
```

## JSON output

```bat
ttree --json
ttree --json --out tree.json
```

JSON includes `version` (tool) and `bundle_version` (package).

## Summary counts

```bat
ttree --summary
```

## Self-test mode

### Run self-test

```bat
ttree --self-test
```

- Runs real `ttree` invocations
- Exercises excludes, includes, gitignore, JSON, and `--out`
- Writes a full inspection log

Default log file:

```
ttree-self-test.log
```

### Split logs per test

```bat
ttree --self-test-split
```

Creates a per-test log directory alongside the index log.

## Build and install

From repo root:

```bat
BUILD_AND_INSTALL.cmd
```

Compiles, installs, and adds `ttree` to the user PATH.

## Versioning

- Tool version stored in `scripts\ttree\VERSION`
- Exposed via `ttree --version` (embedded at build time)
- Embedded in JSON output and self-test logs (tool + bundle)
- Release notes in `scripts\ttree\RELEASE_NOTES.md`
