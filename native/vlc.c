// HashLink native extension binding libVLC (https://wiki.videolan.org/LibVLC) for heapvlc.HeapVLC.
// Decodes video frames into an off-screen RGBA buffer via libvlc's memory callbacks, which the
// Haxe side polls once per frame and uploads into a Heaps texture. See src/heapvlc/HeapVLC.hx.
//
// Credit: the vendored libVLC 3.x SDK under include/ and lib/ was sourced from MAJigsaw77's
// hxvlc (https://github.com/MAJigsaw77/hxvlc), which bundles it for its own (hxcpp) target. The
// idea to hook libvlc_log_set() for diagnostics (see log_cb below) was likewise prompted by
// seeing it done in a separate HashLink-targeted libVLC binding attributed to MAJigsaw77; the
// implementation here differs (a polled buffer rather than calling back into Haxe closures from
// libVLC's own threads), but the idea to wire it up at all came from that reference.
#define HL_NAME(n) vlc_##n
#include <hl.h>
#include <string.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>
#include <vlc/vlc.h>

// A small spinlock lives directly inside hl_vlc to protect the fields that both
// libVLC's decode thread and the main HL thread access (pixels/width/height/hasFrame).
//
// We don't use hl_mutex_alloc() here because it creates a separate GC-managed block.
// Since hl_vlc is a MEM_KIND_FINALIZER block, the GC doesn't scan its contents, so
// storing a raw pointer to that mutex inside it isn't enough to keep the mutex alive.
// Under heavy allocation, the GC could think the mutex is unused and finalize it while
// the libVLC thread is still accessing it.
//
// Keeping the lock directly inside hl_vlc avoids that problem entirely. The lock is
// part of the same allocation and is never managed separately by the GC.
//
// The lock is built using compiler intrinsics instead of Windows' CRITICAL_SECTION.
// This avoids pulling in <windows.h>, which can clash with definitions already included
// indirectly through hl.h or libVLC. A spinlock also fits this use case well since the
// critical sections are extremely short: just a few field reads/writes or one memcpy,
// with no I/O or other long-running work while the lock is held.

#if defined(_MSC_VER)
#include <intrin.h>
typedef volatile long hl_vlc_lock;
#define VLC_LOCK_INIT(l) (*(l) = 0)
#define VLC_LOCK_DESTROY(l) ((void)0)
#define VLC_LOCK(l) do { while( _InterlockedCompareExchange((l), 1, 0) != 0 ) { } } while(0)
#define VLC_UNLOCK(l) _InterlockedExchange((l), 0)
#else
typedef volatile int hl_vlc_lock;
#define VLC_LOCK_INIT(l) (*(l) = 0)
#define VLC_LOCK_DESTROY(l) ((void)0)
#define VLC_LOCK(l) do { while( __sync_lock_test_and_set((l), 1) ) { } } while(0)
#define VLC_UNLOCK(l) __sync_lock_release(l)
#endif

typedef struct {
	void *finalizer;
	libvlc_media_t *media;
	libvlc_media_player_t *player;
	hl_vlc_lock lock;
	bool lockInited;
	unsigned width;
	unsigned height;
	unsigned char *pixels;
	bool hasFrame;
	volatile bool ended;
	volatile bool errored;
	volatile bool playingFired;
} hl_vlc;

static libvlc_instance_t *g_instance = NULL;

// Recent libVLC diagnostic log, captured via libvlc_log_set() below. Cleared at the start of
// each vlc_open() so a failed/silent open (e.g. an unresolvable URL) can be explained by reading
// this afterwards, instead of only having the single last libvlc_errmsg() (which many failures,
// like a lua playlist script not resolving a page, never actually set).
#define VLC_LOG_CAPACITY 16384
static char g_logBuf[VLC_LOG_CAPACITY];
static int g_logLen = 0;
static hl_vlc_lock g_logLock;

static void log_cb( void *data, int level, const libvlc_log_t *ctx, const char *fmt, va_list args ) {
	char line[1024];
	const char *tag;
	int tagLen, msgLen, total;
	switch( level ) {
	case LIBVLC_ERROR: tag = "[error] "; break;
	case LIBVLC_WARNING: tag = "[warn] "; break;
	case LIBVLC_NOTICE: tag = "[notice] "; break;
	default: tag = "[debug] "; break;
	}
	tagLen = (int)strlen(tag);
	msgLen = vsnprintf(line, sizeof(line), fmt, args);
	if( msgLen <= 0 )
		return;
	if( msgLen >= (int)sizeof(line) )
		msgLen = sizeof(line) - 1;
	total = tagLen + msgLen + 1; // + newline
	VLC_LOCK(&g_logLock);
	if( g_logLen + total > VLC_LOG_CAPACITY )
		g_logLen = 0; 
	if( g_logLen + total <= VLC_LOG_CAPACITY ) {
		memcpy(g_logBuf + g_logLen, tag, tagLen);
		g_logLen += tagLen;
		memcpy(g_logBuf + g_logLen, line, msgLen);
		g_logLen += msgLen;
		g_logBuf[g_logLen++] = '\n';
	}
	VLC_UNLOCK(&g_logLock);
}

static void hl_vlc_free( hl_vlc *v ) {
	if( v->player ) {
		libvlc_media_player_stop(v->player);
		libvlc_media_player_release(v->player);
		v->player = NULL;
	}
	if( v->media ) {
		libvlc_media_release(v->media);
		v->media = NULL;
	}
	if( v->pixels ) {
		free(v->pixels);
		v->pixels = NULL;
	}
	if( v->lockInited ) {
		VLC_LOCK_DESTROY(&v->lock);
		v->lockInited = false;
	}
}

HL_PRIM bool HL_NAME(vlc_global_init)( vbyte *pluginsPath ) {
	const char *args[] = { "--verbose=2" };
	if( g_instance != NULL )
		return true;
	if( pluginsPath != NULL ) {
#ifdef _WIN32
		SetEnvironmentVariableA("VLC_PLUGIN_PATH", (const char*)pluginsPath);
#else
		setenv("VLC_PLUGIN_PATH", (const char*)pluginsPath, 1);
#endif
	}
	VLC_LOCK_INIT(&g_logLock);
	g_instance = libvlc_new(1, args);
	if( g_instance != NULL )
		libvlc_log_set(g_instance, log_cb, NULL);
	return g_instance != NULL;
}

HL_PRIM void HL_NAME(vlc_global_shutdown)() {
	if( g_instance ) {
		libvlc_release(g_instance);
		g_instance = NULL;
	}
}

HL_PRIM int HL_NAME(vlc_get_error)( vbyte *out, int maxLen ) {
	const char *msg = libvlc_errmsg();
	int len;
	if( msg == NULL )
		return 0;
	len = (int)strlen(msg);
	if( len > maxLen )
		len = maxLen;
	memcpy(out, msg, len);
	return len;
}

// Copies libVLC's diagnostic log since the last vlc_open() (see log_cb) into `out`. 
// Non-destructive.. safe to call repeatedly, e.g. to poll while waiting to see if a stream resolves.
HL_PRIM int HL_NAME(vlc_get_log)( vbyte *out, int maxLen ) {
	int len;
	VLC_LOCK(&g_logLock);
	len = g_logLen;
	if( len > maxLen )
		len = maxLen;
	memcpy(out, g_logBuf, len);
	VLC_UNLOCK(&g_logLock);
	return len;
}

// video memory callbacks (invoked on libVLC's internal decode/output threads)

static unsigned format_cb( void **opaque, char *chroma, unsigned *width, unsigned *height, unsigned *pitches, unsigned *lines ) {
	hl_vlc *v = (hl_vlc*)*opaque;
	size_t size = (size_t)(*width) * (size_t)(*height) * 4;
	memcpy(chroma, "RV32", 4);
	VLC_LOCK(&v->lock);
	if( v->pixels )
		free(v->pixels);
	v->pixels = (unsigned char*)calloc(size, 1);
	v->width = *width;
	v->height = *height;
	v->hasFrame = false;
	pitches[0] = *width * 4;
	lines[0] = *height;
	VLC_UNLOCK(&v->lock);
	return v->pixels != NULL ? 1 : 0;
}

static void cleanup_cb( void *opaque ) {
	hl_vlc *v = (hl_vlc*)opaque;
	VLC_LOCK(&v->lock);
	if( v->pixels ) {
		free(v->pixels);
		v->pixels = NULL;
	}
	v->width = 0;
	v->height = 0;
	VLC_UNLOCK(&v->lock);
}

static void *lock_cb( void *opaque, void **planes ) {
	hl_vlc *v = (hl_vlc*)opaque;
	VLC_LOCK(&v->lock);
	*planes = v->pixels;
	return NULL;
}

static void unlock_cb( void *opaque, void *picture, void *const *planes ) {
	hl_vlc *v = (hl_vlc*)opaque;
	VLC_UNLOCK(&v->lock);
}

static void display_cb( void *opaque, void *picture ) {
	hl_vlc *v = (hl_vlc*)opaque;
	VLC_LOCK(&v->lock);
	v->hasFrame = true;
	VLC_UNLOCK(&v->lock);
}

static void event_cb( const struct libvlc_event_t *evt, void *opaque ) {
	hl_vlc *v = (hl_vlc*)opaque;
	switch( evt->type ) {
	case libvlc_MediaPlayerEndReached:
		v->ended = true;
		break;
	case libvlc_MediaPlayerEncounteredError:
		v->errored = true;
		break;
	case libvlc_MediaPlayerPlaying:
		v->playingFired = true;
		break;
	default:
		break;
	}
}

// player lifecycle

HL_PRIM hl_vlc *HL_NAME(vlc_open)( vbyte *path, bool isUrl ) {
	hl_vlc *v;
	libvlc_event_manager_t *events;
	if( g_instance == NULL && !HL_NAME(vlc_global_init)(NULL) )
		return NULL;
	VLC_LOCK(&g_logLock);
	g_logLen = 0;
	VLC_UNLOCK(&g_logLock);
	v = (hl_vlc*)hl_gc_alloc_finalizer(sizeof(hl_vlc));
	memset(v, 0, sizeof(hl_vlc));
	v->finalizer = hl_vlc_free;
	VLC_LOCK_INIT(&v->lock);
	v->lockInited = true;
	v->media = isUrl ? libvlc_media_new_location(g_instance, (const char*)path) : libvlc_media_new_path(g_instance, (const char*)path);
	if( v->media == NULL ) {
		hl_vlc_free(v);
		return NULL;
	}
	v->player = libvlc_media_player_new_from_media(v->media);
	if( v->player == NULL ) {
		hl_vlc_free(v);
		return NULL;
	}
	libvlc_video_set_callbacks(v->player, lock_cb, unlock_cb, display_cb, v);
	libvlc_video_set_format_callbacks(v->player, format_cb, cleanup_cb);
	events = libvlc_media_player_event_manager(v->player);
	libvlc_event_attach(events, libvlc_MediaPlayerEndReached, event_cb, v);
	libvlc_event_attach(events, libvlc_MediaPlayerEncounteredError, event_cb, v);
	libvlc_event_attach(events, libvlc_MediaPlayerPlaying, event_cb, v);
	return v;
}

HL_PRIM bool HL_NAME(vlc_play)( hl_vlc *v ) {
	v->ended = false;
	v->errored = false;
	return libvlc_media_player_play(v->player) == 0;
}

HL_PRIM void HL_NAME(vlc_set_pause)( hl_vlc *v, bool pause ) {
	libvlc_media_player_set_pause(v->player, pause ? 1 : 0);
}

HL_PRIM void HL_NAME(vlc_stop)( hl_vlc *v ) {
	libvlc_media_player_stop(v->player);
}

HL_PRIM bool HL_NAME(vlc_is_playing)( hl_vlc *v ) {
	return libvlc_media_player_is_playing(v->player) != 0;
}

HL_PRIM bool HL_NAME(vlc_has_ended)( hl_vlc *v ) {
	return v->ended;
}

HL_PRIM bool HL_NAME(vlc_has_error)( hl_vlc *v ) {
	return v->errored;
}

HL_PRIM bool HL_NAME(vlc_take_playing)( hl_vlc *v ) {
	bool r = v->playingFired;
	v->playingFired = false;
	return r;
}

HL_PRIM bool HL_NAME(vlc_get_size)( hl_vlc *v, int *width, int *height ) {
	bool ready;
	VLC_LOCK(&v->lock);
	ready = v->width > 0 && v->height > 0;
	*width = (int)v->width;
	*height = (int)v->height;
	VLC_UNLOCK(&v->lock);
	return ready;
}

HL_PRIM bool HL_NAME(vlc_has_frame)( hl_vlc *v ) {
	bool has;
	VLC_LOCK(&v->lock);
	has = v->hasFrame;
	VLC_UNLOCK(&v->lock);
	return has;
}

HL_PRIM bool HL_NAME(vlc_get_frame)( hl_vlc *v, vbyte *out, int outCapacity ) {
	bool copied = false;
	VLC_LOCK(&v->lock);
	if( v->pixels && v->hasFrame ) {
		size_t n = (size_t)v->width * (size_t)v->height * 4;
		if( n <= (size_t)outCapacity ) {
			memcpy(out, v->pixels, n);
			v->hasFrame = false;
			copied = true;
		}
	}
	VLC_UNLOCK(&v->lock);
	return copied;
}

HL_PRIM double HL_NAME(vlc_get_length)( hl_vlc *v ) {
	return (double)libvlc_media_player_get_length(v->player);
}

HL_PRIM double HL_NAME(vlc_get_time)( hl_vlc *v ) {
	return (double)libvlc_media_player_get_time(v->player);
}

HL_PRIM void HL_NAME(vlc_set_time)( hl_vlc *v, double t ) {
	libvlc_media_player_set_time(v->player, (libvlc_time_t)t);
}

HL_PRIM double HL_NAME(vlc_get_position)( hl_vlc *v ) {
	return (double)libvlc_media_player_get_position(v->player);
}

HL_PRIM void HL_NAME(vlc_set_position)( hl_vlc *v, double p ) {
	libvlc_media_player_set_position(v->player, (float)p);
}

HL_PRIM int HL_NAME(vlc_get_volume)( hl_vlc *v ) {
	return libvlc_audio_get_volume(v->player);
}

HL_PRIM bool HL_NAME(vlc_set_volume)( hl_vlc *v, int vol ) {
	return libvlc_audio_set_volume(v->player, vol) == 0;
}

HL_PRIM void HL_NAME(vlc_set_mute)( hl_vlc *v, bool mute ) {
	libvlc_audio_set_mute(v->player, mute ? 1 : 0);
}

HL_PRIM void HL_NAME(vlc_close)( hl_vlc *v ) {
	hl_vlc_free(v);
}

#define _VLC _ABSTRACT(hl_vlc)

DEFINE_PRIM(_BOOL, vlc_global_init, _BYTES);
DEFINE_PRIM(_VOID, vlc_global_shutdown, _NO_ARG);
DEFINE_PRIM(_I32, vlc_get_error, _BYTES _I32);
DEFINE_PRIM(_I32, vlc_get_log, _BYTES _I32);

DEFINE_PRIM(_VLC, vlc_open, _BYTES _BOOL);
DEFINE_PRIM(_BOOL, vlc_play, _VLC);
DEFINE_PRIM(_VOID, vlc_set_pause, _VLC _BOOL);
DEFINE_PRIM(_VOID, vlc_stop, _VLC);
DEFINE_PRIM(_BOOL, vlc_is_playing, _VLC);
DEFINE_PRIM(_BOOL, vlc_has_ended, _VLC);
DEFINE_PRIM(_BOOL, vlc_has_error, _VLC);
DEFINE_PRIM(_BOOL, vlc_take_playing, _VLC);

DEFINE_PRIM(_BOOL, vlc_get_size, _VLC _REF(_I32) _REF(_I32));
DEFINE_PRIM(_BOOL, vlc_has_frame, _VLC);
DEFINE_PRIM(_BOOL, vlc_get_frame, _VLC _BYTES _I32);

DEFINE_PRIM(_F64, vlc_get_length, _VLC);
DEFINE_PRIM(_F64, vlc_get_time, _VLC);
DEFINE_PRIM(_VOID, vlc_set_time, _VLC _F64);
DEFINE_PRIM(_F64, vlc_get_position, _VLC);
DEFINE_PRIM(_VOID, vlc_set_position, _VLC _F64);

DEFINE_PRIM(_I32, vlc_get_volume, _VLC);
DEFINE_PRIM(_BOOL, vlc_set_volume, _VLC _I32);
DEFINE_PRIM(_VOID, vlc_set_mute, _VLC _BOOL);

DEFINE_PRIM(_VOID, vlc_close, _VLC);
