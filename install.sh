#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# install.sh · 협동1 강의 PC 자동 설치 진입점 (Ubuntu 24.04 + ROS 2 Jazzy)
#   협동1 = Doosan M0609 + OnRobot RG2 + DRCF 에뮬레이터 + PyQt HMI
#   단계 순서 = resources/courses.sh / 단계 구현 = resources/<base|hostcfg|cobot1>.sh
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_DIR="${SCRIPT_DIR}/resources"

# shellcheck source=resources/config.sh
source "${RESOURCE_DIR}/config.sh"
# shellcheck source=resources/lib.sh
source "${RESOURCE_DIR}/lib.sh"
# shellcheck source=resources/sys.sh
source "${RESOURCE_DIR}/sys.sh"
# shellcheck source=resources/courses.sh
source "${RESOURCE_DIR}/courses.sh"

usage() {
    cat <<'EOF'
Usage: bash install.sh [options]

Installs the 협동1 (cobot1) lecture PC: the same host base as the 협동2 installer minus GPU
(HWE kernel, Docker, ROS 2, CycloneDDS tuning, robot-LAN static IP, one reboot) + M0609/RG2
workspace, DRCF emulator, RealSense SDK, PyQt HMI, FastDDS tools.

Options:
  --domain-id N      write 'export ROS_DOMAIN_ID=N' into the cobot1 ~/.bashrc block (team ID)
  --no-kernel        skip the HWE kernel baseline step
  --no-static-ip     skip the robot-LAN static IP (192.168.1.30/24 on the wired NIC)
  --no-reboot        do not reboot at step 5 (reboot yourself before using the robot)
  -y, --yes          answer yes to confirmations (needed in a non-interactive shell)
  -v, --verbose      also print each step's detailed output to the console
  --dry-run          print the steps that would run; change nothing

Commands (instead of installing):
  --status           print which steps are done
  --verify           check the installed result (read-only)
  --reset            forget the install progress (asks first; installed files are kept)
  -h, --help         this help

Finished steps are skipped on a re-run. The installer reboots once at step 5 and resumes by itself
after the GUI login (like the 협동2 installer). Detailed log: ./install_log
Exit codes: 0 success, 1 user error (bad option, missing input), 2 system error (step failed).
Other lectures: 협동2 https://github.com/ROKEY-SPARK/cobot2_jazzy_installer
                협동3 https://github.com/ROKEY-SPARK/cobot3_jazzy_installer
                지능1 https://github.com/ROKEY-SPARK/int1_jazzy_installer
EOF
}

# 이 저장소 = 협동1 하나. state 파일 이름 (cobot1.state) 과 autostart 항목 이름이 이 값을 쓴다
COURSE=cobot1
CMD=install
OPT_DOMAIN_ID=""
OPT_NO_KERNEL=0
OPT_NO_STATIC_IP=0
OPT_NO_REBOOT=0
RESUMED=0
ASSUME_YES=0
VERBOSE="${VERBOSE:-0}"
DRY_RUN=0

# 다른 강의 이름을 주면 그 강의 저장소를 알려 준다
other_course() {
    local repo
    case "$1" in
        cobot2) repo=cobot2_jazzy_installer ;;
        cobot3) repo=cobot3_jazzy_installer ;;
        *)      repo=int1_jazzy_installer ;;
    esac
    die "${EXIT_USER}" "this repo installs cobot1 (협동1) only. For $1 use https://github.com/ROKEY-SPARK/${repo}"
}

need_value() { [[ -n "${2:-}" && "${2}" != -* ]] || die "${EXIT_USER}" "$1 needs a value (see --help)"; }

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            cobot1) ;;   # 예전 호출 형식 (bash install.sh cobot1 ...) 호환
            cobot2|cobot3|intel1|int1) other_course "$1" ;;
            --domain-id)      need_value "$1" "${2:-}"; OPT_DOMAIN_ID="$2"; shift ;;
            --no-kernel)      OPT_NO_KERNEL=1 ;;
            --no-static-ip)   OPT_NO_STATIC_IP=1 ;;
            --no-reboot)      OPT_NO_REBOOT=1 ;;
            --resumed)        RESUMED=1 ;;   # 내부용: 재부팅 후 autostart 가 붙임
            -y|--yes)         ASSUME_YES=1 ;;
            -v|--verbose)     VERBOSE=1 ;;
            --dry-run)        DRY_RUN=1 ;;
            --status|--verify|--reset) CMD="${1#--}" ;;
            -h|--help)        usage; exit 0 ;;
            *) echo "install: unknown argument '$1'" >&2; usage >&2; exit "${EXIT_USER}" ;;
        esac
        shift
    done
    if [[ -n "${OPT_DOMAIN_ID}" ]] && ! [[ "${OPT_DOMAIN_ID}" =~ ^[0-9]+$ && "${OPT_DOMAIN_ID}" -le 232 ]]; then
        die "${EXIT_USER}" "--domain-id must be an integer 0..232 (got '${OPT_DOMAIN_ID}')"
    fi
    export ASSUME_YES VERBOSE DRY_RUN
}

preflight() {
    [[ "${EUID}" -ne 0 ]] || die "${EXIT_USER}" "do not run with sudo — run 'bash install.sh' as your user (it calls sudo itself)."
    local codename
    # os-release 도 UBUNTU_CODENAME 을 정의 → 서브셸에서 읽어 config 값을 덮지 않게 함
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    # shellcheck disable=SC2031  # 위 서브셸의 UBUNTU_CODENAME 은 의도적으로 버림
    [[ "${codename}" == "${UBUNTU_CODENAME}" ]] \
        || die "${EXIT_USER}" "this installer targets Ubuntu 24.04 (${UBUNTU_CODENAME}); current: '${codename:-unknown}'."
    config_assert_set || die "${EXIT_SYSTEM}" "config incomplete"
    mkdir -p "$(dirname "${LOG_FILE}")"
}

# 재부팅 뒤 GUI autostart 전용 (도움말 미노출): 설치를 이어 돌리고 결과를 볼 수 있게 터미널 유지
resume_terminal() {
    local rc=0
    cd "${SCRIPT_DIR}"
    bash "${SCRIPT_DIR}/install.sh" --resumed "$@" || rc=$?
    echo
    echo "[resume] install.sh exited (${rc}). This terminal stays open so you can read the result."
    stty sane 2>/dev/null || true
    exec bash
}

# 5단계에서 재부팅 → 시작 때 autostart 를 미리 등록 (협동2 와 같음)
prepare_resume() {
    [[ "${DRY_RUN}" == 0 && "${OPT_NO_REBOOT}" == 0 ]] || return 0
    step_is_done reboot && return 0
    register_resume_autostart "${SCRIPT_DIR}/install.sh" "${ORIG_ARGS[@]}"
}

main() {
    [[ "${1:-}" == --resume-terminal ]] && { shift; resume_terminal "$@"; }
    ORIG_ARGS=("$@")
    parse_args "$@"
    # 재개된 실행 = autostart 를 바로 지움 (one-shot). 여기서 실패하면 같은 명령을 직접 다시 실행
    [[ "${RESUMED}" == 1 ]] && remove_resume_autostart
    case "${CMD}" in
        status) state_dump; exit 0 ;;
        verify) exec bash "${RESOURCE_DIR}/verify.sh" ;;
        reset)
            confirm_or_abort "Forget the ${COURSE} progress in $(state_file)? (installed files are kept)"
            rm -f "$(state_file)"; remove_resume_autostart; echo "install: ${COURSE} progress reset."; exit 0 ;;
    esac
    preflight
    echo "== ROKEY Jazzy installer: ${COURSE} (log: ${LOG_FILE})"
    if [[ "${DRY_RUN}" == 0 ]]; then
        # 재부팅 후 재개된 실행은 시작 때 이미 동의를 받았으므로 다시 묻지 않음
        [[ "${RESUMED}" == 1 ]] || confirm_or_abort "Install the ${COURSE} lecture environment (apt packages, ~/.bashrc block, reboots once at step 5)?"
        sudo_prime
    fi
    prepare_resume
    trap 'echo "[install] failed at line ${LINENO} — see ${LOG_FILE}" >&2' ERR
    plan_cobot1
    echo
    echo "install: ${COURSE} done. Open a new terminal (or 'source ~/.bashrc'). Re-check anytime: bash install.sh --verify"
}

main "$@"
