package heapvlc;

#if !hl
#error "heapvlc.LibVLC requires the hl target (see native/build.ps1 to build vlc.hdll)"
#end

#if (haxe_ver < 4.0)
#error "heapvlc requires Haxe >= 4.0 (uses hl.Abstract, @:hlNative and other Haxe 4 hl-target features)"
#end

/**
	A handle to a native `hl_vlc` player instance, backed by libVLC.
	See native/vlc.c for the implementation.
**/
typedef VLCHandle = hl.Abstract<"hl_vlc">;

/**
	Raw `@:hlNative` bindings to `vlc.hdll` (native/vlc.c), which wraps libVLC (https://wiki.videolan.org/LibVLC). 
	The vendored SDK under native/{include,lib} and the ideato surface libVLC's own diagnostic log (see `get_log`) both trace back to MAJigsaw77's work on libVLC/HashLink bindings (https://github.com/MAJigsaw77/hxvlc) - see native/vlc.c for specifics on what came from where.
**/
@:hlNative("vlc", "vlc_")
@:build(heapvlc.macro.Checks.run())
class LibVLC {

	public static function global_init(pluginsPath:hl.Bytes):Bool {
		return false;
	}

	public static function global_shutdown():Void {}

	public static function get_error(out:hl.Bytes, maxLen:Int):Int {
		return 0;
	}

	/** Copies libVLC's diagnostic log since the last `open()` into `out`. Non-destructive. **/
	public static function get_log(out:hl.Bytes, maxLen:Int):Int {
		return 0;
	}

	public static function open(path:hl.Bytes, isUrl:Bool):VLCHandle {
		return null;
	}

	public static function play(v:VLCHandle):Bool {
		return false;
	}

	public static function set_pause(v:VLCHandle, pause:Bool):Void {}

	public static function stop(v:VLCHandle):Void {}

	public static function is_playing(v:VLCHandle):Bool {
		return false;
	}

	public static function has_ended(v:VLCHandle):Bool {
		return false;
	}

	public static function has_error(v:VLCHandle):Bool {
		return false;
	}

	/**
		Event-based: returns true once when libVLC's "playing" event has fired since the last
		call, then resets. Can fire again for the same handle, e.g. after pausing and resuming.
	**/
	public static function take_playing(v:VLCHandle):Bool {
		return false;
	}

	/** Returns true once the decoder has determined the video's pixel size. **/
	public static function get_size(v:VLCHandle, width:hl.Ref<Int>, height:hl.Ref<Int>):Bool {
		return false;
	}

	public static function has_frame(v:VLCHandle):Bool {
		return false;
	}

	public static function get_frame(v:VLCHandle, out:hl.Bytes, outCapacity:Int):Bool {
		return false;
	}

	/** Media duration in milliseconds. **/
	public static function get_length(v:VLCHandle):Float {
		return 0;
	}

	/** Playback position in milliseconds. **/
	public static function get_time(v:VLCHandle):Float {
		return 0;
	}

	public static function set_time(v:VLCHandle, ms:Float):Void {}

	/** Playback position, normalized 0..1. **/
	public static function get_position(v:VLCHandle):Float {
		return 0;
	}

	public static function set_position(v:VLCHandle, pos:Float):Void {}

	/** Volume, 0..100+ (100 = normal). **/
	public static function get_volume(v:VLCHandle):Int {
		return 0;
	}

	public static function set_volume(v:VLCHandle, volume:Int):Bool {
		return false;
	}

	public static function set_mute(v:VLCHandle, mute:Bool):Void {}

	/** Playback speed multiplier, e.g. `0.5` for half speed, `2.0` for double. **/
	public static function get_rate(v:VLCHandle):Single {
		return 1.0;
	}

	public static function set_rate(v:VLCHandle, rate:Single):Bool {
		return false;
	}

	public static function get_audio_track_count(v:VLCHandle):Int {
		return 0;
	}

	/** Currently selected audio track id, or `-1` if none/disabled. **/
	public static function get_audio_track(v:VLCHandle):Int {
		return -1;
	}

	public static function set_audio_track(v:VLCHandle, track:Int):Bool {
		return false;
	}

	public static function get_subtitle_track_count(v:VLCHandle):Int {
		return 0;
	}

	/** Currently selected subtitle track id, or `-1` if none/disabled. **/
	public static function get_subtitle_track(v:VLCHandle):Int {
		return -1;
	}

	public static function set_subtitle_track(v:VLCHandle, track:Int):Bool {
		return false;
	}

	public static function close(v:VLCHandle):Void {}

}
