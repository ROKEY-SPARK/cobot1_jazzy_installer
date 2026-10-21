#!/usr/bin/env bash
# tests/test_templates.sh · 협동1 ~/.bashrc 블록 · CycloneDDS 설정 렌더 결과 검사
#   cobot1.sh bashrc · hostcfg.sh dds 서브커맨드를 격리된 HOME 에서 실제로 실행한다

_block() { sed -n "/^# >>> rokey $1 >>>\$/,/^# <<< rokey $1 <<<\$/p" "${BASHRC}"; }

test_cobot1_block_matches_lecture_aliases() {
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc 10 >/dev/null
    blk="$(_block cobot1)"
    bash -n <<<"${blk}"
    assert_contains "${blk}" "export ROS_DOMAIN_ID=10"
    assert_contains "${blk}" "alias sod='source ${HOME}/ws_cobot_pjt/ws_dsr/install/setup.bash'"
    assert_contains "${blk}" "mode:=virtual host:=127.0.0.1 port:=12345 model:=m0609"
    assert_contains "${blk}" "mode:=real host:=192.168.1.100 port:=12345 model:=m0609"
    assert_contains "${blk}" "install/dsr_common2/lib/dsr_common2/imp"
}

test_cobot1_block_without_domain_leaves_comment() {
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc >/dev/null
    blk="$(_block cobot1)"
    assert_contains "${blk}" "# export ROS_DOMAIN_ID=<조별 ID>"
    if grep -q '^export ROS_DOMAIN_ID' <<<"${blk}"; then echo "unexpected active ROS_DOMAIN_ID"; return 1; fi
}

# 같은 노트북에 다른 강의 설치기 블록이 있어도 협동1 블록만 바뀐다
test_cobot1_block_keeps_other_lecture_blocks() {
    printf '# >>> rokey cobot3 >>>\nexport ROS_DOMAIN_ID=50\n# <<< rokey cobot3 <<<\n' > "${BASHRC}"
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc >/dev/null
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc 20 >/dev/null
    assert_eq "$(grep -c '^# >>> rokey ' "${BASHRC}")" "2"
    assert_contains "$(_block cobot3)" "export ROS_DOMAIN_ID=50"
    assert_contains "$(_block cobot1)" "export ROS_DOMAIN_ID=20"
}

test_rerun_without_domain_id_keeps_previous_value() {
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc 30 >/dev/null
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc >/dev/null
    assert_contains "$(_block cobot1)" "export ROS_DOMAIN_ID=30"
}

test_cobot1_pythonpath_has_no_leading_colon_when_unset() {
    bash "${INSTALLER_ROOT}/resources/cobot1.sh" bashrc >/dev/null
    line="$(_block cobot1 | grep '^export PYTHONPATH')"
    out="$(env -u PYTHONPATH bash -c "${line}; echo \"\$PYTHONPATH\"")"
    assert_eq "${out}" "${HOME}/ws_cobot_pjt/ws_dsr/install/dsr_common2/lib/dsr_common2/imp"
}

# dpkg-query 가짜 = "설치됨" → hostcfg dds 가 apt/sudo 를 부르지 않음
_fake_installed() {
    mkdir -p "${HOME}/bin"
    printf '#!/bin/sh\necho "install ok installed"\n' > "${HOME}/bin/dpkg-query"; chmod +x "${HOME}/bin/dpkg-query"
    export PATH="${HOME}/bin:${PATH}"
}

test_dds_block_uses_cobot2_marker_and_replaces_existing_cobot2_block() {
    _fake_installed
    printf 'keep\n# >>> cobot2_jazzy_installer cyclonedds env >>>\nexport RMW_IMPLEMENTATION=old\n# <<< cobot2_jazzy_installer cyclonedds env <<<\nexport CYCLONEDDS_URI=stray\n' > "${BASHRC}"
    DDS_NETIF="enp3s0" bash "${INSTALLER_ROOT}/resources/hostcfg.sh" dds --no-sysctl >/dev/null
    assert_eq "$(grep -c 'cobot2_jazzy_installer cyclonedds env >>>' "${BASHRC}")" "1"
    assert_contains "$(cat "${BASHRC}")" "export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp"
    assert_eq "$(grep -c '^export CYCLONEDDS_URI=' "${BASHRC}")" "1"
    assert_contains "$(cat "${BASHRC}")" "keep"
    xml="${HOME}/.config/cyclonedds/cyclonedds.xml"
    python3 -c 'import sys,xml.dom.minidom as m; m.parse(sys.argv[1])' "${xml}"
    assert_contains "$(cat "${xml}")" '<NetworkInterface name="enp3s0" presence_required="false"/>'
    assert_contains "$(cat "${xml}")" '<NetworkInterface name="lo" priority="default" multicast="true"/>'
}

test_dds_block_rerun_is_idempotent() {
    _fake_installed
    bash "${INSTALLER_ROOT}/resources/hostcfg.sh" dds --no-sysctl >/dev/null
    bash "${INSTALLER_ROOT}/resources/hostcfg.sh" dds --no-sysctl >/dev/null
    assert_eq "$(grep -c '^export RMW_IMPLEMENTATION=' "${BASHRC}")" "1"
}
