# heapvlc

<a href="https://lib.haxe.org/p/heapvlc">
	<img src="https://heroeyad.github.io/heapvlc/api/logo.png" align="center" />
</a>

Video playback for [Heaps](https://heaps.io/) on the HashLink target, via [libVLC](https://wiki.videolan.org/LibVLC).

Currently Supports Windows and Linux (special thanks to [swordcube](https://github.com/swordcube) on adding [it](https://github.com/HeroEyad/heapvlc/pull/2))

`heapvlc.HeapVideo` is a standalone `h2d.Object` that decodes video frames through libVLC and
uploads them into a dynamic Heaps texture, shown via its `bitmap` child. Since libVLC does its
own decoding, `play()` accepts anything libVLC supports (mp4, mkv, webm, ...) as well as
streaming URLs.

Native playback is backed by `native/vlc.c`, compiled into `vlc.hdll` and loaded through
`heapvlc.LibVLC`'s `@:hlNative` bindings. The vendored libVLC SDK and the diagnostic-log wiring
both trace back to [MAJigsaw77](https://github.com/MAJigsaw77)'s libVLC/HashLink binding work in
[hxvlc](https://github.com/MAJigsaw77/hxvlc)
See `native/vlc.c` for specifics on what came from
where.

## Requirements

- Haxe with the [Heaps](https://heaps.io/) library installed.
- The HashLink (`hl`) target - `heapvlc` only compiles under `-hl`.
- `vlc.hdll`, built from `native/vlc.c` (see below), staged next to `hl.exe`.
- A libVLC 3.x runtime (`libvlc.dll`, `libvlccore.dll`, `plugins/`, and ideally `lua/` for
  resolving video-site URLs like YouTube) staged next to `hl.exe` as well.

## Building the native extension

`vlc.hdll` isn't prebuilt or vendored - build it locally with the provided scripts:

Windows:
```powershell
powershell -ExecutionPolicy Bypass -File native/build.ps1 [-BinDir path\to\game\bin]
```

Linux:
```bash
bash ./native/build.sh
```

This needs MSVC (Visual Studio Build Tools with the "Desktop development with C++" workload) and
a local libVLC 3.x SDK. Headers and import libs are vendored under `native/include` and
`native/lib`; the runtime DLLs and plugins are not (they're tens of MB), so the script pulls them
from an existing VLC install, `$env:VLC_SDK_DIR`, or a local `hxvlc` haxelib install.

The script compiles `vlc.hdll` into `native/bin/`, then copies both the `.hdll` and the libVLC
runtime next to `hl.exe` - HashLink's `.hdll` loader only searches next to `hl.exe`, not the
working directory, so that's the copy that actually matters for `hl yourgame.hl` to find it.
Pass `-BinDir` to also copy both into a consuming project's own `bin/`.

## Usage

```haxe
import heapvlc.HeapVideo;

class Main extends hxd.App {
	override function init() {
		var video = new HeapVideo(s2d);
		video.loop = true;
		video.onFormatSetup = (w, h) -> trace('video is ${w}x${h}');
		video.onEndReached = () -> trace("looped");
		video.play("assets/intro.mp4");
	}
}
```

Streaming a URL works the same way - `load()`/`play()` auto-detect a `scheme://` prefix:

```haxe
video.play("https://example.com/stream.m3u8");
```

### Fitting into a target size

Set `fitWidth`/`fitHeight` (either or both) before or after `play()` to scale `bitmap` down
(never up) to fit, centered on whichever axes are set, once the native pixel size is known:

```haxe
video.fitWidth = 1280;
video.fitHeight = 720;
```

### Playback control

```haxe
video.pause();
video.resume();
video.position = 0.5;   // seek to 50%, normalized 0..1
video.time = 30000;     // seek to 30s, in milliseconds
video.volume = 50;
video.muted = true;
video.rate = 1.5;       // 1.5x speed; 1.0 is normal
video.stop();           // stops playback and frees the native player
video.destroy();        // stop() + removes the object from the scene
```

### Audio/subtitle tracks

Track ids come from libVLC itself - not necessarily 0-based or contiguous - so enumerate what's
valid via the `*TrackCount` properties rather than assuming a range. `-1` means none/disabled.

```haxe
trace('${video.audioTrackCount} audio track(s), current: ${video.audioTrack}');
video.subtitleTrack = -1; // disable subtitles
```

### Errors

```haxe
video.onError = () -> trace('playback error: ${video.getLog()}');
```

`onError` fires once per error (e.g. a stream that drops mid-play, or a decoder failure after
`play()` already succeeded) - these are usually asynchronous failures that `play()`/`load()`
themselves won't have thrown for, since they succeeded synchronously at the time.

### Diagnostics

libVLC's own errors (`libvlc_errmsg()`) are only set for calls that fail synchronously - a lot of
real-world failures, like a URL that "opens" fine but whose stream never resolves, don't set them
at all. `load()`/`play()` fall back to libVLC's diagnostic log when that happens, and it's also
available directly:

```haxe
trace(video.getLog());
```

## API

See [API Documentation](https://heroeyad.github.io/heapvlc/api/index.html) for further details!

## License

MIT. Note that distributing a working install also means shipping libVLC runtime binaries
(LGPL/GPL) — see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
