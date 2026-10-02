#!/usr/bin/env bash
# privacy-reset tests. Never calls the real tccutil.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/src/privacy-reset"
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  PASS: %s\n' "$desc"
    else
        printf '  FAIL: %s\n        expected: [%s]\n        actual:   [%s]\n' \
            "$desc" "$expected" "$actual"
        FAIL=1
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -F -q -- "$needle"; then
        printf '  PASS: %s\n' "$desc"
    else
        printf '  FAIL: %s\n        missing: [%s]\n' "$desc" "$needle"
        FAIL=1
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -F -q -- "$needle"; then
        printf '  FAIL: %s\n        unexpected: [%s]\n' "$desc" "$needle"
        FAIL=1
    else
        printf '  PASS: %s\n' "$desc"
    fi
}

test_help_without_tccutil() {
    local out status=0
    out="$(PATH="/usr/bin:/bin" "$SCRIPT" --help 2>"$ROOT/tests/.help.err")" || status=$?
    assert_eq "help exit" "0" "$status"
    assert_contains "help usage" "Usage: privacy-reset" "$out"
    assert_contains "help folder flag" "--folder-access" "$out"
    assert_contains "help all flag" "--all" "$out"
    assert_eq "help stderr empty" "" "$(cat "$ROOT/tests/.help.err")"
    rm -f "$ROOT/tests/.help.err"
}

test_missing_tccutil() {
    local err status=0 tmpdir
    tmpdir="$(mktemp -d)"
    ln -sf /bin/bash "$tmpdir/bash"
    err="$(PATH="$tmpdir" "$SCRIPT" --downloads --bundle-id com.example.app 2>&1 1>/dev/null)" || status=$?
    rm -rf "$tmpdir"
    assert_eq "missing tccutil exit" "1" "$status"
    assert_contains "missing tccutil text" "Error: tccutil was not found in PATH." "$err"
}

make_fakes() {
    FAKE_DIR="$(mktemp -d)"
    TCC_LOG="${FAKE_DIR}/tccutil.log"
    : >"$TCC_LOG"
    cat >"${FAKE_DIR}/tccutil" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${TCC_LOG:?}"
if [ -n "${TCC_FAIL_SERVICE:-}" ] && printf '%s' "$*" | grep -F -q -- "$TCC_FAIL_SERVICE"; then
    exit 9
fi
exit 0
EOF
    chmod +x "${FAKE_DIR}/tccutil"
}

run_priv() {
    RUN_STATUS=0
    RUN_OUT="$(
        PATH="${FAKE_DIR}:/usr/bin:/bin" \
        TCC_LOG="$TCC_LOG" \
        TCC_FAIL_SERVICE="${TCC_FAIL_SERVICE:-}" \
        SQLITE_FAIL="${SQLITE_FAIL:-}" \
        "$SCRIPT" "$@" 2>"${FAKE_DIR}/err"
    )" || RUN_STATUS=$?
    RUN_ERR="$(cat "${FAKE_DIR}/err")"
}

test_resets() {
    make_fakes
    run_priv --downloads --bundle-id com.example.app
    assert_eq "downloads exit" "0" "$RUN_STATUS"
    assert_eq "downloads log" "reset SystemPolicyDownloadsFolder com.example.app" "$(cat "$TCC_LOG")"
    assert_contains "downloads arrow" "==> tccutil reset SystemPolicyDownloadsFolder com.example.app" "$RUN_OUT"

    : >"$TCC_LOG"
    run_priv --folder-access --bundle-id com.example.app
    assert_eq "folder exit" "0" "$RUN_STATUS"
    assert_eq "folder log" "$(printf '%s\n' \
        'reset SystemPolicyDownloadsFolder com.example.app' \
        'reset SystemPolicyDesktopFolder com.example.app' \
        'reset SystemPolicyDocumentsFolder com.example.app' \
        'reset SystemPolicyAllFiles com.example.app')" "$(cat "$TCC_LOG")"

    : >"$TCC_LOG"
    TCC_FAIL_SERVICE=SystemPolicyDesktopFolder run_priv --folder-access --bundle-id com.example.app
    assert_eq "partial folder exit" "9" "$RUN_STATUS"
    assert_contains "partial folder failed line" "Failed: SystemPolicyDesktopFolder (status 9)." "$RUN_ERR"
    assert_eq "partial folder still ran all four" "4" "$(wc -l <"$TCC_LOG" | tr -d ' ')"

    : >"$TCC_LOG"
    unset TCC_FAIL_SERVICE
    run_priv --all --yes --downloads
    assert_eq "all downloads exit" "0" "$RUN_STATUS"
    assert_eq "all downloads log" "reset SystemPolicyDownloadsFolder" "$(cat "$TCC_LOG")"

    : >"$TCC_LOG"
    cat >"${FAKE_DIR}/ps" <<'EOF'
#!/bin/bash
if printf '%s' "$*" | grep -F -q ppid; then
    printf '1\n'
else
    printf 'bash\n'
fi
EOF
    chmod +x "${FAKE_DIR}/ps"
    TERM_PROGRAM='' run_priv --downloads
    assert_eq "no target exit" "1" "$RUN_STATUS"
    assert_contains "no target text" "Error: could not detect a bundle id. Pass --bundle-id." "$RUN_ERR"
    assert_eq "no target did not call tccutil" "" "$(cat "$TCC_LOG")"
    rm -rf "$FAKE_DIR"
}

test_list_apps() {
    make_fakes
    cat >"${FAKE_DIR}/sqlite3" <<'EOF'
#!/bin/bash
if [ "${SQLITE_FAIL:-}" = "1" ]; then
    exit 1
fi
printf '%s\n' "com.apple.Terminal" "com.googlecode.iterm2"
EOF
    chmod +x "${FAKE_DIR}/sqlite3"
    run_priv --list-apps
    assert_eq "list exit" "0" "$RUN_STATUS"
    assert_eq "list ids" "$(printf '%s\n' com.apple.Terminal com.googlecode.iterm2)" "$RUN_OUT"
    assert_eq "list did not reset" "" "$(cat "$TCC_LOG")"

    SQLITE_FAIL=1 run_priv --list-apps
    assert_eq "list fail exit" "1" "$RUN_STATUS"
    assert_contains "list fail text" "Error: could not read the privacy database." "$RUN_ERR"
    rm -rf "$FAKE_DIR"
}

test_term_program_map() {
    # shellcheck source=src/privacy-reset
    source "$SCRIPT"
    set +e
    bundle_from_term_program Apple_Terminal
    assert_eq "terminal id" "com.apple.Terminal" "$TARGET_BUNDLE"
    assert_eq "terminal name" "Terminal" "$TARGET_NAME"
    bundle_from_term_program iTerm.app
    assert_eq "iterm id" "com.googlecode.iterm2" "$TARGET_BUNDLE"
    bundle_from_term_program ghostty
    assert_eq "ghostty id" "com.mitchellh.ghostty" "$TARGET_BUNDLE"
    bundle_from_term_program WarpTerminal
    assert_eq "warp id" "dev.warp.Warp-Stable" "$TARGET_BUNDLE"
    if bundle_from_term_program vscode; then
        assert_eq "vscode stays unmapped" "1" "0"
    else
        assert_eq "vscode stays unmapped" "1" "1"
    fi
}

test_bare_comm_term_program_fallback() {
    make_fakes
    cat >"${FAKE_DIR}/ps" <<'EOF'
#!/bin/bash
if printf '%s' "$*" | grep -F -q ppid; then
    printf '1\n'
else
    printf 'bash\n'
fi
EOF
    chmod +x "${FAKE_DIR}/ps"
    # shellcheck source=src/privacy-reset
    source "$SCRIPT"
    set +e
    PATH="${FAKE_DIR}:/usr/bin:/bin" TERM_PROGRAM=Apple_Terminal detect_target
    assert_eq "bare comm bundle" "com.apple.Terminal" "$TARGET_BUNDLE"
    assert_eq "bare comm name" "Terminal" "$TARGET_NAME"
    rm -rf "$FAKE_DIR"
}

test_parent_walk() {
    make_fakes
    local app="${ROOT}/tests/fixtures/Example.app/Contents/MacOS/Example"
    cat >"${FAKE_DIR}/ps" <<EOF
#!/bin/bash
if printf '%s' "\$*" | grep -F -q ppid; then
    printf '1\n'
else
    printf '%s\n' "${app}"
fi
EOF
    chmod +x "${FAKE_DIR}/ps"
    PATH="${FAKE_DIR}:/usr/bin:/bin" TERM_PROGRAM=vscode detect_target
    assert_eq "walk id" "com.example.fixture" "$TARGET_BUNDLE"
    assert_eq "walk name" "Example" "$TARGET_NAME"

    : >"$TCC_LOG"
    RUN_STATUS=0
    RUN_OUT="$(
        PATH="${FAKE_DIR}:/usr/bin:/bin" \
        TCC_LOG="$TCC_LOG" \
        TERM_PROGRAM='' \
        "$SCRIPT" --downloads 2>"${FAKE_DIR}/err"
    )" || RUN_STATUS=$?
    assert_eq "detected downloads exit" "0" "$RUN_STATUS"
    assert_eq "detected downloads log" "reset SystemPolicyDownloadsFolder com.example.fixture" "$(cat "$TCC_LOG")"
    rm -rf "$FAKE_DIR"
}

install_menu_ps() {
    local app="${ROOT}/tests/fixtures/Example.app/Contents/MacOS/Example"
    cat >"${FAKE_DIR}/ps" <<EOF
#!/bin/bash
if printf '%s' "\$*" | grep -F -q ppid; then
    printf '1\n'
else
    printf '%s\n' "${app}"
fi
EOF
    chmod +x "${FAKE_DIR}/ps"
    cat >"${FAKE_DIR}/mdfind" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "${FAKE_DIR}/mdfind"
}

feed_menu() {
    RUN_STATUS=0
    RUN_OUT="$(printf '%s\n' "$@" | PATH="${FAKE_DIR}:/usr/bin:/bin" TERM_PROGRAM='' "$SCRIPT" 2>"${FAKE_DIR}/err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${FAKE_DIR}/err")"
}

test_menu() {
    make_fakes
    install_menu_ps
    cat >"${FAKE_DIR}/sqlite3" <<'EOF'
#!/bin/bash
printf '%s\n' "com.example.other"
EOF
    chmod +x "${FAKE_DIR}/sqlite3"
    export TCC_LOG
    feed_menu q
    assert_eq "quit exit" "0" "$RUN_STATUS"
    assert_contains "quit text" "Goodbye." "$RUN_OUT"
    assert_eq "quit did not reset" "" "$(cat "$TCC_LOG")"

    : >"$TCC_LOG"
    feed_menu nope q
    assert_contains "invalid" "Invalid option:" "$RUN_OUT"

    : >"$TCC_LOG"
    feed_menu 2 "" q
    assert_eq "menu downloads" "reset SystemPolicyDownloadsFolder com.example.fixture" "$(cat "$TCC_LOG")"
    assert_contains "menu done" "Done." "$RUN_OUT"
    assert_contains "menu reopen" "Quit and reopen Example, then approve any permission prompts." "$RUN_OUT"

    : >"$TCC_LOG"
    feed_menu 11 2 n b q
    assert_eq "all declined" "" "$(cat "$TCC_LOG")"

    : >"$TCC_LOG"
    feed_menu 11 2 y "" b q
    assert_eq "all accepted" "reset SystemPolicyDownloadsFolder" "$(cat "$TCC_LOG")"
    assert_contains "all reopen" "Quit and reopen the affected apps, then approve any permission prompts." "$RUN_OUT"

    : >"$TCC_LOG"
    feed_menu 10 1 2 "" b q
    assert_eq "other app downloads" "reset SystemPolicyDownloadsFolder com.example.other" "$(cat "$TCC_LOG")"
    rm -rf "$FAKE_DIR"
}

test_menu_unreadable_db() {
    make_fakes
    install_menu_ps
    cat >"${FAKE_DIR}/sqlite3" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${FAKE_DIR}/sqlite3"
    export TCC_LOG
    feed_menu 10 com.example.typed 2 "" q
    assert_contains "unreadable db text" "Could not read the privacy database. Full Disk Access is required to list apps." "$RUN_OUT"
    assert_eq "typed downloads" "reset SystemPolicyDownloadsFolder com.example.typed" "$(cat "$TCC_LOG")"
    rm -rf "$FAKE_DIR"
}

test_other_app_list_does_not_execute_bundle_id() {
    make_fakes
    install_menu_ps
    local marker="${FAKE_DIR}/pwned-executed"
    local payload
    # shellcheck disable=SC2016  # intentional literal command-substitution strings
    payload='$(echo pwned)$(touch "'"${marker}"'")$(printf "\120\127\116\104\137\105\130\105\103")'
    printf '%s\n' "$payload" >"${FAKE_DIR}/bundle-id"
    cat >"${FAKE_DIR}/sqlite3" <<EOF
#!/bin/bash
cat "${FAKE_DIR}/bundle-id"
EOF
    chmod +x "${FAKE_DIR}/sqlite3"
    export TCC_LOG
    feed_menu 10 q
    assert_eq "injected bundle id exit" "0" "$RUN_STATUS"
    # shellcheck disable=SC2016
    assert_contains "injected bundle id kept literal" '$(echo pwned)' "$RUN_OUT"
    assert_not_contains "injected bundle id was not executed" "PWND_EXEC" "${RUN_OUT}${RUN_ERR}"
    if [ -e "$marker" ]; then
        assert_eq "injected bundle id did not touch a marker" "absent" "present"
    else
        assert_eq "injected bundle id did not touch a marker" "absent" "absent"
    fi
    rm -rf "$FAKE_DIR"
}

test_unreadable_db_empty_bundle_returns() {
    make_fakes
    install_menu_ps
    cat >"${FAKE_DIR}/sqlite3" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "${FAKE_DIR}/sqlite3"
    export TCC_LOG
    feed_menu 10 "" q
    assert_eq "empty bundle after db failure exit" "0" "$RUN_STATUS"
    assert_contains "empty bundle returns to quit" "Goodbye." "$RUN_OUT"
    assert_eq "empty bundle did not call tccutil" "" "$(cat "$TCC_LOG")"
    rm -rf "$FAKE_DIR"
}

test_flag_errors() {
    make_fakes
    run_priv --yes
    assert_eq "yes alone exit" "2" "$RUN_STATUS"
    assert_contains "yes alone text" "Error: no action flag given." "$RUN_ERR"
    assert_eq "yes alone did not reset" "" "$(cat "$TCC_LOG")"

    run_priv --downloads --desktop --bundle-id com.example.app
    assert_eq "two actions exit" "2" "$RUN_STATUS"
    assert_contains "two actions text" "Error: only one action flag is allowed per run." "$RUN_ERR"

    run_priv --all --downloads --bundle-id com.example.app --yes
    assert_eq "all plus bundle exit" "2" "$RUN_STATUS"
    assert_contains "all plus bundle text" "Error: --all cannot be combined with --bundle-id." "$RUN_ERR"

    run_priv --all --downloads
    assert_eq "all without yes exit" "2" "$RUN_STATUS"
    assert_contains "all without yes text" "Error: resetting every app requires --yes" "$RUN_ERR"
    assert_eq "rejected flags did not reset" "" "$(cat "$TCC_LOG")"

    run_priv --downloads --bundle-id '-evil'
    assert_eq "dash bundle exit" "2" "$RUN_STATUS"
    assert_contains "dash bundle text" "Error: invalid bundle id." "$RUN_ERR"

    run_priv --list-apps --bundle-id com.example.app
    assert_eq "list-apps target exit" "2" "$RUN_STATUS"
    assert_contains "list-apps target text" "Error: --list-apps does not take a target." "$RUN_ERR"

    run_priv --list-apps --all
    assert_eq "list-apps all exit" "2" "$RUN_STATUS"
    assert_contains "list-apps all text" "Error: --list-apps does not take a target." "$RUN_ERR"
    rm -rf "$FAKE_DIR"
}

test_help_without_tccutil
test_missing_tccutil
test_list_apps
test_flag_errors
test_resets
test_term_program_map
test_bare_comm_term_program_fallback
test_parent_walk
test_menu
test_menu_unreadable_db
test_other_app_list_does_not_execute_bundle_id
test_unreadable_db_empty_bundle_returns

if [ "$FAIL" -ne 0 ]; then
    printf 'FAILED\n'
    exit 1
fi
printf 'OK\n'
