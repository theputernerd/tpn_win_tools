#!/usr/bin/env python3
"""
ttree.py — a Windows TREE-compatible clone with real excludes/includes.

Defaults (matches Windows tree):
  - Root is current directory (.)
  - Shows directories only
  - Unicode line drawing

TREE-compatible switches:
  /F or -F or --files      Include files
  /A or -A or --ascii      Use ASCII line drawing
  /? or -h or --help       Help

Enhancements:
  /XD or --exclude-dirs <pats...>     Exclude directories (patterns: * % ?)
  /XF or --exclude-files <pats...>    Exclude files (patterns: * % ?)
  /ID or --include-dirs <pats...>     Include directories only (optional)
  /ND /NF or --no-dirs/--no-files     Hide dirs / hide files
  --show-dirs/--show-files            Force on

Pattern rules (basename only, case-insensitive):
  * and % => any chars
  ?       => single char
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional, Tuple


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


def _dir_allowed(name: str, opt: Options) -> bool:
    if _matches_any(name, opt.exclude_dir_pats):
        return False
    if opt.include_dir_pats:
        return _matches_any(name, opt.include_dir_pats)
    return True


def _file_allowed(name: str, opt: Options) -> bool:
    return not _matches_any(name, opt.exclude_file_pats)


def _walk(path: Path, prefix: str, opt: Options, counts: Counts) -> List[str]:
    lines: List[str] = []
    g = _glyphs(opt.ascii)

    try:
        dirs, files = _sorted_entries(path, opt.follow_symlinks)
    except PermissionError:
        return lines

    kept_dirs = [d for d in dirs if _dir_allowed(d.name, opt)]
    kept_files = [f for f in files if opt.show_files and _file_allowed(f.name, opt)]

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


def _preprocess_windows_help(argv: List[str]) -> List[str]:
    return ["-h" if a == "/?" else a for a in argv]


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    if argv is None:
        argv = sys.argv[1:]
    argv = _preprocess_windows_help(argv)

    ap = argparse.ArgumentParser(
        prog="ttree",
        formatter_class=argparse.RawTextHelpFormatter,
        description="by theputernerd (c) 2025. Windows TREE-like output with excludes/includes.",
        prefix_chars="-/"  # <-- CRITICAL: allow /F /A /XD /XF /ID on Windows
    )

    ap.add_argument("path", nargs="?", default=".", help="Root path (default: current directory)")

    ap.add_argument("-F", "--files", "/F", action="store_true", help="Include files (like tree /F)")
    ap.add_argument("-A", "--ascii", "/A", action="store_true", help="Use ASCII (like tree /A)")

    ap.add_argument("/XD", "--exclude-dirs", dest="exclude_dirs", nargs="*", default=[],
                    help="Exclude directories (patterns: * %% ?)")
    ap.add_argument("/XF", "--exclude-files", dest="exclude_files", nargs="*", default=[],
                    help="Exclude files (patterns: * %% ?)")

    ap.add_argument("/ID", "--include-dirs", dest="include_dirs", nargs="*", default=[],
                    help="Include directories only (optional)")

    ap.add_argument("/ND", "--no-dirs", dest="show_dirs", action="store_false", help="Hide directories")
    ap.add_argument("/NF", "--no-files", dest="show_files", action="store_false", help="Hide files")
    ap.add_argument("--show-dirs", dest="show_dirs", action="store_true", help="Show directories")
    ap.add_argument("--show-files", dest="show_files", action="store_true", help="Show files")

    ap.set_defaults(show_dirs=True, show_files=False)

    ap.add_argument("--summary", action="store_true", help="Print counts at end")
    ap.add_argument("--follow-symlinks", action="store_true", help="Follow symlinks/junctions (default: off)")

    ns = ap.parse_args(argv)

    # if /F / --files is set, show_files must be on
    if ns.files:
        ns.show_files = True

    return ns


def main(argv: Optional[List[str]] = None) -> int:
    ns = parse_args(argv)

    opt = Options(
        root=Path(ns.path),
        ascii=bool(ns.ascii),
        show_dirs=bool(ns.show_dirs),
        show_files=bool(ns.show_files),
        exclude_dir_pats=_compile_patterns(ns.exclude_dirs),
        include_dir_pats=_compile_patterns(ns.include_dirs),
        exclude_file_pats=_compile_patterns(ns.exclude_files),
        follow_symlinks=bool(ns.follow_symlinks),
    )

    lines, counts = build_tree(opt)
    for line in lines:
        print(line)

    if ns.summary:
        print()
        print(f"{counts.dirs} directories")
        if opt.show_files:
            print(f"{counts.files} files")

    return 0

def _self_test() -> None:
    """
    Sanity tests for CLI switches.
    Fails fast with AssertionError if anything breaks.
    """

    test_argvs = [
        [],  # default
        ["."],
        ["-A"],
        ["-F"],
        ["--files"],
        ["--ascii"],
        ["/A"],
        ["/F"],
        ["/?"],
        ["--exclude-dirs", ".venv", ".git"],
        ["/XD", ".venv", ".git"],
        ["--exclude-files", "*.pyd", "*.dll"],
        ["/XF", "*.pyd", "*.dll"],
        ["--include-dirs", "src", "tests"],
        ["/ID", "src", "tests"],
        ["--no-dirs"],
        ["--no-files"],
        ["/ND"],
        ["/NF"],
        ["--show-files"],
        ["--show-dirs"],
        ["-F", "-A", "--exclude-dirs", ".venv"],
        ["/F", "/A", "/XD", ".venv", "/XF", "*.pyc"],
    ]

    for argv in test_argvs:
        try:
            ns = parse_args(argv)
        except SystemExit:
            # argparse exits on help; that is acceptable
            if "/?" in argv or "-h" in argv or "--help" in argv:
                continue
            raise AssertionError(f"parse_args crashed on argv={argv}")

        # basic invariants
        assert isinstance(ns.show_dirs, bool), f"show_dirs not bool for {argv}"
        assert isinstance(ns.show_files, bool), f"show_files not bool for {argv}"
        assert isinstance(ns.ascii, bool), f"ascii not bool for {argv}"

        # if files requested, show_files must be True
        if "-F" in argv or "--files" in argv or "/F" in argv:
            assert ns.show_files is True, f"/F did not enable show_files for {argv}"

        # build tree should not crash
        try:
            opt = Options(
                root=Path("."),
                ascii=bool(ns.ascii),
                show_dirs=bool(ns.show_dirs),
                show_files=bool(ns.show_files),
                exclude_dir_pats=_compile_patterns(ns.exclude_dirs),
                include_dir_pats=_compile_patterns(ns.include_dirs),
                exclude_file_pats=_compile_patterns(ns.exclude_files),
                follow_symlinks=False,
            )
            build_tree(opt)
        except Exception as e:
            raise AssertionError(f"build_tree failed for argv={argv}: {e}")

    print("ttree self-test: ALL TESTS PASSED")

if __name__ == "__main__":
    if os.environ.get("TTREE_SELFTEST") == "1":
        _self_test()
    else:
        raise SystemExit(main())