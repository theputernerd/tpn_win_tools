# ttree

Windows `tree.com` is noisy and can’t exclude project junk properly.  
`ttree` is a Windows-style `tree` replacement that supports real excludes/includes while keeping familiar switches.

Repo layout:

```
scripts\        # app entrypoints (each .py becomes a same-named .exe)
tools\          # build/install launchers and scripts
dist\           # compiled .exe output (PyInstaller --distpath)
build\          # per-app PyInstaller work dirs (--workpath/--specpath)
```

Install layout (user machine):

```
%USERPROFILE%\tpn_apps\
  ttree.exe
  ttree.cmd
  ...
```

`tpn_apps` is prepended to **User PATH** (persistent).

---

## Build + install

From repo root:

```bat
tools\BUILD_AND_INSTALL.cmd
```

What it does:

1) Ensures build deps are installed into the active interpreter (`pip install -r requirements.txt`)
2) Compiles every `scripts\*.py` into `dist\*.exe` (name = script basename)
3) Installs all `dist\*.exe` into `%USERPROFILE%\tpn_apps`
4) Creates `.cmd` wrappers for reliable `cmd.exe` resolution
5) Prepends `%USERPROFILE%\tpn_apps` to **User PATH** (persistent)

After install, open a **new** terminal:

```bat
where ttree
ttree /?
```

---

## Manual build

```bat
pip install -r requirements.txt
tools\compile_all_apps.cmd
```

---

## Manual install

```bat
tools\install_TPM_apps.cmd
```

---
