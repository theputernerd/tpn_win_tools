  v0.3.7
  - Build discovers tools in both scripts\tool.py and scripts\tool\tool.py
  - Per-tool requirements and python-version pins supported
  - Shared per-version build envs (.venv_pyX.Y) with isolated fallback on conflicts
  - Tool docs split into per-tool READMEs; root README now covers maintenance and release flow
  - Git ignore updated for per-version venv