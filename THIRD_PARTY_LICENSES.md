# Third-party licenses

`heapvlc` itself is MIT licensed (see [LICENSE](LICENSE)). However, a working installation also includes libVLC runtime binaries next to `hl.exe` (see [README: Requirements](README.md#requirements)). These binaries have their own licenses, which are summarized below.

## libvlc.dll / libvlccore.dll: LGPL v2.1 or later

Copyright © VideoLAN and VLC authors. The libVLC core library is licensed under the [GNU Lesser General Public License v2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html), or any later version at your option.

`heapvlc` loads these as dynamic libraries. `vlc-windows.hdll` calls into `libvlc.dll` and `libvlccore.dll` at runtime rather than linking them statically. This means end users can replace the DLLs with their own modified or updated builds of libVLC.

If you redistribute `libvlc.dll` or `libvlccore.dll` with your project, you must:

* Include a copy of the LGPL v2.1 license text.
* Keep VideoLAN's copyright notice.
* Keep the DLLs dynamically loaded and replaceable. Do not statically link a modified version of libVLC into your own binary unless you also comply with the additional LGPL requirements for static linking.

## plugins/: GPL v2 or later

Many of the codec, demux, and output modules in libVLC's `plugins/` directory are licensed under the [GNU General Public License v2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html), or any later version, rather than the LGPL.

`heapvlc` needs this directory next to `hl.exe` for playback to work. If you distribute these plugins, the GPL requirements apply to the specific binaries you ship.

This means you must:

* Include a copy of the GPL v2 license text.
* Make sure recipients can obtain the corresponding source code for the exact plugin build you shipped. In practice, if you have not modified the plugins, you can point users to [VideoLAN's official source releases](https://www.videolan.org/vlc/download-sources.html) for the matching libVLC version.

## Vendored SDK headers and import libraries (`native/include`, `native/lib`)

The libVLC 3.x headers and import libraries included in this repository were sourced from [MAJigsaw77/hxvlc](https://github.com/MAJigsaw77/hxvlc), which is MIT licensed for its own code. Those files ultimately come from the official libVLC SDK.

See `native/vlc.c` for additional attribution details.

These headers and import libraries are used only at build time and are not included with the runtime distribution.

---

This file is provided for convenience and is not legal advice. If you are distributing `heapvlc` or a project built with it commercially, verify the license terms for the specific libVLC build you are using and consult a lawyer if necessary.
