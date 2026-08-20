#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
package_dir="${script_dir:h}"
project_dir="${package_dir:h}"
app_dir="${project_dir}/artifacts/Work Rhythm V0.app"

swift build --package-path "${package_dir}"
mkdir -p "${app_dir}/Contents/MacOS"
cp "${package_dir}/.build/debug/WorkRhythmV0" "${app_dir}/Contents/MacOS/WorkRhythmV0"
cp "${package_dir}/Resources/DebugInfo.plist" "${app_dir}/Contents/Info.plist"
open "${app_dir}"
