#!/usr/bin/env bash
#
# builds native/vlc.c into <lib>/native/bin/vlc.hdll (the hashlink native ext heapvlc.HeapVLC /
# heapvlc.LibVLC call into), then stages the libVLC runtime (libvlc.so/libvlccore.so + plugins)
# next to hl - hashlink's .hdll loader on Linux resolves via dlopen(), which follows the
# dynamic linker's normal search path (RPATH/RUNPATH, LD_LIBRARY_PATH, ld.so.conf, then the
# standard system dirs) rather than "next to the exe" like on Windows. In practice that means:
# if libvlc/libvlccore are already installed as system packages, nothing needs staging next to
# hl at all - apt/dnf's ldconfig entry already covers it. This script still offers a -BinDir-style
# staging step for people who want a self-contained/portable build (e.g. bundling a private
# libvlc alongside a bundled hl), but it's optional on Linux in a way it wasn't on Windows.
#
# usage:
#   ./native/build.sh [--bin-dir path/to/game/bin]
#
# needs gcc (or clang) and a local libVLC 3.x dev package (libvlc-dev / vlc-dev, or a
# self-built SDK). headers + import libs live under native/{include,lib} if vendored; otherwise
# pkg-config's vlc.pc / libvlc.pc is used to find the system install.

set -euo pipefail

BIN_DIR=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--bin-dir)
			BIN_DIR="$2"
			shift 2
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

NATIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$NATIVE_DIR/bin"
mkdir -p "$OUT_DIR"

# 1. find a C compiler. gcc first, clang as fallback - there's no MSVC-style "locate the
#    toolchain" step needed since these are normally already on PATH via the distro.
if command -v gcc >/dev/null 2>&1; then
	CC="gcc"
elif command -v clang >/dev/null 2>&1; then
	CC="clang"
else
	echo "No C compiler found. Install gcc (e.g. 'sudo apt install build-essential')." >&2
	exit 1
fi
echo "Using compiler: $CC"

# 2. find HashLink headers/libs. On Linux these usually come from building hashlink from
#    source (make && sudo make install), which installs hl.h to /usr/include/hashlink and
#    libhl.so to /usr/lib. Allow overriding via env vars for non-standard installs.
HL_INCLUDE="${HL_INCLUDE:-/usr/include/hashlink}"
HL_LIB_DIR="${HL_LIB_DIR:-/usr/lib}"

if [[ ! -f "$HL_INCLUDE/hl.h" ]]; then
	# fall back to common alternate include dir
	if [[ -f /usr/local/include/hashlink/hl.h ]]; then
		HL_INCLUDE="/usr/local/include/hashlink"
		HL_LIB_DIR="${HL_LIB_DIR:-/usr/local/lib}"
	else
		echo "HashLink SDK not found at $HL_INCLUDE (expected hl.h). Set \$HL_INCLUDE / \$HL_LIB_DIR." >&2
		exit 1
	fi
fi

# 3. find libVLC 3.x dev files. Prefer pkg-config (covers apt/dnf-installed libvlc-dev),
#    fall back to a vendored SDK under native/{include,lib} like the Windows version used.
VLC_INCLUDE=""
VLC_LIB_DIR=""
VLC_CFLAGS=""
VLC_LIBS=""

if pkg-config --exists libvlc 2>/dev/null; then
	VLC_CFLAGS="$(pkg-config --cflags libvlc)"
	VLC_LIBS="$(pkg-config --libs libvlc)"
	echo "Found libvlc via pkg-config"
elif [[ -f "$NATIVE_DIR/include/vlc/vlc.h" ]]; then
	VLC_INCLUDE="$NATIVE_DIR/include"
	VLC_LIB_DIR="$NATIVE_DIR/lib"
	VLC_CFLAGS="-I$VLC_INCLUDE"
	VLC_LIBS="-L$VLC_LIB_DIR -lvlc -lvlccore"
	echo "Found vendored libvlc SDK under $NATIVE_DIR"
else
	echo "libvlc dev files not found. Install 'libvlc-dev' (Debian/Ubuntu) or 'vlc-devel'" >&2
	echo "(Fedora), or vendor headers/libs under native/include and native/lib." >&2
	exit 1
fi

# 4. compile vlc.c -> native/bin/vlc.hdll
#    -shared -fPIC builds a .so; hashlink's .hdll on Linux IS just an .so with a different
#    extension, loaded via dlopen, so no separate "import lib" step like MSVC's /IMPLIB.
OUT_HDLL="$OUT_DIR/vlc.hdll"

"$CC" -O2 -fPIC -shared \
	-I "$HL_INCLUDE" $VLC_CFLAGS \
	"$NATIVE_DIR/vlc.c" \
	-o "$OUT_HDLL" \
	-L "$HL_LIB_DIR" -lhl $VLC_LIBS \
	-Wl,-rpath,'$ORIGIN'

echo "Built $OUT_HDLL"

# 5. stage the runtime (libvlc.so/libvlccore.so + plugins) into a target dir. Only needed for
#    a portable/self-contained deployment - if libvlc-dev/vlc came from the system package
#    manager, the runtime libs and plugin dir (usually
#    /usr/lib/x86_64-linux-gnu/vlc/plugins or /usr/lib/vlc/plugins) are already on the
#    system's dynamic loader path and VLC_PLUGIN_PATH doesn't need to be set.
find_vlc_runtime() {
	local libdir="" plugindir=""

	if [[ -n "${VLC_SDK_DIR:-}" && -f "$VLC_SDK_DIR/libvlc.so" ]]; then
		libdir="$VLC_SDK_DIR"
		plugindir="$VLC_SDK_DIR/plugins"
	else
		# ask the dynamic linker where the system libvlc actually lives
		local found
		found="$(ldconfig -p 2>/dev/null | grep 'libvlc\.so' | head -n1 | awk '{print $NF}')"
		if [[ -n "$found" ]]; then
			libdir="$(dirname "$found")"
			# plugin dir is conventionally <libdir>/vlc/plugins on most distros
			if [[ -d "$libdir/vlc/plugins" ]]; then
				plugindir="$libdir/vlc/plugins"
			fi
		fi
	fi

	if [[ -z "$libdir" ]]; then
		return 1
	fi
	echo "$libdir|$plugindir"
}

stage_vlc_runtime() {
	local target_dir="$1"
	local rt
	if ! rt="$(find_vlc_runtime)"; then
		echo "Warning: no libVLC runtime found (checked VLC_SDK_DIR, ldconfig). Copy" >&2
		echo "libvlc.so(.*), libvlccore.so(.*) and the vlc/plugins/ dir into $target_dir manually," >&2
		echo "or just rely on the system-installed vlc package + ldconfig." >&2
		return
	fi

	local libdir="${rt%%|*}"
	local plugindir="${rt##*|}"

	mkdir -p "$target_dir"

	# copy the .so files including version symlinks (libvlc.so.5 etc.), matching the actual
	# shared object names rather than just the dev-symlink 'libvlc.so'
	cp -a "$libdir"/libvlc.so* "$target_dir/" 2>/dev/null || true
	cp -a "$libdir"/libvlccore.so* "$target_dir/" 2>/dev/null || true

	if [[ -n "$plugindir" && -d "$plugindir" ]]; then
		local plugins_out="$target_dir/plugins"
		if [[ ! -d "$plugins_out" ]]; then
			echo "Copying VLC plugins from $plugindir into $target_dir (this can be 70-130MB, one-time)..."
			cp -a "$plugindir" "$plugins_out"
		fi
	else
		echo "Warning: no plugins dir found alongside $libdir - staged libvlc likely won't be able to play anything." >&2
	fi

	# note: unlike the Windows build, there's no separate lua/ directory to copy - on Linux
	# distro packages of VLC, the lua playlist-resolver scripts (used for YouTube/Vimeo/etc
	# URLs) live inside the plugins tree itself (share/lua under the VLC data dir), so they
	# come along for free as long as you're using a full system VLC install rather than a
	# stripped-down libvlc-only build. If you're vendoring a minimal SDK, check that
	# share/vlc/lua exists and copy it alongside plugins/ if not.

	echo "Staged libvlc runtime from $libdir into $target_dir"
}

# native/bin/ - this library's own build output, kept for reference/packaging.
stage_vlc_runtime "$OUT_DIR"

# On Linux there's no "next to hl" requirement the way Windows has "next to hl.exe" - the
# .hdll (an .so) is found via dlopen's normal search path once it's anywhere on
# LD_LIBRARY_PATH or a standard lib dir. Most setups just run `hl yourgame.hl` from the
# directory containing vlc.hdll, which works because '.' ends up searched for hdlls
# specifically (unlike Windows where only next-to-exe is searched). If you want it available
# system-wide, copy vlc.hdll to somewhere on LD_LIBRARY_PATH instead.

# optional: also copy into a consuming project's own bin/ (for packaging a standalone build).
if [[ -n "$BIN_DIR" ]]; then
	cp -f "$OUT_HDLL" "$BIN_DIR/"
	stage_vlc_runtime "$BIN_DIR"
	echo "Also staged into $BIN_DIR"
fi

echo "Done."