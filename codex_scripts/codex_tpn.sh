#!/usr/bin/env bash
set -euo pipefail

# Keep this Codex invocation isolated to the TPN account profile.
export CODEX_HOME="${HOME}/.codex-tpn_bus"

screen_session="${CODEX_SCREEN_NAME:-codex-tpn}"
script_path="${BASH_SOURCE[0]}"

if [[ "${script_path}" != */* ]]; then
  script_path="$(command -v -- "${script_path}")"
elif [[ "${script_path}" != /* ]]; then
  script_dir="$(cd -- "$(dirname -- "${script_path}")" && pwd -P)"
  script_path="${script_dir}/$(basename -- "${script_path}")"
fi

if [[ -z "${STY:-}" ]]; then
  exec screen -D -RR -S "${screen_session}" "${script_path}" "$@"
fi

exec codex --yolo "$@"
