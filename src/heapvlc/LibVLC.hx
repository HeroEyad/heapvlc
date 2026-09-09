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
@:hlNative("vlc")
@:build(heapvlc.macro.Checks.run())
class LibVLC {
	// taken from hxvlc:
	// https://github.com/MAJigsaw77/hxvlc/blob/main/source/hxvlc/impl/Instance.hx#L58
	// only thing really changed from this is the removal of the dummy audio output
	public static function get_default_args():Array<String> {
		final args:Array<String> = [];

		// left over from hxvlc, idk if i should keep this or not
		#if (android || ios)
		args.push("--audio-resampler=soxr"); // High-quality audio resampler (default in VLC 4.0)
		#end
		
		args.push("--ignore-config"); // Ignore any existing VLC config files
		args.push("--drop-late-frames"); // Drop late video frames instead of trying to render them
		args.push("--intf=none"); // Disable interface / UI
		args.push("--vout=vdummy"); // Disable video output (we use vmem)
		args.push("--text-renderer=freetype"); // Use Freetype for subtitles/text overlays
		args.push("--no-color"); // Disable colored console output
		args.push("--no-lua"); // Disable Lua scripting engine
		args.push("--no-interact"); // Disable interaction prompts
		args.push("--no-keyboard-events"); // Disable keyboard input
		args.push("--no-mouse-events"); // Disable mouse events
		args.push("--no-snapshot-preview"); // Disable snapshot previews
		args.push("--no-sout-keep"); // Disable streaming output persistence
		args.push("--no-sub-autodetect-file"); // Don’t automatically load subtitle files
		args.push("--no-video-title-show"); // Don’t show video title overlay at playback start
		
		// left over from hxvlc, idk if i should keep this or not		
		#if (macos || ios)
		args.push("--no-videotoolbox"); // Disable VideoToolbox hardware decoding (to make subtitles work)
		#end

		args.push("--no-volume-save"); // Don’t save last volume level
		args.push("--no-xlib"); // Disable X11 output (irrelevant on Apple)

		#if HEAPVLC_VERBOSE
		args.push("--verbose=2"); // Verbose logging in my stdout?!?!?! I Can't Accept It :(
		#else
		args.push("--quiet"); // Don't print anything to stdout, shus  h!
		#end
		return args;
	}

	static function vlc_global_init( pluginsPath : hl.Bytes, args : hl.NativeArray<hl.Bytes> ) : Bool {
		return false;
	}

	public static function global_init(pluginsPath:String, args:Array<String>):Bool {
		var nargs = new hl.NativeArray<hl.Bytes>(args.length);
		for( i in 0...args.length )
			nargs[i] = @:privateAccess HeapVideo.toCString(args[i]);
		var pp = @:privateAccess HeapVideo.toCString(pluginsPath);
		return vlc_global_init(pp, nargs);
	}

	public static function vlc_global_shutdown():Void {}

	public static function vlc_get_error(out:hl.Bytes, maxLen:Int):Int {
		return 0;
	}

	/** Copies libVLC's diagnostic log since the last `open()` into `out`. Non-destructive. **/
	public static function vlc_get_log(out:hl.Bytes, maxLen:Int):Int {
		return 0;
	}

	public static function vlc_open(path:hl.Bytes, isUrl:Bool):VLCHandle {
		return null;
	}

	public static function vlc_play(v:VLCHandle):Bool {
		return false;
	}

	public static function vlc_set_pause(v:VLCHandle, pause:Bool):Void {}

	public static function vlc_stop(v:VLCHandle):Void {}

	public static function vlc_is_playing(v:VLCHandle):Bool {
		return false;
	}

	public static function vlc_has_ended(v:VLCHandle):Bool {
		return false;
	}

	public static function vlc_has_error(v:VLCHandle):Bool {
		return false;
	}

	/**
		Event-based: returns true once when libVLC's "playing" event has fired since the last
		call, then resets. Can fire again for the same handle, e.g. after pausing and resuming.
	**/
	public static function vlc_take_playing(v:VLCHandle):Bool {
		return false;
	}

	/** Returns true once the decoder has determined the video's pixel size. **/
	public static function vlc_get_size(v:VLCHandle, width:hl.Ref<Int>, height:hl.Ref<Int>):Bool {
		return false;
	}

	public static function vlc_has_frame(v:VLCHandle):Bool {
		return false;
	}

	public static function vlc_get_frame(v:VLCHandle, out:hl.Bytes, outCapacity:Int):Bool {
		return false;
	}

	/** Media duration in milliseconds. **/
	public static function vlc_get_length(v:VLCHandle):Float {
		return 0;
	}

	/** Playback position in milliseconds. **/
	public static function vlc_get_time(v:VLCHandle):Float {
		return 0;
	}

	public static function vlc_set_time(v:VLCHandle, ms:Float):Void {}

	/** Playback position, normalized 0..1. **/
	public static function vlc_get_position(v:VLCHandle):Float {
		return 0;
	}

	public static function vlc_set_position(v:VLCHandle, pos:Float):Void {}

	/** Volume, 0..100+ (100 = normal). **/
	public static function vlc_get_volume(v:VLCHandle):Int {
		return 0;
	}

	public static function vlc_set_volume(v:VLCHandle, volume:Int):Bool {
		return false;
	}

	public static function vlc_set_mute(v:VLCHandle, mute:Bool):Void {}

	/** Playback speed multiplier, e.g. `0.5` for half speed, `2.0` for double. **/
	public static function vlc_get_rate(v:VLCHandle):Single {
		return 1.0;
	}

	public static function vlc_set_rate(v:VLCHandle, rate:Single):Bool {
		return false;
	}

	public static function vlc_get_audio_track_count(v:VLCHandle):Int {
		return 0;
	}

	/** Currently selected audio track id, or `-1` if none/disabled. **/
	public static function vlc_get_audio_track(v:VLCHandle):Int {
		return -1;
	}

	public static function vlc_set_audio_track(v:VLCHandle, track:Int):Bool {
		return false;
	}

	public static function vlc_get_subtitle_track_count(v:VLCHandle):Int {
		return 0;
	}

	/** Currently selected subtitle track id, or `-1` if none/disabled. **/
	public static function vlc_get_subtitle_track(v:VLCHandle):Int {
		return -1;
	}

	public static function vlc_set_subtitle_track(v:VLCHandle, track:Int):Bool {
		return false;
	}

	public static function vlc_close(v:VLCHandle):Void {}

}
