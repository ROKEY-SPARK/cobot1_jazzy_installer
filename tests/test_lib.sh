#!/usr/bin/env bash
# tests/test_lib.sh · lib.sh / sys.sh 단위 테스트 (run.sh 가 함수별 격리 실행)
# shellcheck disable=SC2034  # COURSE 등은 source 된 라이브러리가 읽는다

_load() {
    # shellcheck source=../resources/config.sh
    source "${INSTALLER_ROOT}/resources/config.sh"
    # shellcheck source=../resources/lib.sh
    source "${INSTALLER_ROOT}/resources/lib.sh"
    # shellcheck source=../resources/sys.sh
    source "${INSTALLER_ROOT}/resources/sys.sh"
    COURSE=testcourse
    STEPS_TOTAL=3
}

test_state_set_get_overwrites_single_line() {
    _load
    state_set foo RUNNING
    state_set foo DONE
    assert_eq "$(state_get foo)" "DONE"
    assert_eq "$(grep -c '^step_foo=' "$(state_file)")" "1"
}

test_step_is_done_only_for_done_or_skipped() {
    _load
    state_set a DONE; state_set b SKIPPED; state_set c FAIL
    step_is_done a
    step_is_done b
    # `! cmd` 는 errexit 를 일으키지 않으므로 if 로 명시 판정
    if step_is_done c; then echo "FAIL counted as done"; return 1; fi
    if step_is_done missing; then echo "missing counted as done"; return 1; fi
}

test_run_step_records_done_and_skips_rerun() {
    _load
    run_step 1 touch_marker touch "${HOME}/marker" >/dev/null
    assert_eq "$(state_get touch_marker)" "DONE"
    rm "${HOME}/marker"
    out="$(run_step 1 touch_marker touch "${HOME}/marker")"
    assert_contains "${out}" "skip: touch_marker"
    [[ ! -e "${HOME}/marker" ]]
}

test_run_step_always_reruns() {
    _load
    run_step --always 1 cnt bash -c "echo x >> '${HOME}/cnt'" >/dev/null
    run_step --always 1 cnt bash -c "echo x >> '${HOME}/cnt'" >/dev/null
    assert_eq "$(wc -l < "${HOME}/cnt")" "2"
}

test_run_step_failure_exits_2_and_records_fail() {
    _load
    rc=0
    ( run_step 2 broken false ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_eq "$(state_get broken)" "FAIL"
}

test_run_step_dry_run_does_not_execute() {
    _load
    DRY_RUN=1
    out="$(run_step 1 nope touch "${HOME}/should_not_exist")"
    assert_contains "${out}" "would run: nope"
    [[ ! -e "${HOME}/should_not_exist" ]]
    assert_eq "$(state_get nope)" ""
}

test_run_step_logs_output_to_log_file() {
    _load
    run_step 1 say echo hello-log >/dev/null
    assert_contains "$(cat "${LOG_FILE}")" "hello-log"
}

test_run_step_verbose_propagates_failure() {
    _load
    VERBOSE=1
    rc=0
    ( run_step 1 vfail bash -c 'echo boom; exit 3' ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_eq "$(state_get vfail)" "FAIL"
}

test_confirm_assume_yes_passes_without_tty() {
    _load
    ASSUME_YES=1
    out="$(confirm_or_abort "do it?" </dev/null)"
    assert_contains "${out}" "auto-confirmed"
}

test_confirm_without_tty_exits_user_error() {
    _load
    rc=0
    ( confirm_or_abort "do it?" </dev/null ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_bashrc_block_is_idempotent_and_replaces() {
    _load
    printf 'line-before\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c1"
    printf 'export A=2\n' > "${HOME}/c2"
    bashrc_block_write cobot1 "${HOME}/c1"
    bashrc_block_write cobot1 "${HOME}/c1"
    assert_eq "$(grep -c '^# >>> rokey cobot1 >>>$' "${BASHRC}")" "1"
    bashrc_block_write cobot1 "${HOME}/c2"
    assert_eq "$(grep -c 'export A=' "${BASHRC}")" "1"
    assert_contains "$(cat "${BASHRC}")" "export A=2"
    assert_contains "$(cat "${BASHRC}")" "line-before"
}

test_bashrc_blocks_of_other_courses_survive() {
    _load
    printf 'X=1\n' > "${HOME}/c"
    bashrc_block_write cobot1 "${HOME}/c"
    bashrc_block_write intel1 "${HOME}/c"
    bashrc_block_remove cobot1
    assert_eq "$(grep -c '^# >>> rokey intel1 >>>$' "${BASHRC}")" "1"
    assert_eq "$(grep -c 'rokey cobot1' "${BASHRC}")" "0"
}

test_render_template_replaces_and_keeps_ampersand() {
    _load
    printf 'a=__A__\nb=__B__\n' > "${HOME}/t.in"
    render_template "${HOME}/t.in" "${HOME}/out/t" "A=x&y" "B=/p/q"
    assert_eq "$(cat "${HOME}/out/t")" $'a=x&y\nb=/p/q'
}

test_render_template_fails_on_unresolved_placeholder() {
    _load
    printf 'a=__MISSING__\n' > "${HOME}/t.in"
    rc=0
    ( render_template "${HOME}/t.in" "${HOME}/t" ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
}

test_git_clone_pinned_checks_out_ref_and_respects_local_changes() {
    _load
    git init -q "${HOME}/up"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    first="$(git -C "${HOME}/up" rev-parse HEAD)"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m two
    git_clone_pinned "${HOME}/up" "${HOME}/clone" "${first}" >/dev/null
    assert_eq "$(git -C "${HOME}/clone" rev-parse HEAD)" "${first}"
    # 재실행 = 그대로 유지 (멱등)
    git_clone_pinned "${HOME}/up" "${HOME}/clone" "${first}" >/dev/null
    assert_eq "$(git -C "${HOME}/clone" rev-parse HEAD)" "${first}"
}

test_git_clone_pinned_refuses_non_repo_dir() {
    _load
    mkdir -p "${HOME}/notrepo" && touch "${HOME}/notrepo/student_code.py"
    rc=0
    ( git_clone_pinned "${HOME}/up" "${HOME}/notrepo" main ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "1"
}

test_bashrc_block_missing_end_marker_does_not_truncate() {
    _load
    printf 'keep-1\n# >>> rokey cobot1 >>>\nexport X=1\nkeep-2\nkeep-3\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    rc=0
    ( bashrc_block_write cobot1 "${HOME}/c" ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_contains "$(cat "${BASHRC}")" "keep-3"
}

test_bashrc_block_appends_on_new_line_when_file_lacks_trailing_newline() {
    _load
    printf 'export OLD=1' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    bashrc_block_write cobot1 "${HOME}/c"
    bashrc_block_write cobot1 "${HOME}/c"
    # 마커가 줄 중간에 붙으면 매칭 실패 → 블록이 쌓인다. 줄 위치까지 정확히 본다
    assert_eq "$(grep -c 'rokey cobot1 >>>' "${BASHRC}")" "1"
    assert_eq "$(sed -n 1p "${BASHRC}")" "export OLD=1"
    assert_eq "$(sed -n 2p "${BASHRC}")" "# >>> rokey cobot1 >>>"
}

test_bashrc_block_keeps_backup_of_original() {
    _load
    printf 'original\n' > "${BASHRC}"
    printf 'export A=1\n' > "${HOME}/c"
    bashrc_block_write cobot1 "${HOME}/c"
    assert_eq "$(cat "${BASHRC}.rokey.bak")" "original"
}

test_bashrc_block_get_reads_value_inside_block_only() {
    _load
    printf 'export ROS_DOMAIN_ID=99\n' > "${BASHRC}"
    printf 'export ROS_DOMAIN_ID=12\n' > "${HOME}/c"
    bashrc_block_write cobot1 "${HOME}/c"
    assert_eq "$(bashrc_block_domain_id cobot1)" "12"
    assert_eq "$(bashrc_block_domain_id intel1)" ""
}

test_state_reads_do_not_create_files() {
    _load
    step_is_done anything || true
    state_get anything >/dev/null
    [[ ! -e "${STATE_DIR}" ]]
}

test_git_clone_pinned_accepts_empty_existing_dir() {
    _load
    git init -q "${HOME}/up"
    git -C "${HOME}/up" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
    mkdir -p "${HOME}/empty"
    git_clone_pinned "${HOME}/up" "${HOME}/empty" HEAD >/dev/null
    [[ -d "${HOME}/empty/.git" ]]
}

test_register_resume_autostart_writes_one_shot_entry_with_args() {
    _load
    COURSE=cobot1
    mkdir -p "${HOME}/bin"; printf '#!/bin/sh\n' > "${HOME}/bin/gnome-terminal"; chmod +x "${HOME}/bin/gnome-terminal"
    PATH="${HOME}/bin:${PATH}" register_resume_autostart /opt/x/install.sh cobot1 --domain-id 10 >/dev/null
    f="${HOME}/.config/autostart/rokey-jazzy-install-resume-cobot1.desktop"
    assert_contains "$(cat "${f}")" 'Exec=gnome-terminal -- bash "/opt/x/install.sh" --resume-terminal "cobot1" "--domain-id" "10"'
    remove_resume_autostart >/dev/null
    [[ ! -e "${f}" ]]
}

test_desktop_quote_escapes_special_characters() {
    _load
    assert_eq "$(_desktop_quote 'a b')" '"a b"'
    assert_eq "$(_desktop_quote '50%$x"y\z`')" '"50%%\$x\"y\\z\`"'
}

# reboot_step 를 격리 실행: as_root 를 가짜로 바꿔 실제 재부팅 없이 흐름만 본다
_load_courses() {
    _load
    COURSE=cobot1; STEPS_TOTAL=18; RESOURCE_DIR="${INSTALLER_ROOT}/resources"
    OPT_NO_REBOOT=0; DRY_RUN=0
    # shellcheck source=../resources/courses.sh
    source "${INSTALLER_ROOT}/resources/courses.sh"
    mkdir -p "${HOME}/.config/autostart"
    touch "${HOME}/.config/autostart/rokey-jazzy-install-resume-cobot1.desktop"
}

test_reboot_step_records_done_before_reboot() {
    _load_courses
    as_root() { echo "STATE_AT_REBOOT=$(state_get reboot)" > "${HOME}/seen"; }
    ( reboot_step 5 ) >/dev/null 2>&1
    assert_eq "$(cat "${HOME}/seen")" "STATE_AT_REBOOT=DONE"
}

test_reboot_step_failure_marks_fail_and_removes_autostart() {
    _load_courses
    as_root() { return 1; }
    rc=0; ( reboot_step 5 ) >/dev/null 2>&1 || rc=$?
    assert_eq "${rc}" "2"
    assert_eq "$(state_get reboot)" "FAIL"
    [[ ! -e "${HOME}/.config/autostart/rokey-jazzy-install-resume-cobot1.desktop" ]]
}

test_reboot_step_no_reboot_leaves_no_state() {
    _load_courses
    OPT_NO_REBOOT=1
    as_root() { echo "must not reboot"; return 1; }
    out="$(reboot_step 5)"
    assert_contains "${out}" "skip: reboot (--no-reboot"
    assert_eq "$(state_get reboot)" ""
}

test_reboot_step_dry_run_keeps_autostart_when_done() {
    _load_courses
    state_set reboot DONE
    DRY_RUN=1
    reboot_step 5 >/dev/null
    [[ -e "${HOME}/.config/autostart/rokey-jazzy-install-resume-cobot1.desktop" ]]
}

test_reboot_step_done_removes_autostart_after_resume() {
    _load_courses
    state_set reboot DONE
    reboot_step 5 >/dev/null
    [[ ! -e "${HOME}/.config/autostart/rokey-jazzy-install-resume-cobot1.desktop" ]]
}
