package heapvlc;

#if !hl
#error "heapvlc.HeapVideo requires the hl target (see native/build.ps1)"
#end

#if (haxe_ver < 4.0)
#error "heapvlc requires Haxe >= 4.0 (uses hl.Abstract, @:hlNative and other Haxe 4 hl-target features)"
#end

import heapvlc.LibVLC;
import heapvlc.LibVLC.VLCHandle;

/**
	Plays video through libVLC, decoding frames into a dynamic heaps texture shown via `bitmap`.
	Backed by native/vlc.c (built into `vlc.hdll` by native/build.ps1 / native/build.sh), which has to exist before use.

	libVLC does its own decoding, so `play()` takes anything it supports (mp4, mkv, webm, etc.)
	and also supports URL streaming.

	Standalone `h2d.Object` - doesn't depend on any particular host engine's update convention,
	just Heaps' own per-frame `sync()`, so `new heapvlc.HeapVideo(parent)` works in any Heaps scene.
**/
@:build(heapvlc.macro.Checks.run())
class HeapVideo extends h2d.Object {

	/** The `h2d.Bitmap` child that displays decoded video frames. Untextured until the first frame arrives. **/
	public var bitmap(default, null):h2d.Bitmap;

	/** When true, playback restarts from the beginning instead of stopping at `onEndReached`. **/
	public var loop:Bool = false;

	/** Fires when playback reaches the end of the media - after a loop restart, or after `stop()` on a non-looping end. **/
	public var onEndReached:Void->Void;

	/** Fires once the decoder reports the video's pixel size and `bitmap`'s texture has been (re)created. **/
	public var onFormatSetup:(width:Int, height:Int) -> Void;

	/** Fires when libVLC's "playing" event is observed; see `LibVLC.vlc_take_playing`. Can fire again after a pause/resume. **/
	public var onPlaying:Void->Void;

	/** Fires once when the native player reports a playback error; call `getLog()` for details. **/
	public var onError:Void->Void;

	/**
		When set, `bitmap` is scaled down (never up) to fit within this size and centered on
		whichever axes are set, once the native dimensions are known. Set before or after play().
	**/
	public var fitWidth:Null<Float>;
	public var fitHeight:Null<Float>;

	/** Whether the native player considers itself currently playing. `false` when nothing is loaded. **/
	public var playing(get, never):Bool;
	/** Media duration in milliseconds, or `0` when nothing is loaded. **/
	public var duration(get, never):Float;
	/** Playback position, normalized `0..1`. Writable to seek; `0` when nothing is loaded. **/
	public var position(get, set):Float;
	/** Playback position in milliseconds. Writable to seek; `0` when nothing is loaded. **/
	public var time(get, set):Float;
	/** Volume, `0..100+` (`100` = normal). Defaults to `100` when nothing is loaded. **/
	public var volume(get, set):Int;
	/** Whether audio output is muted. **/
	public var muted(default, set):Bool = false;
	/** Playback speed multiplier, e.g. `0.5` for half speed, `2.0` for double. `1.0` when nothing is loaded. **/
	public var rate(get, set):Float;

	/** Number of available audio tracks, or `0` when nothing is loaded. **/
	public var audioTrackCount(get, never):Int;
	/** Selected audio track id (not necessarily 0-based - see `audioTrackCount`), or `-1` for none. **/
	public var audioTrack(get, set):Int;
	/** Number of available subtitle tracks, or `0` when nothing is loaded. **/
	public var subtitleTrackCount(get, never):Int;
	/** Selected subtitle track id (not necessarily 0-based - see `subtitleTrackCount`), or `-1` for none/disabled. **/
	public var subtitleTrack(get, set):Int;

	/** Native libVLC player handle for the currently loaded media, or `null` when nothing is loaded. **/
	var handle:VLCHandle;
	/** GPU texture that `bitmap.tile` wraps; recreated whenever the decoded frame size changes. **/
	var texture:h3d.mat.Texture;
	/** CPU-side buffer that `LibVLC.vlc_get_frame` fills each frame before it's uploaded to `texture`. **/
	var frameBytes:haxe.io.Bytes;
	/** Last known decoded frame width in pixels, or `0` before the format callback has fired. **/
	var frameWidth:Int = 0;
	/** Last known decoded frame height in pixels, or `0` before the format callback has fired. **/
	var frameHeight:Int = 0;
	/** Whether `frameWidth`/`frameHeight`/`texture` reflect a size reported by the decoder yet. **/
	var sizeKnown:Bool = false;
	/** Whether `onError` has already fired for the current `handle`'s error state.. `LibVLC.vlc_has_error` doesn't reset on its own. **/
	var errorSeen:Bool = false;

	/** Whether `LibVLC.vlc_global_init` has already been called for this process. **/
	static var initialized = false;

	/**
		Creates the player and its `bitmap`, optionally attaching it under `parent`. Runs one-time
		libVLC init if needed.
		@param parent Optional Heaps object to attach this player under.
	**/
	public function new(?parent:h2d.Object) {
		super(parent);
		bitmap = new h2d.Bitmap(this);
		ensureInit();
	}

	/** Runs libVLC's process-wide `global_init` exactly once, no matter how many players are created. **/
	static function ensureInit(?args:Array<String>):Void {
		if (initialized) return;
		initialized = true;
		// null: libVLC finds its plugins/ folder next to libvlc.dll by itself.
		LibVLC.global_init(null, args ?? LibVLC.get_default_args());
	}

	/** Matches a `scheme://` prefix, used by `load()` to auto-detect a URL vs. a local file path. **/
	static var urlScheme = ~/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//;

	/**
		Stops any current playback and opens `path` (a local file path or a streaming URL) for
		this player, without starting playback.
		@param path A local file path or a streaming URL.
		@param isUrl Whether `path` is a URL. Auto-detected from a `scheme://` prefix when omitted.
		@return This player, for chaining.
		@throws String if libVLC fails to open the source.
	**/
	public function load(path:String, ?isUrl:Bool):HeapVideo {
		stop();
		var url = isUrl != null ? isUrl : urlScheme.match(path);
		handle = LibVLC.vlc_open(toCString(path), url);
		if (handle == null)
			throw 'HeapVideo: failed to open "$path"' + errorSuffix();
		return this;
	}

	/**
		Converts `s` to a null-terminated byte buffer for passing to libVLC as a C `const char*`.
		`haxe.io.Bytes.ofString` isn't null-terminated on its own and libVLC would read past the
		end into garbage without the trailing null this appends.
		@param s The string to convert.
		@return A null-terminated byte buffer suitable for a C `const char*` parameter.
	**/
	static function toCString(s:String):hl.Bytes {
		if(s == null) return null;
		var b = haxe.io.Bytes.ofString(s);
		var out = haxe.io.Bytes.alloc(b.length + 1);
		out.blit(0, b, 0, b.length);
		out.set(b.length, 0);
		return out.getData();
	}

	/**
		Starts playback. Pass `path` to `load()` it first, or call after a previous `load()`.
		@param path Optional media to `load()` before playing.
		@param isUrl Forwarded to `load()` when `path` is given.
		@return This player, for chaining.
		@throws String if nothing is loaded or if libVLC fails to start playback.
	**/
	public function play(?path:String, ?isUrl:Bool):HeapVideo {
		if (path != null) load(path, isUrl);
		if (handle == null)
			throw "HeapVideo: play() called with nothing loaded - call load() or pass a path";
		errorSeen = false; // vlc_play() resets the native errored flag along with starting playback
		if (!LibVLC.vlc_play(handle))
			throw "HeapVideo: failed to play" + errorSuffix();
		return this;
	}

	/**
		Builds a `" (...)"` suffix describing why the last libVLC call failed, for appending to
		thrown error messages.
		@return A parenthesized error message, a fallback diagnostic log, or `""` if neither is available.
	**/
	function errorSuffix():String {
		var buf = haxe.io.Bytes.alloc(256);
		var len = LibVLC.vlc_get_error(buf, buf.length);
		if (len > 0) return " (" + buf.getString(0, len) + ")";
		// libvlc_errmsg() is only set by calls that fail synchronously; a lot of real failures
		// (e.g. a URL that opens "fine" but whose stream never resolves) don't set it at all,
		// so fall back to whatever it logged instead of reporting nothing.
		var log = getLog();
		return log.length > 0 ? "\n" + log : "";
	}

	/**
		Recent libVLC diagnostic log (info/warning/error) since this player's last `load()`/
		`play()` call - useful when playback silently doesn't progress (wrong URL, unresolved
		stream, missing codec, ...) without `open()`/`play()` themselves reporting failure.
		@return The diagnostic log text, or `""` if there's nothing logged.
	**/
	public function getLog():String {
		var buf = haxe.io.Bytes.alloc(8192);
		var len = LibVLC.vlc_get_log(buf, buf.length);
		return buf.getString(0, len);
	}

	/** Pauses playback. No-op when nothing is loaded. **/
	public function pause():Void {
		if (handle != null) LibVLC.vlc_set_pause(handle, true);
	}

	/** Resumes playback after `pause()`. No-op when nothing is loaded. **/
	public function resume():Void {
		if (handle != null) LibVLC.vlc_set_pause(handle, false);
	}

	/** stops playback and frees the native player. safe to call when nothing's playing. **/
	public function stop():Void {
		if (handle != null) {
			LibVLC.vlc_close(handle);
			handle = null;
		}
		sizeKnown = false;
		frameWidth = 0;
		frameHeight = 0;
		errorSeen = false;
	}

	// destroys the object.
	public function destroy():Void {
		stop();
		remove();
	}

	/**
		Per-frame update: detects and reacts to a (re)reported decoder frame size, uploads the
		latest decoded frame to `texture`, and dispatches `onPlaying`/`onEndReached`/loop-restart
		based on the native player's state.
		@param ctx The Heaps render context for this frame, forwarded to `super.sync()`.
	**/
	override function sync(ctx:h2d.RenderContext):Void {
		super.sync(ctx);
		if (handle == null) return;

		// checked every frame, not once: the format callback can fire again after the first time
		var w = 0, h = 0;
		if (LibVLC.vlc_get_size(handle, w, h) && w > 0 && h > 0 && (w != frameWidth || h != frameHeight)) {
			frameWidth = w;
			frameHeight = h;
			sizeKnown = true;
			frameBytes = haxe.io.Bytes.alloc(w * h * 4);
			texture?.dispose();
			texture = new h3d.mat.Texture(w, h, [Dynamic], BGRA);
			bitmap.tile = h2d.Tile.fromTexture(texture);
			if (fitWidth != null || fitHeight != null) {
				var scale = 1.0;
				if (fitWidth != null) scale = Math.min(scale, fitWidth / w);
				if (fitHeight != null) scale = Math.min(scale, fitHeight / h);
				bitmap.scaleX = bitmap.scaleY = scale;
				bitmap.x = fitWidth != null ? (fitWidth - w * scale) / 2 : 0;
				bitmap.y = fitHeight != null ? (fitHeight - h * scale) / 2 : 0;
			}
			if (onFormatSetup != null) onFormatSetup(w, h);
		}

		if (sizeKnown && LibVLC.vlc_has_frame(handle)) {
			if (LibVLC.vlc_get_frame(handle, frameBytes, frameBytes.length))
				texture.uploadPixels(new hxd.Pixels(frameWidth, frameHeight, frameBytes, BGRA));
		}

		if (LibVLC.vlc_take_playing(handle) && onPlaying != null)
			onPlaying();

		if (!errorSeen && LibVLC.vlc_has_error(handle)) {
			errorSeen = true;
			if (onError != null) onError();
		}

		if (LibVLC.vlc_has_ended(handle)) {
			if (loop) {
				LibVLC.vlc_stop(handle);
				sizeKnown = false;
				LibVLC.vlc_play(handle);
				if (onEndReached != null) onEndReached();
			} else {
				var cb = onEndReached;
				stop();
				if (cb != null) cb();
			}
		}
	}

	inline function get_playing() return handle != null && LibVLC.vlc_is_playing(handle);
	inline function get_duration() return handle == null ? 0. : LibVLC.vlc_get_length(handle);
	inline function get_position() return handle == null ? 0. : LibVLC.vlc_get_position(handle);
	function set_position(p:Float) { if (handle != null) LibVLC.vlc_set_position(handle, p); return p; }
	inline function get_time() return handle == null ? 0. : LibVLC.vlc_get_time(handle);
	function set_time(t:Float) { if (handle != null) LibVLC.vlc_set_time(handle, t); return t; }
	inline function get_volume() return handle == null ? 100 : LibVLC.vlc_get_volume(handle);
	function set_volume(v:Int) { if (handle != null) LibVLC.vlc_set_volume(handle, v); return v; }
	function set_muted(m:Bool) { if (handle != null) LibVLC.vlc_set_mute(handle, m); return muted = m; }

	inline function get_rate() return handle == null ? 1. : LibVLC.vlc_get_rate(handle);
	function set_rate(r:Float) { if (handle != null) LibVLC.vlc_set_rate(handle, r); return r; }

	inline function get_audioTrackCount() return handle == null ? 0 : LibVLC.vlc_get_audio_track_count(handle);
	inline function get_audioTrack() return handle == null ? -1 : LibVLC.vlc_get_audio_track(handle);
	function set_audioTrack(t:Int) { if (handle != null) LibVLC.vlc_set_audio_track(handle, t); return t; }

	inline function get_subtitleTrackCount() return handle == null ? 0 : LibVLC.vlc_get_subtitle_track_count(handle);
	inline function get_subtitleTrack() return handle == null ? -1 : LibVLC.vlc_get_subtitle_track(handle);
	function set_subtitleTrack(t:Int) { if (handle != null) LibVLC.vlc_set_subtitle_track(handle, t); return t; }

}
