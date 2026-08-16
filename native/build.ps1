# builds native/vlc.c into <lib>/native/bin/vlc.hdll (the hashlink native ext heapvlc.HeapVLC /
# heapvlc.LibVLC call into), then stages the libVLC runtime (libvlc(core).dll + plugins + lua/)
# next to hl.exe - hashlink's .hdll loader only searches next to hl.exe, not the working dir, so
# that's the one copy that actually matters for `hl yourgame.hl` to find it. Optionally also
# copies both into a consuming project's own bin/ (pass -BinDir).
#
# usage:
#   powershell -ExecutionPolicy Bypass -File native/build.ps1 [-BinDir path\to\game\bin]
#
# needs MSVC (VS Build Tools) and a local libVLC 3.x SDK. headers + import libs live under
# native/{include,lib}. the runtime dlls + plugins aren't vendored (tens of MB), they're pulled
# from an existing VLC install / SDK.

param(
	[string]$BinDir
)

$ErrorActionPreference = "Stop"

$nativeDir = $PSScriptRoot
$libDir = Split-Path -Parent $nativeDir
$outDir = Join-Path $nativeDir "bin"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# 1. find vcvarsall.bat via vswhere, fall back to the usual install paths.
function Find-VcVarsAll {
	$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path $vswhere) {
		$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
		if ($vsPath) {
			$candidate = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
			if (Test-Path $candidate) { return $candidate }
		}
	}
	$fallback = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft Visual Studio","${env:ProgramFiles}\Microsoft Visual Studio" -Recurse -Filter "vcvarsall.bat" -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($fallback) { return $fallback.FullName }
	throw "Could not find vcvarsall.bat. Install the 'Desktop development with C++' workload (Visual Studio Build Tools)."
}
$vcvarsall = Find-VcVarsAll
Write-Host "Using MSVC via $vcvarsall"

# 2. find a libVLC 3.x runtime to stage (libvlc.dll, libvlccore.dll, plugins/, lua/).
# lua/ holds the playlist resolver scripts that turn a video-site page url into a playable
# stream. without it, opening a youtube watch url just tries to demux the raw html and fails
# silently.
function Find-VlcRuntime {
	if ($env:VLC_SDK_DIR -and (Test-Path (Join-Path $env:VLC_SDK_DIR "libvlc.dll"))) {
		return @{ dlls = $env:VLC_SDK_DIR; plugins = Join-Path $env:VLC_SDK_DIR "plugins"; lua = Join-Path $env:VLC_SDK_DIR "lua" }
	}
	$installed = "${env:ProgramFiles}\VideoLAN\VLC"
	if (Test-Path (Join-Path $installed "libvlc.dll")) {
		return @{ dlls = $installed; plugins = Join-Path $installed "plugins"; lua = Join-Path $installed "lua" }
	}
	# hxvlc (https://github.com/MAJigsaw77/hxvlc) bundles a libVLC SDK for its own (hxcpp)
	# target; if it's installed we can borrow its runtime too. It has no lua/ (it targets local
	# files, not web playlists), so youtube/etc URLs still won't resolve from this fallback.
	$haxelib = Get-ChildItem "$env:HAXEPATH\lib\hxvlc" -Directory -ErrorAction SilentlyContinue |
		Sort-Object Name -Descending | Select-Object -First 1
	if ($haxelib) {
		$vlcDir = Join-Path $haxelib.FullName "project\vlc"
		return @{ dlls = Join-Path $vlcDir "lib\Windows"; plugins = Join-Path $vlcDir "plugins\Windows"; lua = $null }
	}
	return $null
}

# 3. compile vlc.c -> native/bin/vlc.hdll
$hlInclude = "C:\Hashlink\include"
$hlLib = "C:\Hashlink"
$vlcInclude = Join-Path $nativeDir "include"
$vlcLib = Join-Path $nativeDir "lib"

if (-not (Test-Path (Join-Path $hlInclude "hl.h"))) {
	throw "HashLink SDK not found at $hlInclude (expected hl.h). Adjust `$hlInclude in this script."
}

$outHdll = Join-Path $outDir "vlc.hdll"
$cmd = @"
call "$vcvarsall" x64 >nul
cl.exe /nologo /LD /O2 /MD ^
	/I "$hlInclude" /I "$vlcInclude" ^
	"$nativeDir\vlc.c" ^
	/Fo"$nativeDir\vlc.obj" ^
	/link /LIBPATH:"$hlLib" /LIBPATH:"$vlcLib" libhl.lib libvlc.lib libvlccore.lib ^
	/OUT:"$outHdll" /IMPLIB:"$nativeDir\vlc.lib"
"@
$cmdFile = Join-Path $nativeDir "_build.cmd"
Set-Content -Path $cmdFile -Value $cmd -Encoding ASCII
& cmd.exe /c "`"$cmdFile`""
if ($LASTEXITCODE -ne 0) { throw "Compilation failed (exit $LASTEXITCODE)" }
Remove-Item $cmdFile, (Join-Path $nativeDir "vlc.obj"), (Join-Path $nativeDir "vlc.exp"), (Join-Path $nativeDir "vlc.lib") -ErrorAction SilentlyContinue
Write-Host "Built $outHdll"

# 4. stage the runtime (dlls + plugins + lua) into a target dir. libvlc.dll looks for its
#    plugins/ folder next to itself.
function Stage-VlcRuntime($rt, $targetDir) {
	if ($null -eq $rt) {
		Write-Warning "No libVLC runtime found (checked VLC_SDK_DIR, Program Files, haxelib hxvlc). Copy libvlc.dll, libvlccore.dll and the plugins/ folder into $targetDir manually."
		return
	}
	New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
	Copy-Item (Join-Path $rt.dlls "libvlc.dll") $targetDir -Force
	Copy-Item (Join-Path $rt.dlls "libvlccore.dll") $targetDir -Force
	$pluginsOut = Join-Path $targetDir "plugins"
	if (-not (Test-Path $pluginsOut)) {
		Write-Host "Copying VLC plugins from $($rt.plugins) into $targetDir (this is ~70-130MB, one-time)..."
		Copy-Item $rt.plugins $pluginsOut -Recurse -Force
	}
	if ($rt.lua -and (Test-Path $rt.lua)) {
		$luaOut = Join-Path $targetDir "lua"
		if (-not (Test-Path $luaOut)) {
			Write-Host "Copying VLC lua scripts from $($rt.lua) into $targetDir..."
			Copy-Item $rt.lua $luaOut -Recurse -Force
		}
	} else {
		Write-Warning "No lua/ scripts found for this libVLC runtime - web playlist URLs (YouTube, Vimeo, ...) won't resolve. Direct media file/stream URLs are unaffected."
	}
	Write-Host "Staged libvlc runtime from $($rt.dlls) into $targetDir"
}

$rt = Find-VlcRuntime

# native/bin/ - this library's own build output, kept for reference/packaging.
Stage-VlcRuntime $rt $outDir

# next to hl.exe - what actually makes any `hl yourgame.hl` find vlc.hdll, since that's the only
# dir hashlink's native loader searches (verified: NOT the process's working directory).
$hlCmd = Get-Command hl.exe -ErrorAction SilentlyContinue
if ($hlCmd) {
	$hlDir = Split-Path -Parent $hlCmd.Source
	Copy-Item $outHdll $hlDir -Force
	Stage-VlcRuntime $rt $hlDir
	Write-Host "Deployed vlc.hdll to $hlDir (next to hl.exe)"
} else {
	Write-Warning "hl.exe not found on PATH; copy $outHdll and the libvlc runtime next to your hl.exe manually."
}

# optional: also copy into a consuming project's own bin/ (for packaging a standalone build
# alongside a bundled hl.exe - not needed just to run the game during development).
if ($BinDir) {
	Copy-Item $outHdll $BinDir -Force
	Stage-VlcRuntime $rt $BinDir
	Write-Host "Also staged into $BinDir"
}

Write-Host "Done."
