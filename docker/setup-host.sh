#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# docker/setup-host.sh · 협동1 컨테이너를 돌릴 호스트 준비 (Docker 엔진 + NVIDIA Container Toolkit)
#   사용: bash docker/setup-host.sh [--yes]
#   GPU 는 선택. NVIDIA GPU 가 없으면 toolkit 단계는 건너뜀 (드라이버 = 협동2 설치기가 설치)
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=resources/config.sh
source "${ROOT}/resources/config.sh"
# shellcheck source=resources/lib.sh
source "${ROOT}/resources/lib.sh"

case "${1:-}" in
    -y|--yes) export ASSUME_YES=1 ;;
    -h|--help) sed -n '6,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    "") ;;
    *) die "${EXIT_USER}" "setup-host: unknown option $1" ;;
esac
[[ "${EUID}" -ne 0 ]] || die "${EXIT_USER}" "run as your user (sudo is called when needed)."
confirm_or_abort "Install Docker Engine + NVIDIA Container Toolkit on this host (restarts the docker daemon)?"
sudo_prime
bash "${ROOT}/resources/base.sh" docker || exit "${EXIT_SYSTEM}"
bash "${ROOT}/resources/base.sh" toolkit || exit "${EXIT_SYSTEM}"
echo "setup-host: done. Re-login once so the docker group applies, then: bash docker/build.sh"
