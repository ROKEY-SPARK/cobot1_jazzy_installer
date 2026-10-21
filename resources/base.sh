#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/base.sh · 협동1 시스템 계층 (협동2 설치기 base 와 같은 값)
#   서브커맨드마다 별도 프로세스 → 한 단계 실패가 다른 단계 상태에 무영향
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

# HWE 커널 meta + headers + 현재 커널 modules-extra (협동2 1단계와 같음)
#   커널 이미지만 깔고 modules-extra 가 없으면 wifi · 일부 USB 입력 드라이버가 빠진 채 부팅
base_kernel() {
    local running
    running="$(uname -r)"
    apt_install --install-recommends "${KERNEL_META}" "${KERNEL_HEADERS_META}"
    if [[ -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]]; then
        apt_install "linux-headers-${running}"
    else
        apt_install "linux-modules-extra-${running}" "linux-headers-${running}"
    fi
    [[ -d "/lib/modules/${running}/kernel/drivers/net/wireless" ]] \
        || warn "kernel: /lib/modules/${running}/.../net/wireless missing — wifi/USB input may be absent."
    echo "kernel: HWE meta + headers + modules-extra ready (running ${running})."
}

# 협동2 의 ros2-extras = DSR 빌드 기반 라이브러리 + robot/control 스택 + Gazebo Harmonic
base_ros2_extras() {
    local d="ros-${ROS_DISTRO}"
    apt_install git libpoco-dev libyaml-cpp-dev dbus-x11 \
        "${d}-control-msgs" "${d}-realtime-tools" "${d}-xacro" "${d}-joint-state-publisher-gui" \
        "${d}-ros2-control" "${d}-ros2-controllers" "${d}-moveit-msgs" \
        "${d}-ament-lint-common" "${d}-yaml-cpp-vendor" "${d}-ros2launch" "${d}-ament-pep257" \
        "${d}-ros-gz"
    echo "ros2-extras: robot/control + Gazebo Harmonic installed."
}

# Docker 엔진 (두산 에뮬레이터 · 강의 컨테이너용) + docker 그룹
base_docker() {
    local arch key="${KEYRING_DIR}/docker.asc"
    arch="$(dpkg --print-architecture)"
    apt_install ca-certificates curl
    add_apt_repo https://download.docker.com/linux/ubuntu/gpg "${key}" \
        /etc/apt/sources.list.d/docker.list \
        "deb [arch=${arch} signed-by=${key}] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
    if pkg_installed docker-ce; then
        echo "docker: docker-ce already installed."
    else
        apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    # 엔진 버전 고정 = 협동2 와 같음 (자동 업그레이드로 에뮬레이터 동작이 바뀌지 않게)
    as_root apt-mark hold docker-ce docker-ce-cli containerd.io >/dev/null
    local user
    user="$(id -un)"
    if [[ "${user}" != root ]] && ! id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
        as_root usermod -aG docker "${user}"
        echo "docker: added ${user} to the docker group (active after re-login/reboot)."
    fi
    as_root docker run --rm hello-world >/dev/null
    docker --version
}

# ROS 저장소 = 협동2 설치기와 같은 키 경로 · 같은 deb 줄 → 같은 노트북에서 두 설치기가 충돌하지 않음
#   (ros2-apt-source 의 ros2.sources 와 함께 있으면 apt 가 "Conflicting values set for option Signed-By" 로 실패)
_ros_source_cobot2_style() {
    local arch key="${KEYRING_DIR}/ros.gpg"
    arch="$(dpkg --print-architecture)"
    add_apt_repo https://raw.githubusercontent.com/ros/rosdistro/master/ros.key "${key}" \
        /etc/apt/sources.list.d/ros2.list \
        "deb [arch=${arch} signed-by=${key}] http://packages.ros.org/ros2/ubuntu ${UBUNTU_CODENAME} main"
}

# ROS2 Jazzy desktop + 개발 도구 (ros-dev-tools = colcon · rosdep · vcstool)
#   이미 ROS 저장소가 잡혀 있으면 (ros2-apt-source 포함) 새로 추가하지 않음
base_ros2() {
    apt_install locales software-properties-common curl
    as_root locale-gen en_US en_US.UTF-8
    as_root update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
    as_root add-apt-repository -y universe
    __APT_UPDATED=0
    apt_update_once
    if ! pkg_installed ros2-apt-source && ! apt-cache policy "ros-${ROS_DISTRO}-ros-base" | grep -q 'Candidate: [0-9]'; then
        _ros_source_cobot2_style
        __APT_UPDATED=0
    fi
    # 협동2 ros2_desktop 과 같은 개발 패키지 묶음 포함
    apt_install "ros-${ROS_DISTRO}-desktop" ros-dev-tools python3-colcon-common-extensions \
        python3-rosdep python3-argcomplete python3-pip git build-essential \
        "ros-${ROS_DISTRO}-ament-package" "ros-${ROS_DISTRO}-ament-cmake" python3-pyqt5 libzmq3-dev python3-colcon-clean
    rosdep_ready
    echo "ros2: ROS 2 ${ROS_DISTRO} desktop installed ($(dpkg-query -W -f='${Version}' "ros-${ROS_DISTRO}-desktop"))."
}

base_vscode() {
    local key="${KEYRING_DIR}/packages.microsoft.gpg" arch
    arch="$(dpkg --print-architecture)"
    apt_install wget gpg apt-transport-https
    add_apt_repo https://packages.microsoft.com/keys/microsoft.asc "${key}" \
        /etc/apt/sources.list.d/vscode.list \
        "deb [arch=${arch} signed-by=${key}] https://packages.microsoft.com/repos/code stable main" dearmor
    apt_install code
    echo "vscode: $(dpkg-query -W -f='${Version}' code)"
}

# NVIDIA Container Toolkit · docker/setup-host.sh 전용 (GPU 있는 PC 에서 컨테이너가 GPU 사용)
base_toolkit() {
    if ! has_nvidia_gpu; then echo "toolkit: no NVIDIA GPU — skipping."; return 0; fi
    local key="${KEYRING_DIR}/nvidia-container-toolkit.gpg"
    local list=/etc/apt/sources.list.d/nvidia-container-toolkit.list line
    apt_install ca-certificates curl gnupg
    line="$(curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed "s#deb https://#deb [signed-by=${key}] https://#g")"
    add_apt_repo https://nvidia.github.io/libnvidia-container/gpgkey "${key}" "${list}" "${line}" dearmor
    apt_install nvidia-container-toolkit
    as_root nvidia-ctk runtime configure --runtime=docker
    as_root systemctl restart docker
    docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"' \
        || as_root docker info --format '{{json .Runtimes}}' | grep -q '"nvidia"' \
        || die "${EXIT_SYSTEM}" "toolkit: nvidia runtime not visible to docker."
    echo "toolkit: docker nvidia runtime registered."
}

case "${1:?base: subcommand required (kernel|docker|ros2|ros2-extras|vscode|toolkit)}" in
    kernel)       base_kernel ;;
    ros2-extras)  base_ros2_extras ;;
    docker)       base_docker ;;
    ros2)         base_ros2 ;;
    vscode)       base_vscode ;;
    toolkit)      base_toolkit ;;
    *) die "${EXIT_SYSTEM}" "base: unknown subcommand '$1'" ;;
esac
