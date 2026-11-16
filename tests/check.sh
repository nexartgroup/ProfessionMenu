#!/bin/sh
# Alle Pruefungen von ProfessionMenu (WoW: Forever). Aufruf im Addon-Ordner:  sh tests/check.sh
# Braucht LuaJIT (Lua 5.1 wie im Spiel):  brew install luajit
set -e
cd "$(dirname "$0")/.."

echo "== Syntax"
for f in $(grep -v '^##' ProfessionMenu.toc | grep -v '^$' | tr -d '\r'); do
   luajit -e "local f, e = loadfile('$f'); if not f then io.stderr:write(e .. '\n') os.exit(1) end"
   echo "   $f"
done

echo "== Globale Namen"
luajit tests/lint_globals.lua

echo "== Tests"
luajit tests/run.lua
