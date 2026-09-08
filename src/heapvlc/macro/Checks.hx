package heapvlc.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.io.Path;
import sys.FileSystem;

class Checks {
	static var ran = false;

	public static function run():Array<Field> {
		if (!ran) {
			ran = true;
			checkNativeLibrary();
		}
		return Context.getBuildFields();
	}

	static function checkPlatform():Void {
		var supported = ["Windows", "Linux"];
		var currentPlatform = Sys.systemName();

		if(!supported.contains(currentPlatform)) {
			Context.error(
				"heapvlc: " + currentPlatform + " is not supported",
				Context.currentPos()
			);
		} else {
			var os = currentPlatform.toLowerCase();
			if(!Context.defined(os))
				Compiler.define(os);
		}
	}

	static function checkNativeLibrary():Void {
		var cls = Context.getLocalClass().get();
		var modulePath = Context.resolvePath(cls.module.split(".").join("/") + ".hx");
		var libRoot = Path.directory(Path.directory(Path.directory(modulePath)));
		var hdll = Path.join([libRoot, "native", "bin", "vlc.hdll"]);
		if (!FileSystem.exists(hdll)) {
			Context.warning(
				'heapvlc: native/bin/vlc.hdll not found (expected at $hdll). '
				+ 'Run ${Sys.systemName() == "Windows" ? "native/build.ps1" : "native/build.sh"} before running anything that uses HeapVideo/LibVLC, '
				+ 'or native calls will fail at runtime.',
				Context.currentPos()
			);
		}
	}
}
#end
