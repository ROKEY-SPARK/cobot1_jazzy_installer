#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# resources/config.sh · source 전용
#   버전 핀 · 경로의 단일 진실 소스
#   distro/OS 핀 = `=` 강제 / 나머지 = `:=` 로 환경변수 override 가능

# --- distro / OS (강제) --------------------------------------------------
export ROS_DISTRO=jazzy
export UBUNTU_CODENAME=noble
export DEBIAN_FRONTEND=noninteractive

# --- 레포 / 상태 / 로그 ----------------------------------------------------
: "${INSTALLER_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${STATE_DIR:=${HOME}/.rokey_jazzy_installer}"
# 상세 로그 = append-only, 레포 루트 install_log (git 추적 제외)
: "${LOG_FILE:=${INSTALLER_ROOT}/install_log}"
: "${KEYRING_DIR:=/etc/apt/keyrings}"
: "${BASHRC:=${HOME}/.bashrc}"

# --- 협동1 = 협동2 설치기와 같은 호스트 기준 (같은 노트북 사용) -----------------
# 값 출처 = ROKEY-SPARK/cobot2_jazzy_installer resources/config.sh. 바꾸면 두 강의가 어긋남
: "${KERNEL_META:=linux-generic-hwe-24.04}"
: "${KERNEL_HEADERS_META:=linux-headers-generic-hwe-24.04}"
export RMW_IMPLEMENTATION_DEFAULT="rmw_cyclonedds_cpp"
: "${CYCLONEDDS_XML:=${XDG_CONFIG_HOME:-${HOME}/.config}/cyclonedds/cyclonedds.xml}"
# DDS 가 쓸 외부 NIC (콤마 구분). 빈 값 = loopback 전용
: "${DDS_NETIF:=}"
# 로봇 LAN 정적 IP: .1 = OnRobot 그리퍼 / .100 = 로봇 컨트롤러 / .30 = host
: "${HOST_ETH_IP:=192.168.1.30}"
: "${HOST_ETH_PREFIX:=24}"
: "${HOST_ETH_NETIF:=}"

# --- 협동1 (Doosan M0609 + OnRobot RG2) -----------------------------------
: "${COBOT1_PJT_DIR:=${HOME}/ws_cobot_pjt}"
: "${COBOT1_WS:=${COBOT1_PJT_DIR}/ws_dsr}"
: "${COBOT1_REPO_URL:=https://github.com/ahnisinc/cobot_rg2.git}"
: "${COBOT1_REPO_REF:=4d5657f36a160eedb533ab1c975cd8a30c3e53b2}"
: "${DSR_EMULATOR_IMAGE:=doosanrobot/dsr_emulator:3.0.1}"
: "${ROBOT_HOST_IP:=192.168.1.100}"
: "${REALSENSE_UDEV_URL:=https://raw.githubusercontent.com/IntelRealSense/librealsense/v2.59.1/config/99-realsense-libusb.rules}"

# --- 자체 점검 --------------------------------------------------------------
config_assert_set() {
    local var missing=0
    for var in ROS_DISTRO UBUNTU_CODENAME STATE_DIR LOG_FILE KEYRING_DIR BASHRC; do
        if [[ -z "${!var:-}" ]]; then
            echo "config: required variable '${var}' is empty" >&2
            missing=1
        fi
    done
    return "${missing}"
}
