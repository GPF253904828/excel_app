#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${REPO_ROOT}/scripts/build_and_upload_fir.sh"

if [[ ! -f "${SCRIPT_PATH}" ]]; then
  echo "发布脚本不存在: ${SCRIPT_PATH}" >&2
  exit 1
fi

if output="$(
  FIR_API_TOKEN=YOUR_FIR_API_TOKEN \
    FIR_BUNDLE_ID=YOUR_ANDROID_BUNDLE_ID \
    bash "${SCRIPT_PATH}" 2>&1
)"; then
  echo "占位 token 不应允许上传。" >&2
  exit 1
fi

if [[ "${output}" != *"FIR_API_TOKEN"* ]]; then
  echo "未提示设置 FIR_API_TOKEN: ${output}" >&2
  exit 1
fi

echo "占位 token 校验通过。"
