#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/verify.sh · 설치 결과 점검 (읽기 전용 — 시스템을 바꾸지 않음)
#   사용: bash resources/verify.sh [--no-docker] [--no-kernel] [--no-static-ip] [--no-host]
#         --no-* = 그 항목이 없는 환경(컨테이너 이미지 등)에서 해당 점검 생략
#   종료 코드 = 0 전부 통과 / 2 하나 이상 실패
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

PASSED=0
FAILED=0
SKIP_DOCKER=0
SKIP_KERNEL=0
SKIP_STATIC_IP=0
# 호스트 전용 항목 (커널 · 정적 IP · sysctl · RealSense dkms) = 컨테이너 이미지에서는 없음
SKIP_HOST=0

# check <설명> <명령...> · 명령 출력은 숨기고 결과만 한 줄
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASSED=$((PASSED + 1)); echo "  [PASS] ${desc}"
    else
        FAILED=$((FAILED + 1)); echo "  [FAIL] ${desc}"
    fi
}

# ROS 환경을 올린 새 셸에서 명령 실행 (현재 셸 env 오염 방지)
# ros_has_pkg <overlay-setup.bash|""> <pkg>
ros_has_pkg() {
    bash -c 'set +u; source /opt/ros/jazzy/setup.bash; [ -n "$1" ] && [ -f "$1" ] && source "$1"; ros2 pkg prefix "$2"' _ "$1" "$2"
}

# 저장된 NetworkManager 프로필 중 하나라도 로봇 LAN 주소를 가지면 통과 (주소 여러 개 = ", " 구분)
static_ip_configured() {
    local c
    while IFS= read -r c; do
        nmcli -g ipv4.addresses con show "${c}" 2>/dev/null | tr ',' '\n' | tr -d ' ' \
            | grep -qxF "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" && return 0
    done < <(nmcli -t -f NAME con show 2>/dev/null)
    return 1
}

# 부팅된 커널 = /lib/modules 의 가장 새 커널 (HWE 설치 후 재부팅 여부)
booted_newest_kernel() {
    [[ "$(uname -r)" == "$(find /lib/modules -mindepth 1 -maxdepth 1 -printf '%f\n' | grep -E '^[0-9]' | sort -V | tail -n1)" ]]
}

bashrc_has_block() { grep -qx "# >>> rokey $1 >>>" "${BASHRC}"; }

check_common() {
    echo "== common"
    check "Ubuntu ${UBUNTU_CODENAME}" grep -q "VERSION_CODENAME=${UBUNTU_CODENAME}" /etc/os-release
    check "ROS 2 ${ROS_DISTRO} desktop" pkg_installed "ros-${ROS_DISTRO}-desktop"
    check "rosdep initialized" test -e /etc/ros/rosdep/sources.list.d/20-default.list
}

# 협동2 설치기와 같은 호스트 기준 (같은 노트북)
check_cobot1_base() {
    echo "== cobot1 base (same as 협동2 host)"
    if [[ "${SKIP_KERNEL}" == 0 ]]; then
        check "HWE kernel meta ${KERNEL_META}" pkg_installed "${KERNEL_META}"
        check "booted into the newest installed kernel (reboot done)" booted_newest_kernel
    fi
    check "ros2_control + controllers" pkg_installed "ros-${ROS_DISTRO}-ros2-controllers"
    check "Gazebo Harmonic (ros_gz)" pkg_installed "ros-${ROS_DISTRO}-ros-gz"
    check "CycloneDDS RMW" pkg_installed "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    check "cyclonedds.xml" python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "${CYCLONEDDS_XML}"
    check "bashrc cyclonedds block (협동2 marker)" grep -qx "# >>> cobot2_jazzy_installer cyclonedds env >>>" "${BASHRC}"
    if [[ "${SKIP_HOST}" == 0 ]]; then
        check "sysctl 60-cyclonedds.conf" test -f /etc/sysctl.d/60-cyclonedds.conf
        proc_sys_readonly || check "net.core.rmem_max applied" test "$(sysctl -n net.core.rmem_max 2>/dev/null)" = \
            "$(sed -n 's/^net.core.rmem_max *= *//p' "${SCRIPT_DIR}/templates/sysctl-cyclonedds.conf")"
        check "RealSense SDK (rs-enumerate-devices)" command -v rs-enumerate-devices
    fi
    [[ "${SKIP_DOCKER}" == 1 ]] || check "docker-ce held" bash -c 'apt-mark showhold | grep -qx docker-ce'
    if [[ "${SKIP_STATIC_IP}" == 0 ]] && command -v nmcli >/dev/null; then
        check "robot LAN profile ${HOST_ETH_IP}/${HOST_ETH_PREFIX}" static_ip_configured
    fi
}

check_cobot1() {
    local ov="${COBOT1_WS}/install/setup.bash"
    check_cobot1_base
    echo "== cobot1"
    check "workspace cloned (${COBOT1_WS}/src)" test -f "${COBOT1_WS}/src/rg2/m0609_rg2_bringup/package.xml"
    check "package m0609_rg2_bringup" ros_has_pkg "${ov}" m0609_rg2_bringup
    check "package dsr_bringup2" ros_has_pkg "${ov}" dsr_bringup2
    check "package dsr_example2 (dance)" ros_has_pkg "${ov}" dsr_example
    check "package rokey" ros_has_pkg "${ov}" rokey
    check "DSR_ROBOT2 import path (PYTHONPATH imp)" test -f "${COBOT1_WS}/install/dsr_common2/lib/dsr_common2/imp/DSR_ROBOT2.py"
    check "pymodbus import" python3 -c 'import pymodbus'
    check "PyQt5 uic import" python3 -c 'from PyQt5 import uic'
    check "Qt Designer" command -v designer
    check "fastdds CLI" command -v fastdds
    check "terminator" command -v terminator
    check "realsense udev rule" test -f /etc/udev/rules.d/99-realsense-libusb.rules
    if [[ "${SKIP_DOCKER}" == 0 ]]; then
        check "docker engine" command -v docker
        check "DSR emulator image ${DSR_EMULATOR_IMAGE}" as_root docker image inspect "${DSR_EMULATOR_IMAGE}"
    fi
    check "bashrc cobot1 block" bashrc_has_block cobot1
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            cobot1) ;;   # 예전 호출 형식 (강의 이름 인자) 호환
            --no-gpu) ;;   # 예전 호출 호환. 협동1 은 GPU 드라이버를 깔지 않아 점검하지 않음 (협동2 설치기 몫)
            --no-docker) SKIP_DOCKER=1 ;;
            --no-kernel) SKIP_KERNEL=1 ;;
            --no-static-ip) SKIP_STATIC_IP=1 ;;
            --no-host) SKIP_HOST=1; SKIP_KERNEL=1; SKIP_STATIC_IP=1 ;;
            *) die "${EXIT_USER}" "verify: unknown option $1" ;;
        esac
        shift
    done
    check_common
    check_cobot1
    echo "---- ${PASSED} passed, ${FAILED} failed"
    [[ ${FAILED} -eq 0 ]] || exit "${EXIT_SYSTEM}"
}

main "$@"
