@echo off
rem uni, the unified CLI, for this game repo: unified's own shim (unified\uni.cmd) run for this repo's root (UNI_ROOT),
rem so the bootstrap is always the pinned submodule's (unified/src/cli/README.md, Bootstrap and self-rebuild).
setlocal
if not exist "%~dp0unified\uni.cmd" (
	echo uni: "%~dp0unified" is empty: run git submodule update --init 1>&2
	exit /b 1
)
set "UNI_ROOT=%~dp0"
rem no `call`: control passes to unified's shim, which returns the exit code (and `call` would double carets)
"%~dp0unified\uni.cmd" %*
