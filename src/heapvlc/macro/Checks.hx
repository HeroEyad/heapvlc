package heapvlc.macro;

#if macro
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

	static function checkNativeLibrary():Void {
		var cls = Context.getLocalClass().get();
		var modulePath = Context.resolvePath(cls.module.split(".").join("/") + ".hx");
		var libRoot = Path.directory(Path.directory(Path.directory(modulePath)));
		var hdll = Path.join([libRoot, "native", "bin", "vlc.hdll"]);
		if (!FileSystem.exists(hdll)) {
			Context.warning(
				'heapvlc: native/bin/vlc.hdll not found (expected at $hdll). '
				+ 'Run native/build.ps1 before running anything that uses HeapVideo/LibVLC, '
				+ 'or native calls will fail at runtime.',
				Context.currentPos()
			);
		}
	}
}
#end
