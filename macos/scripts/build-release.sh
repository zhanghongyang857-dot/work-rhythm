#!/bin/zsh
set -euo pipefail

release_version="${1:-}"
build_number="${2:-}"

if [[ -z "${release_version}" || -z "${build_number}" ]]; then
  print "用法: $(basename "$0") <版本号，例如 0.1.0> <构建号，例如 1>"
  exit 1
fi

if [[ ! "${release_version}" =~ ^[0-9]+(\.[0-9]+){0,2}$ || ! "${build_number}" =~ ^[0-9]+$ ]]; then
  print "版本号必须是 0.1.0 形式，构建号必须是正整数。"
  exit 1
fi

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
project_dir="${package_dir:h}"
release_dir="${project_dir}/artifacts/releases/v${release_version}"
app_dir="${release_dir}/Work Rhythm.app"
zip_path="${release_dir}/Work-Rhythm-macOS.zip"

if [[ -e "${release_dir}" ]]; then
  print "发布目录已存在：${release_dir}"
  print "为保护已有产物，脚本不会覆盖它。请使用新的版本号。"
  exit 1
fi

swift build --package-path "${package_dir}" -c release --product WorkRhythmV0

mkdir -p "${app_dir}/Contents/MacOS"
cp "${package_dir}/.build/release/WorkRhythmV0" "${app_dir}/Contents/MacOS/WorkRhythm"
cp "${package_dir}/Resources/ReleaseInfo.plist" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${release_version}" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build_number}" "${app_dir}/Contents/Info.plist"

ditto -c -k --sequesterRsrc --keepParent "${app_dir}" "${zip_path}"
shasum -a 256 "${zip_path}" > "${zip_path}.sha256"

print "发布包已生成：${zip_path}"
print "校验文件已生成：${zip_path}.sha256"
