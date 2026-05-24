#!/bin/bash
# amalgame-io-filewatcher — Test Runner. Requires amc 0.7.7+.
set -u

if [ $# -ge 1 ]; then AMC="$1"
elif [ -n "${AMC:-}" ]; then :
elif command -v amc >/dev/null 2>&1; then AMC="$(command -v amc)"
else echo "ERROR: amc not found." >&2; exit 2
fi
[ -x "$AMC" ] || { echo "ERROR: amc not executable: $AMC" >&2; exit 2; }
AMC="$(cd "$(dirname "$AMC")" && pwd)/$(basename "$AMC")"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AMC_DIR="$(cd "$(dirname "$AMC")" && pwd)"
if [ -d "$AMC_DIR/runtime" ]; then AMC_RUNTIME="$AMC_DIR/runtime"
elif [ -n "${AMC_RUNTIME:-}" ]; then :
else echo "ERROR: amc runtime/ not found." >&2; exit 2; fi

BUILD_DIR="$(mktemp -d -t affw-tests-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
PROJ_DIR="$BUILD_DIR/proj"
mkdir -p "$PROJ_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
PASS=0; FAIL=0; SKIP=0

echo ""
echo "════════════════════════════════════════════"
echo "  amalgame-io-filewatcher — Test Suite"
echo "════════════════════════════════════════════"
echo "  amc:     $AMC ($("$AMC" --version 2>&1 | head -1))"
echo "  package: $PKG_ROOT"
echo "  runtime: $AMC_RUNTIME"

FAKE_CACHE="$BUILD_DIR/cache"
PKG_GIT="github.com/amalgame-lang/amalgame-io-filewatcher"
PKG_TAG="${PKG_TAG:-v0.1.0}"
FAKE_SHA="deadbeefcafebabe0000000000000000000000ab"
SHORT_SHA="${FAKE_SHA:0:8}"
PKG_CACHE_DIR="$FAKE_CACHE/$PKG_GIT/${PKG_TAG}_${SHORT_SHA}"
mkdir -p "$(dirname "$PKG_CACHE_DIR")"
ln -s "$PKG_ROOT" "$PKG_CACHE_DIR"

cat > "$PROJ_DIR/amalgame.lock" <<EOF
[[package]]
name = "amalgame-io-filewatcher"
git  = "$PKG_GIT"
tag  = "$PKG_TAG"
rev  = "$FAKE_SHA"
EOF
export AMALGAME_PACKAGES_DIR="$FAKE_CACHE"
echo "  cache:   $FAKE_CACHE → $PKG_ROOT"
echo ""

case "$(uname -s)" in
    Linux*)               PLAT="linux-$(uname -m)" ;;
    Darwin*)              PLAT="macos-$(uname -m)" ;;
    MINGW*|MSYS*|CYGWIN*) PLAT="windows-$(uname -m)" ;;
    *)                    PLAT="unknown-$(uname -m)" ;;
esac
PLAT="${PLAT/amd64/x86_64}"; PLAT="${PLAT/aarch64/arm64}"

FACADE_BUILD_DIR="$BUILD_DIR/build/$PLAT"
mkdir -p "$FACADE_BUILD_DIR"
WORK_BUILD_DIR="$PKG_ROOT/build/$PLAT"
mkdir -p "$(dirname "$WORK_BUILD_DIR")"
if [ -e "$WORK_BUILD_DIR" ] && [ ! -L "$WORK_BUILD_DIR" ]; then rm -rf "$WORK_BUILD_DIR"; fi
rm -f "$WORK_BUILD_DIR"
ln -s "$FACADE_BUILD_DIR" "$WORK_BUILD_DIR"
ARCHIVE="$FACADE_BUILD_DIR/libamalgame-pkg-FileWatcher.a"

echo "── Pre-compiling facade.am → libamalgame-pkg-FileWatcher.a ──"
"$AMC" --lib --quiet "$PKG_ROOT/facade.am" -o "$FACADE_BUILD_DIR/FileWatcher-facade"
gcc -O2 -I"$AMC_RUNTIME" -w -c "$FACADE_BUILD_DIR/FileWatcher-facade.c" \
    -o "$FACADE_BUILD_DIR/FileWatcher-facade.o"
ar rcs "$ARCHIVE" "$FACADE_BUILD_DIR/FileWatcher-facade.o"
ARSIZE=$(stat -c%s "$ARCHIVE" 2>/dev/null || stat -f%z "$ARCHIVE")
echo "  built: $ARCHIVE ($ARSIZE bytes)"
echo ""

run_test() {
    local name="$1"; local expected="$2"
    printf "  %-38s" "$name"
    cp "$SCRIPT_DIR/stdlib_file_watch.am" "$PROJ_DIR/test.am"
    local out_base="$PROJ_DIR/test"
    local out
    out=$(cd "$PROJ_DIR" && "$AMC" -o test test.am --quiet 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${RED}FAIL${NC} (amc error)"
        echo "$out" | head -3 | sed 's/^/    /'
        FAIL=$((FAIL + 1)); return
    fi
    if [ ! -f "$out_base.c" ]; then echo -e "${RED}FAIL${NC} (no .c)"; FAIL=$((FAIL + 1)); return; fi
    local gcc_log
    gcc_log=$(gcc -O2 -I"$AMC_RUNTIME" "$out_base.c" "$ARCHIVE" \
        -lgc -lm -lz -ldl -lpthread -o "$out_base" 2>&1)
    if [ ! -x "$out_base" ]; then
        echo -e "${RED}FAIL${NC} (link)"
        echo "$gcc_log" | head -5 | sed 's/^/    /'
        FAIL=$((FAIL + 1)); return
    fi
    local run_output
    run_output=$("$out_base" 2>&1)
    if echo "$run_output" | grep -qF "$expected"; then
        echo -e "${GREEN}PASS${NC}"; PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (mismatch)"
        echo "    expected: $expected"
        echo "    got:      $(echo "$run_output" | head -3 | tr '\n' '|')"
        FAIL=$((FAIL + 1))
    fi
}

echo "── Amalgame.IO.FileWatcher v1 ─────────────"
run_test "exists when present"          "[PASS] exists when present"
run_test "getpath"                      "[PASS] getpath"
run_test "no-change-on-init"            "[PASS] no-change-on-init"
run_test "detect-delete"                "[PASS] detect-delete"
run_test "reset-after-read"             "[PASS] reset-after-read"
run_test "exists when absent"           "[PASS] exists when absent"
run_test "detect-recreate"              "[PASS] detect-recreate"

echo ""
echo "── Amalgame.IO.FileWatcher v2 ─────────────"
run_test "Poll Created"                 "[PASS] Poll emits Created on appearance"
run_test "Poll quiescent"               "[PASS] Poll quiescent"
run_test "Poll Deleted"                 "[PASS] Poll emits Deleted on disappearance"
run_test "WatchEvent.PathOf"            "[PASS] WatchEvent.PathOf"
run_test "WatchEvent.TimestampMs"       "[PASS] WatchEvent.TimestampMs"
run_test "DirectoryWatcher empty"       "[PASS] DirectoryWatcher empty snapshot"
run_test "DirectoryWatcher 2 Created"   "[PASS] DirectoryWatcher detects 2 Created"
run_test "DirectoryWatcher all Created" "[PASS] DirectoryWatcher all events are Created"
run_test "DirectoryWatcher Deleted"     "[PASS] DirectoryWatcher Deleted event"
run_test "DirectoryWatcher recursive"   "[PASS] DirectoryWatcher recursive sees nested"
run_test "DirectoryWatcher non-recurs"  "[PASS] DirectoryWatcher non-recursive ignores subdirs"

echo ""
echo "── Amalgame.IO.FileWatcher v0.4 (inotify) ─"
run_test "BackendName probe"            "[PASS] FileWatcher.BackendName returns inotify or polling"
run_test "inotify reactive Modify"      "PASS] inotify detects Modify in real time"
run_test "inotify atomic-rename"        "PASS] inotify atomic-rename recovery (Delete+Create)"
run_test "inotify recursive new subdir" "PASS] inotify recursive picks up new subdir's file"

echo ""
echo "── Amalgame.IO.FileWatcher v0.5 (rename pairing) ─"
run_test "rename within dir → Renamed"  "PASS] rename within watched dir → Renamed event with both paths"
run_test "move out → Deleted"           "PASS] move out of watched dir → Deleted"
run_test "move in → Created"            "PASS] move into watched dir → Created"

rm -f "$WORK_BUILD_DIR"
echo ""
echo "────────────────────────────────────────────"
echo -e "  ${GREEN}PASS: $PASS${NC}  |  ${RED}FAIL: $FAIL${NC}  |  ${YELLOW}SKIP: $SKIP${NC}"
echo "────────────────────────────────────────────"
echo ""
[ $FAIL -eq 0 ] && exit 0 || exit 1
