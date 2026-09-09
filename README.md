# heapvlc

<a href="https://lib.haxe.org/p/heapvlc">
	<img src="https://heroeyad.github.io/heapvlc/api/logo.png" align="center" />
</a>

Video playback for [Heaps](https://heaps.io/) on the HashLink target, via [libVLC](https://wiki.videolan.org/LibVLC).

Currently supports Windows and Linux (special thanks to [swordcube](https://github.com/swordcube) for adding [it](https://github.com/HeroEyad/heapvlc/pull/2)).

`heapvlc.HeapVideo` is a standalone `h2d.Object` that decodes video frames through libVLC and uploads them into a dynamic Heaps texture, shown via its `bitmap` child. Since libVLC does its own decoding, `play()` accepts anything libVLC supports (mp4, mkv, webm, ...) as well as streaming URLs.

Native playback is backed by `native/vlc.c`, compiled into `vlc.hdll` and loaded through `heapvlc.LibVLC`'s `@:hlNative` bindings. 
The vendored libVLC SDK and the diagnostic-log wiring both trace back to [MAJigsaw77](https://github.com/MAJigsaw77)'s libVLC/HashLink binding work in [hxvlc](https://github.com/MAJigsaw77/hxvlc). 
See `native/vlc.c` for specifics on what came from where.

## Requirements

- Haxe with the [Heaps](https://heaps.io/) library installed.
- The HashLink (`hl`) target -- `heapvlc` only compiles under `-hl`.
- `vlc.hdll`, built from `native/vlc.c` (see below), staged next to `hl.exe`.
- A libVLC 3.x runtime (`libvlc.dll`, `libvlccore.dll`, `plugins/`, and ideally `lua/` for resolving video-site URLs like YouTube) staged next to `hl.exe` as well.

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

This needs MSVC (Visual Studio Build Tools with "Desktop development with C++") and a local libVLC 3.x SDK. 
Headers and import libs are already vendored under `native/include` and `native/lib`, but the runtime DLLs and plugins aren't (they're tens of MB), so the script grabs them from an existing VLC install, `$env:VLC_SDK_DIR`, or a local `hxvlc`  haxelib install.

The script compiles `vlc.hdll` into `native/bin/`, then copies both the `.hdll` and the libVLC runtime next to `hl.exe`. HashLink's `.hdll` loader only searches next to `hl.exe`, not the working directory, so that copy is the one that actually matters for `hl yourgame.hl` to find it.
Pass `-BinDir` if you also want both copied into a consuming project's own `bin/`.

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

Streaming a URL works the same way: `load()`/`play()` auto-detect a `scheme://` prefix:

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
video.position = 0.5; // seek to 50%, normalized 0..1
video.time = 30000; // seek to 30s, in milliseconds
video.volume = 50;
video.muted = true;
video.rate = 1.5; // 1.5x speed; 1.0 is normal
video.stop(); // stops playback and frees the native player
video.destroy(); // stop() + removes the object from the scene
```

### Audio/subtitle tracks

Track ids come from libVLC itself, so don't assume they start at 0 or run in order.. some can be skipped entirely. 
Always check what's actually available using the `*TrackCount` properties instead of guessing a range.
A value of `-1` just means none selected / disabled.

```haxe
trace('${video.audioTrackCount} audio track(s), current: ${video.audioTrack}');
video.subtitleTrack = -1; // disable subtitles
```

### Errors

```haxe
video.onError = () -> trace('playback error: ${video.getLog()}');
```

`onError` fires once per error: think a stream that drops mid-play, or a decoder failure that shows up after `play()` already returned successfully. 
These are async failures, so `play()`/`load()` won't throw for them directly since they'd already succeeded synchronously by that point.

### Diagnostics

libVLC's own errors (`libvlc_errmsg()`) only get set when a call fails synchronously: plenty of real-world failures, like a URL that "opens" fine but the stream just never resolves, won't set anything there at all.
When that happens, `load()`/`play()` fall back to libVLC's diagnostic log instead, which is also exposed directly if you need it:

```haxe
trace(video.getLog());
```

## API

See [API Documentation](https://heroeyad.github.io/heapvlc/api/index.html) for further details!

## License

MIT. 
Note that distributing a working install also means shipping libVLC runtime binaries!
(LGPL/GPL)
See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
