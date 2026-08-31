#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIR_API_TOKEN="${FIR_API_TOKEN:-588cdfd5f45635e3338b79d5b66f50bf}"
FIR_BUNDLE_ID="${FIR_BUNDLE_ID:-com.example.excel_app}"
FIR_API_URL="${FIR_API_URL:-http://api.appmeta.cn/apps}"
APK_PATH="${PROJECT_ROOT}/build/app/outputs/flutter-apk/app-release.apk"
ICON_PATH="${FIR_ICON_PATH:-${PROJECT_ROOT}/assets/branding/acbio_icon_1024.png}"

if [[ -z "${FIR_API_TOKEN}" || "${FIR_API_TOKEN}" == "YOUR_FIR_API_TOKEN" ]]; then
  echo "请设置 FIR_API_TOKEN 后再上传 fir.im。" >&2
  exit 1
fi
if [[ "${#FIR_API_TOKEN}" -ne 32 ]]; then
  echo "FIR_API_TOKEN 必须是 fir.im 提供的 32 位令牌。" >&2
  exit 1
fi
if [[ -z "${FIR_BUNDLE_ID}" || "${FIR_BUNDLE_ID}" == "YOUR_ANDROID_BUNDLE_ID" ]]; then
  echo "请设置 FIR_BUNDLE_ID 后再上传 fir.im。" >&2
  exit 1
fi

command -v flutter >/dev/null 2>&1 || {
  echo "未找到 flutter 命令。" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "未找到 curl 命令。" >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "未找到 python3 命令，用于解析上传凭证。" >&2
  exit 1
}

if [[ ! -f "${ICON_PATH}" ]]; then
  echo "未找到应用图标: ${ICON_PATH}" >&2
  exit 1
fi

cd "${PROJECT_ROOT}"
flutter build apk --release

if [[ ! -f "${APK_PATH}" ]]; then
  echo "未找到构建产物: ${APK_PATH}" >&2
  exit 1
fi

PUBSPEC_VERSION="$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)"
FIR_VERSION="${FIR_VERSION:-${PUBSPEC_VERSION%%+*}}"
FIR_BUILD="${FIR_BUILD:-${PUBSPEC_VERSION#*+}}"
if [[ -z "${FIR_BUILD}" || "${FIR_BUILD}" == "${PUBSPEC_VERSION}" ]]; then
  FIR_BUILD="$(date +%Y%m%d%H%M%S)"
fi

REQUEST_BODY="$(FIR_API_TOKEN="${FIR_API_TOKEN}" FIR_BUNDLE_ID="${FIR_BUNDLE_ID}" python3 - <<'PY'
import json
import os

print(json.dumps({
    'type': 'android',
    'bundle_id': os.environ['FIR_BUNDLE_ID'],
    'api_token': os.environ['FIR_API_TOKEN'],
}))
PY
)"

if ! CREDENTIALS="$(curl --fail --silent --show-error \
  --request POST "${FIR_API_URL}" \
  --header "Content-Type: application/json" \
  --data "${REQUEST_BODY}")"; then
  echo "获取上传凭证失败，请检查 FIR_API_TOKEN 和 FIR_BUNDLE_ID。" >&2
  exit 1
fi

CREDENTIAL_FIELDS="$(CREDENTIALS="${CREDENTIALS}" python3 - <<'PY'
import json
import os

cert = json.loads(os.environ['CREDENTIALS'])['cert']
icon = cert['icon']
binary = cert['binary']
print('\t'.join(
    icon[key] for key in ('upload_url', 'key', 'token')
) + '\t' + '\t'.join(
    binary[key] for key in ('upload_url', 'key', 'token')
))
PY
)"
IFS=$'\t' read -r ICON_UPLOAD_URL ICON_UPLOAD_KEY ICON_UPLOAD_TOKEN \
  UPLOAD_URL UPLOAD_KEY UPLOAD_TOKEN <<< "${CREDENTIAL_FIELDS}"

if ! curl --fail --silent --show-error \
  --request POST \
  --form "key=${ICON_UPLOAD_KEY}" \
  --form "token=${ICON_UPLOAD_TOKEN}" \
  --form "file=@${ICON_PATH}" \
  "${ICON_UPLOAD_URL}" >/dev/null; then
  echo "上传应用图标失败，请检查 cert.icon 上传凭证和网络连接。" >&2
  exit 1
fi

if ! UPLOAD_RESPONSE="$(curl --fail --silent --show-error \
  --request POST \
  --form "key=${UPLOAD_KEY}" \
  --form "token=${UPLOAD_TOKEN}" \
  --form "file=@${APK_PATH}" \
  --form "x:name=${FIR_APP_NAME:-excel_app}" \
  --form "x:version=${FIR_VERSION}" \
  --form "x:build=${FIR_BUILD}" \
  --form "x:changelog=${FIR_CHANGELOG:-$(git log -1 --pretty=%s)}" \
  "${UPLOAD_URL}")"; then
  echo "上传 APK 失败，请检查 cert.binary 上传凭证和网络连接。" >&2
  exit 1
fi

if ! UPLOAD_RESPONSE="${UPLOAD_RESPONSE}" python3 - <<'PY'
import json
import os
import sys

try:
    completed = json.loads(os.environ['UPLOAD_RESPONSE']).get('is_completed') is True
except (TypeError, json.JSONDecodeError):
    completed = False
sys.exit(0 if completed else 1)
PY
then
  echo "fir.im 上传未完成: ${UPLOAD_RESPONSE}" >&2
  exit 1
fi

echo "fir.im 上传完成。"
