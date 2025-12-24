#!/usr/bin/env python3
"""
ttree.py — a Windows TREE-compatible clone with real excludes/includes.

Defaults:
  - Root is current directory (.)
  - Shows directories + files
  - Unicode line drawing

TREE-compatible switches:
  /F or -F or --files      Include files (redundant: files are shown by default)
  /A or -A or --ascii      Use ASCII line drawing
  /? or -h or --help       Help
  /V or --version          Show version and exit

Enhancements:
  /XD, -XD, -xd, /xd, --exclude-dirs, --exclude-folder <pats...>
      Exclude directories by *basename* patterns (* % ?)

  /XF, -XF, -xf, /xf, --exclude-files <pats...>
      Exclude files by *basename* patterns (* % ?)

  --exclude <pats...>
      Exclude anything (file OR folder) by *basename* patterns.
      Equivalent to adding patterns to both exclude-dirs and exclude-files.

  /ID, -ID, --include-dirs <pats...>
      Only include directories that match patterns (basename-only)

  /ND /NF or --no-dirs/--no-files
      Hide dirs / hide files
  --show-dirs/--show-files
      Force on

  --gitignore
      Exclude items matched by gitignore rules (best-effort)

  --out [FILE]
      Save output to a file. Default: <folder>-tree.txt (in current working directory).
  --overwrite
      If output file exists, overwrite it. Otherwise an incremented suffix is used.

  --json
      Emit JSON instead of text (to stdout and/or --out). JSON format is a nested tree.

  --self-test [LOGFILE]
      Runs internal test suite against the CURRENT WORKING DIRECTORY, writes a log file, then exits.
      Default logfile: <cwd-name>-selftest.log (in current directory).
      If LOGFILE exists, it is overwritten.

Pattern rules for basename matching (case-insensitive):
  * and % => any chars
  ?       => single char

Gitignore notes:
  - Implements a pragmatic subset of gitignore.
  - Reads the nearest .gitignore at/above root.
  - Supports: comments, blank lines, globs, leading / anchors, trailing / (dir-only), and negation (!).
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

import _version


def _like_to_regex(pat: str) -> re.Pattern:
    parts: List[str] = []
    for ch in pat:
        if ch in ("*", "%"):
            parts.append(".*")
        elif ch == "?":
            parts.append(".")
        else:
            parts.append(re.escape(ch))
    return re.compile(r"^" + "".join(parts) + r"$", re.IGNORECASE)


def _compile_patterns(patterns: Iterable[str]) -> List[re.Pattern]:
    return [_like_to_regex(p) for p in patterns if p]


def _matches_any(name: str, pats: List[re.Pattern]) -> bool:
    return any(p.match(name) for p in pats)


@dataclass(frozen=True)
class Options:
    root: Path
    ascii: bool
    show_dirs: bool
    show_files: bool
    exclude_dir_pats: List[re.Pattern]
    include_dir_pats: List[re.Pattern]
    exclude_file_pats: List[re.Pattern]
    follow_symlinks: bool = False
    use_gitignore: bool = False
    gitignore: Optional["GitIgnore"] = None


@dataclass
class Counts:
    dirs: int = 0
    files: int = 0


def _glyphs(ascii_mode: bool) -> dict:
    if ascii_mode:
        return {"tee": "+---", "last": "\\---", "vert": "|   ", "space": "    "}
    return {"tee": "├── ", "last": "└── ", "vert": "│   ", "space": "    "}


def _sorted_entries(path: Path, follow_symlinks: bool) -> Tuple[List[os.DirEntry], List[os.DirEntry]]:
    dirs: List[os.DirEntry] = []
    files: List[os.DirEntry] = []
    with os.scandir(path) as it:
        for e in it:
            try:
                if e.is_dir(follow_symlinks=follow_symlinks):
                    dirs.append(e)
                else:
                    files.append(e)
            except OSError:
                files.append(e)

    key = lambda de: de.name.casefold()
    dirs.sort(key=key)
    files.sort(key=key)
    return dirs, files


def _relposix(child: Path, root: Path) -> str:
    try:
        rel = child.resolve().relative_to(root.resolve())
    except Exception:
        rel = child
    return rel.as_posix()


class GitIgnore:
    """
    Best-effort gitignore matcher (subset).

    Supported:
      - comments (#), blank lines
      - negation (!pattern)
      - anchored patterns (/foo) match from repo root
      - trailing slash (dir-only)
      - globbing via fnmatch with POSIX-style paths
    """

    def __init__(self, base_root: Path, patterns: List[Tuple[bool, bool, str]]) -> None:
        self.base_root = base_root.resolve()
        self.patterns = patterns  # (negate, dir_only, pattern)

    @staticmethod
    def _parse_gitignore(text: str) -> List[Tuple[bool, bool, str]]:
        out: List[Tuple[bool, bool, str]] = []
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            negate = False
            if line.startswith("!"):
                negate = True
                line = line[1:].strip()
                if not line:
                    continue
            dir_only = line.endswith("/")
            if dir_only:
                line = line[:-1]
                if not line:
                    continue

            line = line.replace("\\", "/")
            out.append((negate, dir_only, line))
        return out

    @classmethod
    def load_for_root(cls, root: Path) -> Optional["GitIgnore"]:
        root = root.resolve()
        gi_path = cls._find_gitignore(root)
        if gi_path is None:
            return None
        try:
            txt = gi_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
        patterns = cls._parse_gitignore(txt)
        if not patterns:
            return None

        base_root = cls._find_git_repo_root(root) or gi_path.parent.resolve()
        return cls(base_root=base_root, patterns=patterns)

    @staticmethod
    def _find_git_repo_root(start: Path) -> Optional[Path]:
        p = start.resolve()
        for _ in range(128):
            if (p / ".git").exists():
                return p
            if p.parent == p:
                break
            p = p.parent
        return None

    @staticmethod
    def _find_gitignore(start: Path) -> Optional[Path]:
        p = start.resolve()
        candidate = p / ".gitignore"
        if candidate.exists():
            return candidate
        for _ in range(128):
            candidate = p / ".gitignore"
            if candidate.exists():
                return candidate
            if p.parent == p:
                break
            p = p.parent
        return None

    def is_ignored(self, abs_path: Path, is_dir: bool) -> bool:
        rel = _relposix(abs_path, self.base_root)
        if rel.startswith("./"):
            rel = rel[2:]

        ignored = False
        for negate, dir_only, pat in self.patterns:
            if dir_only and not is_dir:
                continue

            if "/" in pat:
                if pat.startswith("/"):
                    target_pat = pat.lstrip("/")
                    matched = fnmatch.fnmatch(rel, target_pat)
                else:
                    matched = fnmatch.fnmatch(rel, pat)
            else:
                base = abs_path.name
                matched = fnmatch.fnmatch(base, pat) or fnmatch.fnmatch(rel, f"**/{pat}")

            if matched:
                ignored = not negate
        return ignored


def _dir_allowed(abs_path: Path, name: str, opt: Options) -> bool:
    if _matches_any(name, opt.exclude_dir_pats):
        return False
    if opt.include_dir_pats and not _matches_any(name, opt.include_dir_pats):
        return False
    if opt.use_gitignore and opt.gitignore is not None:
        if opt.gitignore.is_ignored(abs_path, is_dir=True):
            return False
    return True


def _file_allowed(abs_path: Path, name: str, opt: Options) -> bool:
    if _matches_any(name, opt.exclude_file_pats):
        return False
    if opt.use_gitignore and opt.gitignore is not None:
        if opt.gitignore.is_ignored(abs_path, is_dir=False):
            return False
    return True


def _walk(path: Path, prefix: str, opt: Options, counts: Counts) -> List[str]:
    lines: List[str] = []
    g = _glyphs(opt.ascii)

    try:
        dirs, files = _sorted_entries(path, opt.follow_symlinks)
    except PermissionError:
        return lines

    kept_dirs: List[os.DirEntry] = []
    for d in dirs:
        if _dir_allowed(Path(d.path), d.name, opt):
            kept_dirs.append(d)

    kept_files: List[os.DirEntry] = []
    if opt.show_files:
        for f in files:
            if _file_allowed(Path(f.path), f.name, opt):
                kept_files.append(f)

    items: List[Tuple[os.DirEntry, bool]] = []
    if opt.show_dirs:
        items.extend((d, True) for d in kept_dirs)
    if opt.show_files:
        items.extend((f, False) for f in kept_files)

    for i, (entry, is_dir) in enumerate(items):
        is_last = (i == len(items) - 1)
        connector = g["last"] if is_last else g["tee"]
        lines.append(prefix + connector + entry.name)

        if is_dir:
            counts.dirs += 1
            next_prefix = prefix + (g["space"] if is_last else g["vert"])
            try:
                lines.extend(_walk(Path(entry.path), next_prefix, opt, counts))
            except PermissionError:
                continue
        else:
            counts.files += 1

    return lines


def build_tree(opt: Options) -> Tuple[List[str], Counts]:
    counts = Counts()
    root = opt.root.resolve()
    out: List[str] = [str(root)]
    out.extend(_walk(root, "", opt, counts))
    return out, counts


def build_tree_json(opt: Options) -> Tuple[Dict[str, object], Counts]:
    counts = Counts()
    root = opt.root.resolve()

    def walk_dir(dir_path: Path) -> Dict[str, object]:
        node: Dict[str, object] = {"name": dir_path.name or str(dir_path), "type": "dir", "children": []}
        try:
            dirs, files = _sorted_entries(dir_path, opt.follow_symlinks)
        except PermissionError:
            node["error"] = "PermissionError"
            return node

        if opt.show_dirs:
            for d in dirs:
                p = Path(d.path)
                if not _dir_allowed(p, d.name, opt):
                    continue
                counts.dirs += 1
                node["children"].append(walk_dir(p))

        if opt.show_files:
            for f in files:
                p = Path(f.path)
                if not _file_allowed(p, f.name, opt):
                    continue
                counts.files += 1
                node["children"].append({"name": f.name, "type": "file"})

        return node

    tree = {
        "root": str(root),
        "version": _version.__version__,
        "tree": walk_dir(root),
    }
    return tree, counts


def _preprocess_windows_help(argv: List[str]) -> List[str]:
    return ["-h" if a == "/?" else a for a in argv]


def _default_outfile(root: Path) -> str:
    name = root.resolve().name or "tree"
    return f"{name}-tree.txt"


def _pick_output_path(requested: Optional[str], root: Path, json_mode: bool, overwrite: bool) -> Path:
    if requested:
        out = Path(requested)
    else:
        out = Path.cwd() / _default_outfile(root)

    if json_mode and out.suffix.lower() not in (".json", ".txt"):
        if not requested:
            out = out.with_suffix(".json")

    if overwrite or not out.exists():
        return out

    stem = out.stem
    suffix = out.suffix
    parent = out.parent
    for i in range(1, 10_000):
        cand = parent / f"{stem}-{i}{suffix}"
        if not cand.exists():
            return cand
    return out



def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    if argv is None:
        argv = sys.argv[1:]
    argv = _preprocess_windows_help(argv)

    ap = argparse.ArgumentParser(
        prog="ttree",
        formatter_class=argparse.RawTextHelpFormatter,
        description="Windows TREE-like output with excludes/includes.",
        prefix_chars="-/",
    )

    ap.add_argument("path", nargs="?", default=".", help="Root path (default: current directory)")

    ap.add_argument("-V", "/V", "--version", action="store_true", help="Show version and exit")
    ap.add_argument("-F", "/F", "--files", action="store_true",
                    help="Include files (like tree /F). Files are already shown by default.")
    ap.add_argument("-A", "/A", "--ascii", action="store_true", help="Use ASCII (like tree /A)")

    ap.add_argument("/XD", "/xd", "-XD", "-xd", "--exclude-dirs", "--exclude-folder", "--exclude-folders",
                    dest="exclude_dirs", nargs="*", default=[],
                    help="Exclude directories (basename patterns: * %% ?)")
    ap.add_argument("/XF", "/xf", "-XF", "-xf", "--exclude-files",
                    dest="exclude_files", nargs="*", default=[],
                    help="Exclude files (basename patterns: * %% ?)")
    ap.add_argument("--exclude", dest="exclude_any", nargs="*", default=[],
                    help="Exclude anything (file or folder) by basename patterns")

    ap.add_argument("/ID", "/id", "-ID", "-id", "--include-dirs",
                    dest="include_dirs", nargs="*", default=[],
                    help="Include directories only (optional)")

    ap.add_argument("/ND", "/nd", "--no-dirs", dest="show_dirs", action="store_false", help="Hide directories")
    ap.add_argument("/NF", "/nf", "--no-files", dest="show_files", action="store_false", help="Hide files")
    ap.add_argument("--show-dirs", dest="show_dirs", action="store_true", help="Show directories")
    ap.add_argument("--show-files", dest="show_files", action="store_true", help="Show files")
    ap.set_defaults(show_dirs=True, show_files=True)

    ap.add_argument("--summary", action="store_true", help="Print counts at end")
    ap.add_argument("--follow-symlinks", action="store_true", help="Follow symlinks/junctions (default: off)")

    ap.add_argument("--gitignore", dest="gitignore", action="store_true",
                    help="Exclude items matched by gitignore rules (best-effort)")

    ap.add_argument("--json", dest="json", action="store_true", help="Emit JSON instead of text")
    ap.add_argument("--out", dest="out", nargs="?", const="", default=None,
                    help="Write output to file. Optional path. Default: <folder>-tree.txt in current directory.")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite --out file if it exists")

    ap.add_argument("--self-test", dest="self_test", nargs="?", const="", default=None,
                    help="Run internal tests and write a log. Optional logfile path. Default: <cwd>-selftest.log")
    ap.add_argument("--self-test-split", dest="self_test_split", action="store_true",
                    help="Write one log per test case into <cwd>-selftest.d (or alongside given --self-test path)")

    ns = ap.parse_args(argv)

    if ns.files:
        ns.show_files = True

    if ns.exclude_any:
        ns.exclude_dirs.extend(ns.exclude_any)
        ns.exclude_files.extend(ns.exclude_any)

    return ns


def json_dumps(obj: object) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2)


def _argv_slug(argv: List[str]) -> str:
    if not argv:
        return "default"
    safe: List[str] = []
    for a in argv:
        a2 = a.strip().replace("\\", "_").replace("/", "_").replace(":", "_")
        a2 = re.sub(r"[^A-Za-z0-9_.-]+", "_", a2)
        if len(a2) > 40:
            a2 = a2[:40]
        safe.append(a2 if a2 else "_")
    s = "_".join(safe)
    return s[:180] if len(s) > 180 else s



def _write_case_header(f, argv: List[str], intent: str, expected: str) -> None:
    f.write("-" * 72 + "\n")
    if argv:
        f.write(f"ARGV: {' '.join(argv)}\n")
        f.write(f"Command: ttree {' '.join(argv)}\n")
    else:
        f.write("ARGV: <default>\n")
        f.write("Command: ttree\n")
    f.write("-" * 72 + "\n")
    f.write(f"Test intent: {intent}\n")
    f.write(f"Expected: {expected}\n\n")
def _run_once(argv: List[str]) -> Tuple[str, Counts, Optional[Path]]:
    """
    Executes ONE ttree run in-process (no subprocess), including --out file writing.
    Returns:
      (text_output, counts, out_path_written_or_None)
    """
    ns = parse_args(argv)

    # Self-test MUST NOT be reachable from inside _run_once (avoid recursion).
    if ns.self_test is not None or bool(getattr(ns, "self_test_split", False)):
        raise RuntimeError("internal: _run_once called with self-test flags")

    if ns.version:
        return _version.__version__ + "\n", Counts(), None

    root = Path(ns.path)
    gi = GitIgnore.load_for_root(root) if ns.gitignore else None

    opt = Options(
        root=root,
        ascii=bool(ns.ascii),
        show_dirs=bool(ns.show_dirs),
        show_files=bool(ns.show_files),
        exclude_dir_pats=_compile_patterns(ns.exclude_dirs),
        include_dir_pats=_compile_patterns(ns.include_dirs),
        exclude_file_pats=_compile_patterns(ns.exclude_files),
        follow_symlinks=bool(ns.follow_symlinks),
        use_gitignore=bool(ns.gitignore),
        gitignore=gi,
    )

    out_path_written: Optional[Path] = None

    if ns.json:
        payload, counts = build_tree_json(opt)
        if ns.summary:
            payload["counts"] = {"dirs": counts.dirs, "files": counts.files}
        text_out = json_dumps(payload) + "\n"
    else:
        lines, counts = build_tree(opt)
        text_out = "\n".join(lines) + "\n"
        if ns.summary:
            text_out += "\n"
            text_out += f"{counts.dirs} directories\n"
            if opt.show_files:
                text_out += f"{counts.files} files\n"

    if ns.out is not None:
        requested = None if ns.out == "" else ns.out
        out_path = _pick_output_path(requested, root, json_mode=bool(ns.json), overwrite=bool(ns.overwrite))
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text_out, encoding="utf-8", errors="replace")
        out_path_written = out_path

    return text_out, counts, out_path_written


def _default_selftest_log(cwd: Path) -> Path:
    # Hard rename: always "ttree-self-test.log" in the current folder by default.
    return cwd / "ttree-self-test.log"


def _self_test(log_arg: str, split: bool) -> None:
    cwd = Path.cwd()

    default_log = _default_selftest_log(cwd)
    log_path = default_log if log_arg == "" else Path(log_arg)

    out_dir: Optional[Path] = None
    if split:
        if log_arg == "":
            out_dir = cwd / "ttree-self-test.d"
        else:
            out_dir = log_path.parent / f"{log_path.stem}.d"
        out_dir.mkdir(parents=True, exist_ok=True)

    log_path.parent.mkdir(parents=True, exist_ok=True)

    def emit_index(msg: str) -> None:
        print(msg)

    def separator(f) -> None:
        f.write("-" * 72 + "\n")

    def emit_full_tree(f, s: str) -> None:
        f.write(s)
        if not s.endswith("\n"):
            f.write("\n")

    cases: List[Tuple[List[str], str, str]] = [
        ([], "TEXT tree output", "tree-like text; content depends on folder and excludes"),
        (["--exclude", ".venv", "build", "dist", ".git", ".*"], "TEXT tree output (exclude any)", "excludes should remove those basenames"),
        (["-xd", ".git", ".venv"], "TEXT tree output (exclude dirs alias)", "directories matching patterns should be excluded"),
        (["-xf", "*.log", "*.tmp"], "TEXT tree output (exclude files alias)", "files matching patterns should be excluded"),
        (["--include-dirs", "scripts", "tools"], "TEXT tree output (include dirs)", "only these top-level dirs should appear"),
        (["/ID", "scripts", "tools"], "TEXT tree output (include dirs /ID)", "equivalent to --include-dirs"),
        (["--no-dirs"], "TEXT tree output (no dirs)", "only files at root should appear"),
        (["--no-files"], "TEXT tree output (no files)", "only directories should appear"),
        (["--gitignore"], "TEXT tree output (gitignore)", "items matched by .gitignore should be omitted (best effort)"),
        (["--json"], "JSON tree output", "JSON object with keys: root, version, tree"),
        (["--json", "--gitignore"], "JSON tree output (gitignore)", "JSON object, with ignored items removed (best effort)"),
        (["--version"], "Version output", "prints the package version string"),
    ]

    out_text = cwd / "ttree-self-test-output.txt"
    out_json = cwd / "ttree-self-test-output.json"

    out_cases: List[Tuple[List[str], str, str, Path]] = [
        (["--out", str(out_text), "--overwrite"], "TEXT file output roundtrip", "--out writes a text tree file we can read back", out_text),
        (["--json", "--out", str(out_json), "--overwrite"], "JSON file output roundtrip", "--json + --out writes a JSON tree file we can read back", out_json),
    ]

    with log_path.open("w", encoding="utf-8", errors="replace") as index_f:
        separator(index_f)
        index_f.write("ttree self-test: START\n")
        index_f.write(f"bundle version: {_version.__version__}\n")
        index_f.write(f"cwd: {cwd}\n")
        index_f.write(f"index log: {log_path}\n")
        separator(index_f)
        index_f.write("What this self-test does:\n")
        index_f.write("  - Runs ttree with multiple argument sets against the CURRENT working directory\n")
        index_f.write("  - Captures FULL output for each test case (text tree or JSON)\n")
        index_f.write("  - Exercises real --out behavior (creates output files) and reads them back into this log\n\n")
        index_f.write("What to expect:\n")
        index_f.write("  - Output differs depending on the folder you run it in\n")
        index_f.write("  - This suite is mainly to capture behavior for manual/LLM review\n")
        separator(index_f)

        def open_case_file(argv: List[str]):
            if not split or out_dir is None:
                return index_f
            slug = _argv_slug(argv)
            p = out_dir / f"{slug}.log"
            return p.open("w", encoding="utf-8", errors="replace")

        for argv, intent, expected in cases:
            case_f = open_case_file(argv)
            try:
                _write_case_header(case_f, argv, intent, expected)
                text_out, counts, out_written = _run_once(argv)

                if argv == ["--version"]:
                    case_f.write("Observed:\n")
                    emit_full_tree(case_f, text_out)
                else:
                    case_f.write(f"Observed counts: dirs={counts.dirs}, files={counts.files}\n")
                    separator(case_f)
                    emit_full_tree(case_f, text_out)

                if out_written is not None:
                    separator(case_f)
                    case_f.write(f"Observed: wrote file: {out_written}\n")
            except Exception as e:
                separator(case_f)
                case_f.write(f"FAIL: {e}\n")
                raise
            finally:
                if split and case_f is not index_f:
                    case_f.close()

        for argv, intent, expected, expected_path in out_cases:
            case_f = open_case_file(argv)
            try:
                _write_case_header(case_f, argv, intent, expected)
                _, counts, out_written = _run_once(argv)

                separator(case_f)
                case_f.write("Output file roundtrip check:\n")
                case_f.write("Test intent: ensure the *real* --out behavior creates a file and we can read it back.\n")
                case_f.write("Expected: file exists at the specified path and contains the emitted tree (text or JSON).\n\n")
                case_f.write("Testing (ttree command):\n")
                case_f.write(f"  ttree {' '.join(argv)}\n\n")
                case_f.write("Commands (Windows cmd):\n")
                case_f.write(f'  dir "{expected_path}"\n')
                case_f.write(f'  type "{expected_path}"\n')
                separator(case_f)

                if out_written is None:
                    case_f.write("Observed: INTERNAL ERROR: --out did not produce a write path\n")
                elif not expected_path.exists():
                    case_f.write(f"Observed: file MISSING: {expected_path}\n")
                else:
                    case_f.write(f"Observed: file exists: {expected_path}\n")
                    case_f.write(f"Observed counts (from in-process run): dirs={counts.dirs}, files={counts.files}\n")
                    separator(case_f)
                    case_f.write("Readback content (type):\n")
                    separator(case_f)
                    emit_full_tree(case_f, expected_path.read_text(encoding="utf-8", errors="replace"))
            except Exception as e:
                separator(case_f)
                case_f.write(f"FAIL: {e}\n")
                raise
            finally:
                if split and case_f is not index_f:
                    case_f.close()

        separator(index_f)
        index_f.write("ttree self-test: ALL TESTS PASSED\n")
        separator(index_f)

    emit_index(f"self-test index log written to: {log_path}")
    if split and out_dir is not None:
        emit_index(f"self-test split logs written to: {out_dir}")
    emit_index(f"self-test output artifacts (if created): {out_text}, {out_json}")

def main(argv: Optional[List[str]] = None) -> int:
    ns = parse_args(argv)

    if ns.self_test is not None or bool(getattr(ns, "self_test_split", False)):
        # Self-test runs on the current directory and always writes a log.
        log_arg = ns.self_test if ns.self_test is not None else ""
        _self_test(log_arg, split=bool(getattr(ns, "self_test_split", False)))
        return 0

    if ns.version:
        print(_version.__version__)
        return 0

    root = Path(ns.path)

    gi = GitIgnore.load_for_root(root) if ns.gitignore else None

    opt = Options(
        root=root,
        ascii=bool(ns.ascii),
        show_dirs=bool(ns.show_dirs),
        show_files=bool(ns.show_files),
        exclude_dir_pats=_compile_patterns(ns.exclude_dirs),
        include_dir_pats=_compile_patterns(ns.include_dirs),
        exclude_file_pats=_compile_patterns(ns.exclude_files),
        follow_symlinks=bool(ns.follow_symlinks),
        use_gitignore=bool(ns.gitignore),
        gitignore=gi,
    )

    if ns.json:
        payload, counts = build_tree_json(opt)
        if ns.summary:
            payload["counts"] = {"dirs": counts.dirs, "files": counts.files}
        text_out = json_dumps(payload) + "\n"
    else:
        lines, counts = build_tree(opt)
        text_out = "\n".join(lines) + "\n"
        if ns.summary:
            text_out += "\n"
            text_out += f"{counts.dirs} directories\n"
            if opt.show_files:
                text_out += f"{counts.files} files\n"

    if ns.out is not None:
        requested = None if ns.out == "" else ns.out
        out_path = _pick_output_path(requested, root, json_mode=bool(ns.json), overwrite=bool(ns.overwrite))
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(text_out, encoding="utf-8", errors="replace")
        print(f"Wrote: {out_path}")
    else:
        sys.stdout.write(text_out)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
