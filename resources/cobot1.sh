#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/cobot1.sh · 협동1 (Doosan M0609 + OnRobot RG2 + DRCF 에뮬레이터)
#   근거 = 협동1 노션 강의안 "rg2 그리퍼를 포함한 Simulator 설치" · ".bashrc 구성" ·
#          "PyQt 간단 사용법" · "FastDDS Discovery Server" + ahnisinc/cobot_rg2 README
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

# cobot_rg2 README 의 요구 패키지 (pymodbus 3.6.9 = noble apt 버전과 일치 → pip 대신 apt)
cobot1_deps() {
    apt_install libpoco-dev \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-realsense2-camera" "ros-${ROS_DISTRO}-realsense2-description" \
        "ros-${ROS_DISTRO}-ros-gz" "ros-${ROS_DISTRO}-hardware-interface" \
        "ros-${ROS_DISTRO}-ros2-control" "ros-${ROS_DISTRO}-ros2-controllers" \
        python3-pymodbus
    python3 -c 'import pymodbus; print("cobot1: pymodbus", pymodbus.__version__)'
}

# RealSense SDK (커널 모듈 + 유틸 + 헤더) = 협동2 app-install realsense-sdk 와 같은 저장소 · 패키지
cobot1_realsense_sdk() {
    local key="${KEYRING_DIR}/librealsenseai.gpg"
    # 옛 Intel 키/소스 잔재 제거 (협동2 와 같음)
    as_root rm -f /etc/apt/sources.list.d/librealsense.list "${KEYRING_DIR}/librealsense.pgp"
    apt_install curl ca-certificates gnupg apt-transport-https "${KERNEL_HEADERS_META}" "linux-headers-$(uname -r)"
    add_apt_repo https://librealsense.realsenseai.com/Debian/librealsenseai.asc "${key}" \
        /etc/apt/sources.list.d/librealsenseai.list \
        "deb [signed-by=${key}] https://librealsense.realsenseai.com/Debian/apt-repo ${UBUNTU_CODENAME} main" dearmor
    apt_install librealsense2-dkms librealsense2-utils librealsense2-dev librealsense2-dbg
    echo "cobot1: librealsense2 $(dpkg-query -W -f='${Version}' librealsense2-utils)"
}

# 강사 디렉토리 구조 + 강의대로 저장소를 ws_dsr/src 자리에 clone
cobot1_workspace() {
    mkdir -p "${COBOT1_PJT_DIR}"/{DartPlatform,backend/app,docker,docs,frontend,ws_cobot1/src,ws_cobot1/doc}
    mkdir -p "${COBOT1_WS}"
    git_clone_pinned "${COBOT1_REPO_URL}" "${COBOT1_WS}/src" "${COBOT1_REPO_REF}"
    [[ -f "${COBOT1_WS}/src/rg2/m0609_rg2_bringup/package.xml" ]] \
        || die "${EXIT_SYSTEM}" "cobot1: m0609_rg2_bringup missing in ${COBOT1_WS}/src"
}

cobot1_rosdep() {
    ros_source
    rosdep_ready
    cd "${COBOT1_WS}"
    # 강의 = `-r` (실패해도 계속). -r 은 apt 실패까지 숨김 → 알려진 ROS1 잔재 키만 건너뛰고 나머지는 실패로 둠
    rosdep install --from-paths src --ignore-src --rosdistro "${ROS_DISTRO}" -y \
        --skip-keys "message_runtime message_generation"
}

# install_emulator.sh 와 같은 일 = 에뮬레이터 이미지 pull (docker 그룹 미적용 상태 대비 as_root)
cobot1_emulator() {
    command -v docker >/dev/null || die "${EXIT_SYSTEM}" "cobot1: docker missing — run the docker step first."
    if as_root docker image inspect "${DSR_EMULATOR_IMAGE}" >/dev/null 2>&1; then
        echo "cobot1: ${DSR_EMULATOR_IMAGE} already pulled."
    else
        as_root docker pull "${DSR_EMULATOR_IMAGE}"
    fi
}

cobot1_build() {
    ros_source
    cd "${COBOT1_WS}"
    colcon build
    local imp="${COBOT1_WS}/install/dsr_common2/lib/dsr_common2/imp"
    [[ -d "${imp}" ]] || die "${EXIT_SYSTEM}" "cobot1: ${imp} missing — PYTHONPATH target of the lecture .bashrc."
    [[ -d "${COBOT1_WS}/install/m0609_rg2_bringup" ]] || die "${EXIT_SYSTEM}" "cobot1: m0609_rg2_bringup not built."
    echo "cobot1: workspace built at ${COBOT1_WS}"
}

# 실기 모드 사전 조건 (README "Real 모드 사전 조건" · "RealSense udev rules")
cobot1_hostcfg() {
    echo 'net.ipv4.ip_unprivileged_port_start=0' | as_root tee /etc/sysctl.d/99-ros2-doosan.conf >/dev/null
    as_root sysctl -w net.ipv4.ip_unprivileged_port_start=0 \
        || warn "cobot1: sysctl apply failed (container?) — applies on next boot."
    as_root curl -fsSL "${REALSENSE_UDEV_URL}" -o /etc/udev/rules.d/99-realsense-libusb.rules
    if command -v udevadm >/dev/null && [[ -d /run/udev ]]; then
        as_root udevadm control --reload-rules && as_root udevadm trigger
    else
        echo "cobot1: udev not running here — rules apply on next boot."
    fi
}

# 강의 중 쓰는 도구 · HMI(PyQt + Qt Designer) · FastDDS Discovery · Dart-Simulator(VirtualBox) · 웹
#   --no-virtualbox = 컨테이너처럼 커널 모듈을 올릴 수 없는 환경
cobot1_extras() {
    local -a pkgs=(terminator python3-pyqt5 pyqt5-dev-tools qttools5-dev-tools fastdds-tools
                   python3-fastapi python3-uvicorn nodejs npm)
    [[ "${1:-}" == --no-virtualbox ]] || pkgs+=(virtualbox)
    apt_install "${pkgs[@]}"
    python3 -c 'from PyQt5 import uic, QtWidgets; print("cobot1: PyQt5 OK")'
    echo "cobot1: Dart-Simulator VM = download from the lecture Drive link, unzip into ${COBOT1_PJT_DIR}/DartPlatform, open DART-Simulator.vbox."
}

# 강의 .bashrc 구성 (ROS_DOMAIN_ID 는 조별 값 → --domain-id 로 받음, 없으면 주석으로 남김)
cobot1_bashrc() {
    # 인자가 없으면 기존 블록 값을 유지 (재실행 때 조별 ID 가 지워지지 않게)
    local domain="${1:-$(bashrc_block_domain_id cobot1)}" line rendered
    if [[ -n "${domain}" ]]; then
        line="export ROS_DOMAIN_ID=${domain}"
    else
        line="# export ROS_DOMAIN_ID=<조별 ID>   # 예) 10 — bash install.sh --domain-id N 로 설정"
    fi
    rendered="$(mktemp)"
    render_template "${SCRIPT_DIR}/templates/cobot1.bashrc" "${rendered}" \
        "WS=${COBOT1_WS}" "DOMAIN_LINE=${line}" "ROBOT_IP=${ROBOT_HOST_IP}"
    bashrc_block_write cobot1 "${rendered}"
    rm -f "${rendered}"
    echo "cobot1: ~/.bashrc block updated (open a new terminal or 'source ~/.bashrc')."
}

case "${1:?cobot1: subcommand required (deps|realsense-sdk|workspace|rosdep|emulator|build|hostcfg|extras|bashrc)}" in
    realsense-sdk) cobot1_realsense_sdk ;;
    deps)      cobot1_deps ;;
    workspace) cobot1_workspace ;;
    rosdep)    cobot1_rosdep ;;
    emulator)  cobot1_emulator ;;
    build)     cobot1_build ;;
    hostcfg)   cobot1_hostcfg ;;
    extras)    shift; cobot1_extras "$@" ;;
    bashrc)    shift; cobot1_bashrc "$@" ;;
    *) die "${EXIT_SYSTEM}" "cobot1: unknown subcommand '$1'" ;;
esac
