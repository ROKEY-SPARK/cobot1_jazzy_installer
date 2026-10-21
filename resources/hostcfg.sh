#!/usr/bin/env bash
# =============================================================
#  ROKEY Jazzy Lecture Installer
# =============================================================
#
# shellcheck source-path=SCRIPTDIR
# resources/hostcfg.sh · 설치가 끝난 호스트의 런타임 설정 (협동1 · 협동2 공통)
#   dds     = CycloneDDS XML + 커널 소켓 버퍼 + ~/.bashrc 관리 블록
#   network = 로봇 LAN 유선 NIC 정적 IP (gateway/DNS 없음 → 인터넷은 wifi 유지)
#   원본 = ROKEY-SPARK/cobot2_jazzy_installer resources/hostcfg.sh. 같은 노트북에서 두 설치기가
#          같은 파일 · 같은 bashrc 마커를 쓰므로 어느 쪽을 나중에 돌려도 결과가 같다
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
source "${SCRIPT_DIR}/config.sh"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=./sys.sh
source "${SCRIPT_DIR}/sys.sh"

# 협동2 설치기의 마커 그대로 (옛 이름 마커도 함께 정리)
DDS_BEGIN="# >>> cobot2_jazzy_installer cyclonedds env >>>"
DDS_END="# <<< cobot2_jazzy_installer cyclonedds env <<<"
DDS_LEGACY_BEGIN="# >>> ros2_jazzy_test cyclonedds env >>>"
DDS_LEGACY_END="# <<< ros2_jazzy_test cyclonedds env <<<"

# 마커 쌍이 온전할 때만 지움 (한쪽만 있으면 sed 범위가 파일 끝까지 번짐)
_remove_marker_block() {
    local begin="$1" end="$2" b=0 e=0
    grep -qxF "${begin}" "${BASHRC}" && b=1
    grep -qxF "${end}" "${BASHRC}" && e=1
    [[ ${b} == "${e}" ]] || die "${EXIT_SYSTEM}" "dds: '${begin}' block in ${BASHRC} has only one marker — fix it by hand."
    [[ ${b} == 1 ]] || return 0
    sed -i "\\|^${begin}\$|,\\|^${end}\$|d" "${BASHRC}"
}

# cyclonedds.xml 렌더 = loopback 항상 + DDS_NETIF 로 지정한 외부 NIC
_render_cyclonedds_xml() {
    local nic iface_block
    local -a nics=()
    [[ -n "${DDS_NETIF}" ]] && IFS=',' read -r -a nics <<< "${DDS_NETIF}"
    iface_block='        <NetworkInterface name="lo" priority="default" multicast="true"/>'
    for nic in "${nics[@]}"; do
        [[ "${nic}" == lo ]] && continue
        iface_block+=$'\n'"        <NetworkInterface name=\"${nic}\" presence_required=\"false\"/>"
    done
    mkdir -p "$(dirname "${CYCLONEDDS_XML}")"
    awk -v block="${iface_block}" '$0 == "__DDS_INTERFACES__" { print block; next } { print }' \
        "${SCRIPT_DIR}/templates/cyclonedds.xml.in" > "${CYCLONEDDS_XML}.tmp"
    mv "${CYCLONEDDS_XML}.tmp" "${CYCLONEDDS_XML}"
    echo "[dds] rendered ${CYCLONEDDS_XML} (loopback + ${#nics[@]} external NIC)"
}

# dds [--no-sysctl] · --no-sysctl = /proc/sys 를 못 쓰는 환경 (Docker 빌드)
hostcfg_dds() {
    pkg_installed "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp" || apt_install "ros-${ROS_DISTRO}-rmw-cyclonedds-cpp"
    if [[ "${1:-}" != --no-sysctl ]]; then
        as_root install -m 0644 -o root -g root "${SCRIPT_DIR}/templates/sysctl-cyclonedds.conf" /etc/sysctl.d/60-cyclonedds.conf
        # 우리 파일만 적용 → 다른 sysctl.d 파일의 오류가 결과를 가리지 않음. 적용 후 실제 값 확인
        local want
        want="$(sed -n 's/^net.core.rmem_max *= *//p' "${SCRIPT_DIR}/templates/sysctl-cyclonedds.conf")"
        as_root sysctl -p /etc/sysctl.d/60-cyclonedds.conf >/dev/null 2>&1 || true
        if [[ "$(sysctl -n net.core.rmem_max 2>/dev/null)" == "${want}" ]]; then
            echo "[dds] rmem_max=$(sysctl -n net.core.rmem_max) wmem_max=$(sysctl -n net.core.wmem_max)"
        elif proc_sys_readonly; then
            warn "dds: /proc/sys is read-only here (container) — file installed, applies on next boot."
        else
            die "${EXIT_SYSTEM}" "dds: net.core.rmem_max is $(sysctl -n net.core.rmem_max), expected ${want} after sysctl -p."
        fi
    fi
    _render_cyclonedds_xml
    touch "${BASHRC}"
    _remove_marker_block "${DDS_BEGIN}" "${DDS_END}"
    _remove_marker_block "${DDS_LEGACY_BEGIN}" "${DDS_LEGACY_END}"
    # 손으로 넣었을 수 있는 흩어진 export 정리 (협동2 와 같은 규칙, 줄 맨 앞 export 만)
    sed -i -e '/CycloneDDS receive-buffer tuning for large RealSense topics/d' \
           -e '/default RMW = CycloneDDS for all new shells/d' \
           -e '\#^export CYCLONEDDS_URI=#d' -e '/^export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp/d' "${BASHRC}"
    if [[ -s "${BASHRC}" && -n "$(tail -c1 "${BASHRC}")" ]]; then echo >> "${BASHRC}"; fi
    {
        echo "${DDS_BEGIN}"
        echo "# CycloneDDS standard + large-topic buffer/interface tuning (managed by hostcfg.sh dds, do not edit manually)"
        echo "export RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION_DEFAULT}"
        echo "export CYCLONEDDS_URI=\"file://${CYCLONEDDS_XML}\""
        echo "${DDS_END}"
    } >> "${BASHRC}"
    echo "[dds] ~/.bashrc block updated (RMW_IMPLEMENTATION / CYCLONEDDS_URI)."
}

# 물리 유선 NIC 자동 탐지 (wifi · docker · veth · bridge 제외)
_detect_wired_nic() {
    local path n
    local -a found=()
    for path in /sys/class/net/*; do
        n="$(basename "${path}")"
        case "${n}" in lo|docker*|veth*|br-*|virbr*|bond*|tap*|tun*) continue ;; esac
        [[ -e "${path}/wireless" || ! -e "${path}/device" ]] && continue
        found+=("${n}")
    done
    [[ ${#found[@]} -gt 1 ]] && warn "net: multiple wired NICs (${found[*]}) — using '${found[0]}'. Set HOST_ETH_NETIF to choose."
    [[ ${#found[@]} -gt 0 ]] && echo "${found[0]}"
    return 0
}

# NIC 에 붙은 ethernet 프로필 (활성 → 저장된 것 → 없으면 새로 만듦)
_nm_connection_for() {
    local nic="$1" conn name ifn
    conn="$(nmcli -t -f NAME,DEVICE con show --active 2>/dev/null | awk -F: -v d="${nic}" '$2==d{print $1; exit}')"
    if [[ -z "${conn}" ]]; then
        while IFS= read -r name; do
            [[ -n "${name}" && "$(nmcli -g connection.type con show "${name}" 2>/dev/null)" == 802-3-ethernet ]] || continue
            ifn="$(nmcli -g connection.interface-name con show "${name}" 2>/dev/null)"
            if [[ "${ifn}" == "${nic}" || -z "${ifn}" ]]; then conn="${name}"; break; fi
        done < <(nmcli -t -f NAME con show 2>/dev/null)
    fi
    if [[ -z "${conn}" ]]; then
        conn="${nic}-static"
        nmcli con add type ethernet ifname "${nic}" con-name "${conn}" >/dev/null
    fi
    echo "${conn}"
}

hostcfg_network() {
    command -v nmcli >/dev/null || die "${EXIT_SYSTEM}" "net: no nmcli — not a NetworkManager environment."
    local nic conn
    nic="${HOST_ETH_NETIF:-$(_detect_wired_nic)}"
    if [[ -z "${nic}" ]]; then
        warn "net: no physical wired NIC — skipping. After plugging one in: bash resources/hostcfg.sh network"
        return 0
    fi
    conn="$(_nm_connection_for "${nic}")"
    nmcli con modify "${conn}" connection.interface-name "${nic}" connection.autoconnect yes \
        ipv4.method manual ipv4.addresses "${HOST_ETH_IP}/${HOST_ETH_PREFIX}" \
        ipv4.gateway "" ipv4.dns "" ipv4.never-default yes
    echo "[net] ${conn} (${nic}) = ${HOST_ETH_IP}/${HOST_ETH_PREFIX}, no gateway/DNS, never-default"
    nmcli con up "${conn}" >/dev/null 2>&1 \
        || warn "net: could not activate ${conn} (cable unplugged?) — saved, applies when connected."
}

case "${1:?hostcfg: subcommand required (dds|network)}" in
    dds)     shift; hostcfg_dds "$@" ;;
    network) hostcfg_network ;;
    *) die "${EXIT_SYSTEM}" "hostcfg: unknown subcommand '$1'" ;;
esac
