#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SCRIPT="${REPO_ROOT}/scripts/build_and_upload_fir.sh"
TEST_ROOT="$(mktemp -d)"
PROJECT_ROOT="${TEST_ROOT}/project"
FAKE_BIN="${TEST_ROOT}/bin"
CALL_LOG="${TEST_ROOT}/curl.log"

trap 'rm -rf "${TEST_ROOT}"' EXIT

if [[ ! -f "${SOURCE_SCRIPT}" ]]; then
  echo "发布脚本不存在: ${SOURCE_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${PROJECT_ROOT}/scripts" "${FAKE_BIN}"
cp "${SOURCE_SCRIPT}" "${PROJECT_ROOT}/scripts/build_and_upload_fir.sh"
chmod +x "${PROJECT_ROOT}/scripts/build_and_upload_fir.sh"
printf '%s\n' 'version: 1.2.3+4' > "${PROJECT_ROOT}/pubspec.yaml"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$*" != "build apk --release" ]]; then exit 91; fi' \
  'mkdir -p build/app/outputs/flutter-apk' \
  ': > build/app/outputs/flutter-apk/app-release.apk' \
  > "${FAKE_BIN}/flutter"
chmod +x "${FAKE_BIN}/flutter"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%q " "$@" >> "${FIR_TEST_CURL_LOG}"' \
  'printf "\n" >> "${FIR_TEST_CURL_LOG}"' \
  'call_count="$(wc -l < "${FIR_TEST_CURL_LOG}" | tr -d " ")"' \
  'if [[ "${call_count}" == "1" ]]; then' \
  '  printf "%s" "{\"cert\":{\"binary\":{\"upload_url\":\"https://upload.example\",\"key\":\"binary-key\",\"token\":\"binary-token\"}}}"' \
  'elif [[ "${call_count}" == "2" ]]; then' \
  '  printf "%s" "{\"is_completed\":true}"' \
  'else' \
  '  exit 92' \
  'fi' \
  > "${FAKE_BIN}/curl"
chmod +x "${FAKE_BIN}/curl"

if output="$(
  env -u FIR_API_TOKEN -u FIR_BUNDLE_ID \
    PATH="${FAKE_BIN}:${PATH}" \
    FIR_TEST_CURL_LOG="${CALL_LOG}" \
    bash "${PROJECT_ROOT}/scripts/build_and_upload_fir.sh" 2>&1
)"; then
  echo "占位 Token 不应允许上传。" >&2
  exit 1
fi

if [[ "${output}" != *"FIR_API_TOKEN"* ]]; then
  echo "未提示设置 FIR_API_TOKEN: ${output}" >&2
  exit 1
fi

if [[ -e "${CALL_LOG}" ]]; then
  echo "占位 Token 不应调用上传接口。" >&2
  exit 1
fi

FIR_TEST_CURL_LOG="${CALL_LOG}" \
  PATH="${FAKE_BIN}:${PATH}" \
  FIR_API_TOKEN='12345678901234567890123456789012' \
  FIR_BUNDLE_ID='com.example.excel_app' \
  FIR_CHANGELOG='test changelog' \
  bash "${PROJECT_ROOT}/scripts/build_and_upload_fir.sh"

if [[ "$(wc -l < "${CALL_LOG}" | tr -d " ")" != "2" ]]; then
  echo "上传流程必须调用两次 curl。" >&2
  exit 1
fi

if ! rg -q -- '--request POST' "${CALL_LOG}" ||
  ! rg -q 'bundle_id' "${CALL_LOG}" ||
  ! rg -q 'api_token' "${CALL_LOG}"; then
  echo "第一步未按文档请求上传凭证。" >&2
  exit 1
fi

if ! rg -q -- '--form key=binary-key' "${CALL_LOG}" ||
  ! rg -q -- '--form token=binary-token' "${CALL_LOG}" ||
  ! rg -q 'file=@.*/app-release\.apk' "${CALL_LOG}" ||
  ! rg -q -- '--form x:version=1.2.3' "${CALL_LOG}" ||
  ! rg -q -- '--form x:build=4' "${CALL_LOG}"; then
  echo "第二步未按 cert.binary 上传 APK。" >&2
  exit 1
fi

echo "fir.im 两步上传流程校验通过。"
