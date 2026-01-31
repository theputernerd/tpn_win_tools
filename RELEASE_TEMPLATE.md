## tpn_win_tools {{VERSION}} - Windows CLI tools bundle

### Quick start
1. Download the .exe files from the release assets.
2. Place them on your PATH.
3. Run from a command prompt (for example: `ttree --help`).

### What this is
tpn_win_tools is a small set of standalone Windows utilities built from Python entry points.
The bundle produces native .exe tools that can be added to the user PATH for command-line use.

### Who it is for
Windows users who want simple, portable CLI tools without needing to install Python or manage dependencies.

---

### Included tools
| Tool | Version | Source |
| --- | --- | --- |
{{TOOLS}}

---

### Tool details
Each tool section includes version, examples, and latest release notes.

{{TOOLS_DETAIL}}

---

### Install tips
- Optional local install: run `BUILD_AND_INSTALL.cmd` from repo root.
- PATH install: place EXEs in a folder on PATH and restart the terminal.


<details>
<summary>Release notes</summary>

{{BUNDLE_NOTES}}
</details>

<details>
<summary>Checksums</summary>

```
{{CHECKSUMS}}
```
</details>

<details>
<summary>Build notes</summary>
---

Built from tag {{TAG}} on {{DATE}} using PyInstaller. Verify downloaded binaries against checksums.
</details>
