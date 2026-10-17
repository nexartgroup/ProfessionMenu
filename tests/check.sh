#!/usr/bin/env bash
# =============================================================================
# tests/check.sh  -  statische Pruefungen und Tests des Addons ProfessionMenu
#                    (WoW 3.3.5a, Lua 5.1, Interface 30300)
#
# Aufruf (von ueberall; das Skript wechselt selbst ins Addon-Verzeichnis):
#
#    bash tests/check.sh [Optionen]
#
# Reihenfolge der Schritte:
#   1. syntax   jede *.lua (auch tests/) mit  luajit -bl  uebersetzen
#   2. globals  tests/lint_globals.lua  (unbekannte/versehentliche Globals gegen wow_api_allowlist.txt)
#   3. locale   tests/lint_locale.lua   (Schluessel, Platzhalter, Kodierung der Texte)
#   4. style    tests/lint_style.lua    (Lua-5.1-Regeln, Nicht-3.3.5-API, Dateihygiene, TOC)
#   5. api      tests/audit_api.lua     (Modulzugriffe, Rahmenmethoden, Ereignisse, Aufzaehlungen, Dateien)
#   6. tests    luajit tests/run.lua    (Attrappe des 3.3.5a-Clients, tests/test_*.lua)
#
# Optionen:
#   --strict    Endabnahme: alle Sprachen muessen vollstaendig sein (lint_locale --strict-locales)
#   --known-bugs-ok  Tests mit dem Namensanfang "BUG" (bekannte Fehler des Addons) zaehlen nicht als Fehlschlag
#   --only LIST nur diese Schritte (Komma-getrennt aus: syntax globals locale style api tests selftest)
#   --selftest  zusaetzlich die Linter gegen eingebaute Fixtures pruefen
#   -v          Linter ausfuehrlich (alle Meldungen, nicht gekuerzt)
#   -h, --help  diese Hilfe
#
# Umgebung:  LUAJIT=/pfad/zu/luajit   (Standard: luajit aus dem PATH)
#            NO_COLOR=1               keine Farben
#
# Exit-Code: 0 = alle ausgefuehrten Schritte bestanden (Warnungen erlaubt),
#            1 = mindestens ein Schritt fehlgeschlagen, 2 = Umgebungsproblem.
#
# Zusatzwerkzeug (nicht Teil von check.sh): luajit tests/coverage.lua  -> Zeilenabdeckung des Addon-Codes durch die Tests.
#
# Hinweis: Tests, deren Name mit "BUG" beginnt, erwarten das RICHTIGE Verhalten und schlagen fehl, solange der Fehler
#          im Addon steckt (bekannte Fehler). "BUG?" = vermuteter Fehler, der vom echten Client
#          abhaengt. Alles andere (Attrappe, Linter, uebrige Tests) ist gruen.
#
# Abhaengigkeiten: luajit; fuer die XML-Pruefung xmllint oder python3 (ProfessionMenu hat keine XML-Dateien).
# Laeuft mit der bash 3.2 von macOS (keine assoziativen Arrays, kein mapfile).
# =============================================================================

STRICT=0
KNOWN_BUGS_OK=0
VERBOSE=0
ONLY=""
WANT_SELFTEST=0

while [ $# -gt 0 ]; do
   case "$1" in
      --strict) STRICT=1 ;;
      --known-bugs-ok) KNOWN_BUGS_OK=1 ;;
      --selftest) WANT_SELFTEST=1 ;;
      -v|--verbose) VERBOSE=1 ;;
      --only)
         shift
         if [ $# -eq 0 ]; then
            echo "check.sh: --only braucht eine Liste" >&2
            exit 2
         fi
         ONLY="$1"
         ;;
      -h|--help)
         sed -n '2,/^# =====/p' "$0" | sed -e '/^# =====/d' -e 's/^# \{0,1\}//'
         exit 0
         ;;
      *)
         echo "check.sh: unbekannte Option: $1 (siehe --help)" >&2
         exit 2
         ;;
   esac
   shift
done

# --only: nur bekannte Schrittnamen zulassen
if [ -n "$ONLY" ]; then
   OLD_IFS="$IFS"
   IFS=','
   for name in $ONLY; do
      case "$name" in
         syntax|globals|locale|style|api|tests|selftest) ;;
         *)
            IFS="$OLD_IFS"
            echo "check.sh: unbekannter Schritt in --only: '$name'" >&2
            exit 2
            ;;
      esac
   done
   IFS="$OLD_IFS"
fi

# ---------------------------------------------------------------------------
# Umgebung
# ---------------------------------------------------------------------------

SELF="${BASH_SOURCE[0]:-$0}"
ADDON_DIR="$(cd "$(dirname "$SELF")/.." && pwd)" || exit 2
cd "$ADDON_DIR" || exit 2

LUAJIT="${LUAJIT:-luajit}"
if ! command -v "$LUAJIT" >/dev/null 2>&1; then
   echo "check.sh: luajit nicht gefunden (PATH oder LUAJIT=... setzen)" >&2
   exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/professionmenu-check.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
   C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
   C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

# Ergebnisliste (parallele Arrays)
R_NAME=()
R_STATE=()
R_INFO=()
FAILED=0

record() {   # Name Zustand(OK|FAIL|ERROR|SKIP) Info
   R_NAME[${#R_NAME[@]}]="$1"
   R_STATE[${#R_STATE[@]}]="$2"
   R_INFO[${#R_INFO[@]}]="$3"
   case "$2" in FAIL|ERROR) FAILED=$((FAILED + 1)) ;; esac
}

want() {   # Schritt ausgewaehlt?
   case ",$ONLY," in
      ",,") return 0 ;;
      *",$1,"*) return 0 ;;
   esac
   return 1
}

heading() {
   echo
   echo "== $1"
}

# Alle Lua-Dateien relativ zum Addon-Verzeichnis, sortiert; Fixtures ausgenommen.
list_lua_files() {
   find . -type f -name '*.lua' \
      -not -path './.*' -not -path '*/.*/*' \
      -not -path '*/_lintfixtures/*' -not -name 'lint_fixture_*' \
      | sed 's|^\./||' | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Schritt 1: Syntax
# ---------------------------------------------------------------------------

step_syntax() {
   heading "syntax: luajit -bl (alle Lua-Dateien)"
   local n=0 bad=0 f
   while IFS= read -r f; do
      [ -n "$f" ] || continue
      n=$((n + 1))
      if ! "$LUAJIT" -bl "$f" >/dev/null 2>"$TMP/syntax.err"; then
         bad=$((bad + 1))
         echo "  $(head -n 1 "$TMP/syntax.err" | sed 's/^luajit: //')"
      fi
   done < <(list_lua_files)
   if [ "$n" -eq 0 ]; then
      echo "  keine Lua-Dateien gefunden"
      record syntax ERROR "keine Lua-Dateien"
   elif [ "$bad" -gt 0 ]; then
      echo "  $bad von $n Datei(en) mit Syntaxfehlern"
      record syntax FAIL "$bad von $n Datei(en) mit Syntaxfehlern"
   else
      echo "  $n Dateien in Ordnung"
      record syntax OK "$n Lua-Dateien"
   fi
}

# ---------------------------------------------------------------------------
# Schritte 2-5: Linter
# ---------------------------------------------------------------------------

run_lint() {   # Name Skript [Argumente...]
   local name="$1" script="$2" rc
   shift 2
   heading "$name: luajit tests/$script $*"
   "$LUAJIT" "tests/$script" "$@" >"$TMP/$name.out" 2>&1
   rc=$?
   cat "$TMP/$name.out"
   local summary
   summary="$(grep -E '^(lint_globals|lint_locale|lint_style|audit_api):' "$TMP/$name.out" | tail -n 1)"
   [ -n "$summary" ] || summary="$(tail -n 1 "$TMP/$name.out")"
   if [ "$rc" -eq 0 ]; then
      record "$name" OK "$summary"
   elif [ "$rc" -eq 1 ]; then
      record "$name" FAIL "$summary"
   else
      record "$name" ERROR "Werkzeugfehler (Exit $rc): $(tail -n 1 "$TMP/$name.out")"
   fi
}

step_globals() {
   if [ ! -f tests/lint_globals.lua ]; then
      record globals ERROR "tests/lint_globals.lua fehlt"
      return
   fi
   run_lint globals lint_globals.lua
}

step_locale() {
   if [ ! -f tests/lint_locale.lua ]; then
      record locale ERROR "tests/lint_locale.lua fehlt"
      return
   fi
   local args=()
   [ "$STRICT" -eq 1 ] && args[${#args[@]}]="--strict-locales"
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint locale lint_locale.lua "${args[@]}"
}

step_style() {
   if [ ! -f tests/lint_style.lua ]; then
      record style ERROR "tests/lint_style.lua fehlt"
      return
   fi
   local args=()
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint style lint_style.lua "${args[@]}"
}

step_api() {
   if [ ! -f tests/audit_api.lua ]; then
      record api ERROR "tests/audit_api.lua fehlt"
      return
   fi
   local args=()
   [ "$VERBOSE" -eq 1 ] && args[${#args[@]}]="-v"
   run_lint api audit_api.lua "${args[@]}"
}

# ---------------------------------------------------------------------------
# Schritt 6: Tests
# ---------------------------------------------------------------------------

step_tests() {
   if [ ! -f tests/run.lua ]; then
      heading "tests: tests/run.lua"
      echo "  tests/run.lua fehlt"
      record tests FAIL "tests/run.lua fehlt"
      return
   fi
   heading "tests: luajit tests/run.lua"
   local run_args=()
   [ "$KNOWN_BUGS_OK" -eq 1 ] && run_args[${#run_args[@]}]="--known-bugs-ok"
   "$LUAJIT" tests/run.lua "${run_args[@]}" >"$TMP/tests.out" 2>&1
   local rc=$?
   cat "$TMP/tests.out"
   local line
   line="$(grep -E '^[0-9]+ tests: ' "$TMP/tests.out" | tail -n 1)"
   if [ "$rc" -eq 0 ]; then
      record tests OK "$line"
   else
      record tests FAIL "Exit $rc: $line"
   fi
}

# ---------------------------------------------------------------------------
# Selbsttest der Linter (Fixtures werden hier erzeugt und danach geloescht)
# ---------------------------------------------------------------------------

ST_PASS=0
ST_FAIL=0

st_ok() {
   ST_PASS=$((ST_PASS + 1))
}

st_bad() {
   ST_FAIL=$((ST_FAIL + 1))
   echo "  FAIL: $1"
}

# st_expect Beschreibung Erwarteter-Exit Ausgabedatei Ist-Exit Muster... (fixe Teilstrings)
st_expect() {
   local desc="$1" want_rc="$2" outfile="$3" got_rc="$4" pat
   shift 4
   if [ "$got_rc" -ne "$want_rc" ]; then
      st_bad "$desc: Exit $got_rc statt $want_rc"
      sed 's/^/        /' "$outfile" | head -n 12
      return
   fi
   for pat in "$@"; do
      if ! grep -F -q -- "$pat" "$outfile"; then
         st_bad "$desc: Ausgabe enthaelt nicht: $pat"
         sed 's/^/        /' "$outfile" | head -n 12
         return
      fi
   done
   st_ok
}

# st_absent Beschreibung Ausgabedatei Muster...
st_absent() {
   local desc="$1" outfile="$2" pat
   shift 2
   for pat in "$@"; do
      if grep -F -q -- "$pat" "$outfile"; then
         st_bad "$desc: Ausgabe enthaelt unerwartet: $pat"
         return
      fi
   done
   st_ok
}

step_selftest() {
   heading "selftest: Linter gegen eingebaute Fixtures"
   local d="$TMP/st" rc
   mkdir -p "$d/g" "$d/s" "$d/toc" "$d/api" "$d/loc_bad" "$d/loc_ok"

   # --- lint_globals ---------------------------------------------------------
   cat > "$d/g/bad.lua" <<'LUA'
local a = 1
leak_write = 5
local function outer()
   local function inner()
      return NoSuch_Read(a)
   end
   nested_leak = inner
   return function()
      deep_leak = true
   end
end
function GlobalFunc() end
print(this, arg1, C_Timer)
LUA
   cat > "$d/g/good.lua" <<'LUA'
local ADDON, PM = ...
ProfessionMenuDB = ProfessionMenuDB or {}
ProfessionMenuMyFrame = CreateFrame("Frame", "ProfessionMenuMyFrame", UIParent)
SLASH_PROFESSIONMENU1 = "/berufe"
SlashCmdList["PROFESSIONMENU"] = function() end
print(GetNumSkillLines(), GetSpellInfo(2575), floor(1.5), strsplit(",", "a,b"), GetTime(), bit.band(1, 1), PM)
LUA
   "$LUAJIT" tests/lint_globals.lua "$d/g/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: schlechte Datei" 1 "$d/out" "$rc" \
      "bad.lua:2: WRITE to global 'leak_write'" \
      "bad.lua:5: read of undefined global 'NoSuch_Read'" \
      "bad.lua:7: WRITE to global 'nested_leak'" \
      "bad.lua:9: WRITE to global 'deep_leak'" \
      "bad.lua:12: WRITE to global 'GlobalFunc'" \
      "'this'" "'arg1'" "'C_Timer'"
   "$LUAJIT" tests/lint_globals.lua "$d/g/good.lua" >"$d/out" 2>&1; rc=$?
   st_expect "globals: saubere Datei" 0 "$d/out" "$rc" "0 violation(s)"

   # --- lint_style -----------------------------------------------------------
   cat > "$d/s/bad.lua" <<'LUA'
local f = CreateFrame("Frame")
f:SetSize(1, 1)
f:SetShown(true)
local t = table.unpack({})
local x = math.type(1)
local y = 7 // 2
local z = 5 & 3
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
C_Timer.After(1, print)
local s = string.format("%i", 3)
local function h() return this, arg1 end
goto done
::done::
LUA
   cat > "$d/s/good.lua" <<'LUA'
-- goto, SetSize, C_Timer, this, arg1, table.unpack: nur Kommentar
--[[ langer Kommentar: SetShown utf8.char math.type ]]
local s = "goto SetSize C_Timer this arg1 table.unpack 5 // 2"
local t = [[ SetColorTexture Mixin ]]
local u = { Mixin = 1 }
local function onEvent(self, event, arg1, arg2)
   for arg3 = 1, 2 do print(arg3) end
   return arg1, arg2
end
local n = 5 ~= 3
return s, t, u, n, onEvent
LUA
   "$LUAJIT" tests/lint_style.lua -v "$d/s/bad.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: schlechte Datei" 1 "$d/out" "$rc" \
      "bad.lua:2: error [no-api]" "bad.lua:3: error [no-api]" "bad.lua:4: error [lua52-lib]" \
      "bad.lua:5: error [lua52-lib]" "bad.lua:6: error [intdiv]" "bad.lua:7: error [bitop]" \
      "bad.lua:8: error [no-api]" "bad.lua:9: error [no-api]" \
      "bad.lua:10: error [format-i]" "bad.lua:11: error [implicit-global]" "bad.lua:12: error [goto]" \
      "bad.lua:13: error [label]"
   "$LUAJIT" tests/lint_style.lua "$d/s/good.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: Strings, Kommentare und Parameter namens arg1/arg2 ausgeblendet" 0 "$d/out" "$rc" "0 error(s)"
   printf 'local a = 1  \r\nlocal b = 2\t\n' > "$d/s/ws.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/ws.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: Leerraum/CRLF/Tab" 1 "$d/out" "$rc" "[trailing-ws]" "[tab]" "[crlf]"
   printf '\357\273\277local a = 1\n' > "$d/s/bom.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/bom.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: BOM" 1 "$d/out" "$rc" "[bom]"
   printf 'local a = "\377\376"\n' > "$d/s/u8.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/u8.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: ungueltiges UTF-8" 1 "$d/out" "$rc" "[utf8]"
   printf 'local f = {}\nf:SetSize(1, 1) -- lint:allow(no-api)\n' > "$d/s/allow.lua"
   "$LUAJIT" tests/lint_style.lua "$d/s/allow.lua" >"$d/out" 2>&1; rc=$?
   st_expect "style: lint:allow" 0 "$d/out" "$rc" "0 error(s)"

   # --- lint_style: TOC ------------------------------------------------------
   printf '## Interface: 30300\n## Title: T\n## SavedVariables: SomethingElse\n' > "$d/toc/ProfessionMenu.toc"
   printf 'Core.lua\nGone.lua\nLocales.lua\n' >> "$d/toc/ProfessionMenu.toc"
   printf 'local a = 1\n' > "$d/toc/Locales.lua"
   printf 'local a = 1\n' > "$d/toc/Core.lua"
   printf 'local a = 1\n' > "$d/toc/Extra.lua"
   "$LUAJIT" tests/lint_style.lua --root "$d/toc" >"$d/out" 2>&1; rc=$?
   st_expect "toc: fehlend, nicht gelistet, SavedVariables, Reihenfolge" 1 "$d/out" "$rc" \
      "[toc-missing] listed file does not exist: Gone.lua" \
      "[toc-unlisted]" "Extra.lua" "[toc-savedvars]" "[toc-order]"

   # --- audit_api ------------------------------------------------------------
   printf '## Interface: 30300\nCore.lua\nUser.lua\n' > "$d/api/ProfessionMenu.toc"
   cat > "$d/api/Core.lua" <<'LUA'
local ADDON, PM = ...
local UI = {}
PM.UI = UI
function UI.Two(a, b) return a, b end
function UI.Var(...) return ... end
UI.Value = 5
local f = CreateFrame("Frame", nil, UIParent, "SecureActionButtonTemplate")
f:RegisterEvent("PLAYER_LOGIN")
LUA
   cat > "$d/api/User.lua" <<'LUA'
local ADDON, PM = ...
local UI = PM.UI
UI.Two(1, 2)
UI.Var(1, 2, 3, 4)
UI.Two(1, 2, 3)
UI.Missing()
PM.UI.AlsoMissing(1)
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLE")
f:SetPoint("MIDDLE", UIParent, "CENTER")
f:SetFrameStrata("TOPMOST")
f:SetShown(true)
f:SetJustifyH("MIDDLE")
local t = f:CreateTexture(nil, "FOREGROUND")
LUA
   "$LUAJIT" tests/audit_api.lua --root "$d/api" >"$d/out" 2>&1; rc=$?
   st_expect "api: Fehlgriffe werden gefunden" 1 "$d/out" "$rc" \
      "User.lua:5: PM.UI.Two mit 3 Argument(en)" \
      "User.lua:6: PM.UI.Missing ist nirgends definiert" \
      "User.lua:7: PM.UI.AlsoMissing ist nirgends definiert" \
      "Ereignis PLAYER_REGEN_ENABLE gibt es in 3.3.5a nicht" \
      "SetPoint: Ankerpunkt MIDDLE ist ungueltig" \
      "SetFrameStrata: TOPMOST ist ungueltig" \
      "Methode :SetShown()" \
      "SetJustifyH: MIDDLE ist ungueltig" \
      "Zeichenebene FOREGROUND ist ungueltig"
   st_absent "api: korrekte Aufrufe bleiben still" "$d/out" "FEHLER  User.lua:3:" "FEHLER  User.lua:4:" "FEHLER  Core.lua:"

   # --- lint_locale ----------------------------------------------------------
   cat > "$d/loc_bad/Locales.lua" <<'LUA'
local ADDON, PM = ...
local texts = {}
texts.enUS = {
   title = "Professions",
   skill = "Skill: %d / %d",
   unused = "Never used",
   help = "a|rb",
}
texts.deDE = {
   title = "Berufe",
   skill = "Fertigkeit: %s",
   stray = "nicht in enUS",
}
PM.texts = texts
LUA
   printf 'local ADDON, PM = ...\nlocal L = PM.L\nprint(L.title, L.skill, L.missing_key, PM.L.help)\n' > "$d/loc_bad/UI.lua"
   "$LUAJIT" tests/lint_locale.lua --root "$d/loc_bad" >"$d/out" 2>&1; rc=$?
   st_expect "locale: schlechte Sprachdateien" 1 "$d/out" "$rc" \
      "[key-undefined]" "missing_key" "[key-orphan]" "deDE.stray" "[placeholder]" "deDE.skill" "[locale-missing]" "[pipe]" "[key-unused]"
   cat > "$d/loc_ok/Locales.lua" <<'LUA'
local ADDON, PM = ...
local texts = {}
texts.enUS = {
   title = "Professions",
   cat_craft = "Crafting",
   cat_refine = "Processing",
   cat_gather = "Gathering",
   cat_secondary = "Secondary",
   hint_open = "Open",
   hint_track = "Track",
   hint_use = "Use",
   hint_passive = "Passive",
   hint_skills = "Skills",
   skill = "Skill: %d / %d",
   none = "None",
   combat = "Combat",
}
texts.deDE = {
   title = "Berufe",
   cat_craft = "Herstellung",
   cat_refine = "Weiterverarbeitung",
   cat_gather = "Sammeln",
   cat_secondary = "Nebenberufe",
   hint_open = "Oeffnen",
   hint_track = "Orten",
   hint_use = "Benutzen",
   hint_passive = "Passiv",
   hint_skills = "Fertigkeiten",
   skill = "Fertigkeit: %d / %d",
   none = "Keine",
   combat = "Kampf",
}
PM.texts = texts
LUA
   printf 'local ADDON, PM = ...\nlocal L = PM.L\nprint(L.title, L.skill, L.none, L.combat, L.hint_open, L.hint_track, L.hint_use)\nprint(L.hint_passive, L.hint_skills, L["cat_" .. x])\n' > "$d/loc_ok/UI.lua"
   "$LUAJIT" tests/lint_locale.lua --root "$d/loc_ok" >"$d/out" 2>&1; rc=$?
   st_expect "locale: saubere Sprachdateien" 0 "$d/out" "$rc" "0 Fehler"

   echo "  $ST_PASS Pruefungen bestanden, $ST_FAIL fehlgeschlagen"
   if [ "$ST_FAIL" -gt 0 ]; then
      record selftest FAIL "$ST_FAIL von $((ST_PASS + ST_FAIL)) Fixture-Pruefungen fehlgeschlagen"
   else
      record selftest OK "$ST_PASS Fixture-Pruefungen"
   fi
}

# ---------------------------------------------------------------------------
# Hauptlauf
# ---------------------------------------------------------------------------

echo "ProfessionMenu static checks  ($ADDON_DIR)"
echo "luajit: $("$LUAJIT" -v 2>&1 | head -n 1)"

if want syntax; then step_syntax; fi
if want globals; then step_globals; fi
if want locale; then step_locale; fi
if want style; then step_style; fi
if want api; then step_api; fi
if want tests; then step_tests; fi
if [ "$WANT_SELFTEST" -eq 1 ] || { [ -n "$ONLY" ] && want selftest; }; then step_selftest; fi

echo
echo "=============================================================================="
echo "Zusammenfassung"
i=0
while [ "$i" -lt "${#R_NAME[@]}" ]; do
   state="${R_STATE[$i]}"
   case "$state" in
      OK) tag="${C_OK}[ OK ]${C_OFF}" ;;
      SKIP) tag="${C_DIM}[SKIP]${C_OFF}" ;;
      *) tag="${C_BAD}[FAIL]${C_OFF}" ;;
   esac
   printf '  %s %-9s %s\n' "$tag" "${R_NAME[$i]}" "${R_INFO[$i]}"
   i=$((i + 1))
done

if [ "$FAILED" -gt 0 ]; then
   echo "${C_BAD}ERGEBNIS: FEHLGESCHLAGEN${C_OFF} ($FAILED von ${#R_NAME[@]} Schritten)"
   exit 1
fi
echo "${C_OK}ERGEBNIS: BESTANDEN${C_OFF} (${#R_NAME[@]} Schritte)"
exit 0
