// QuickJS-NG bounded execution bridge. All JS handles stay on worker thread.
#include "quickjs.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stddef.h>
#ifdef _WIN32
#include <windows.h>
#define API __declspec(dllexport)
#else
#include <time.h>
#define API __attribute__((visibility("default"))) __attribute__((used))
#endif

typedef struct { atomic_int cancelled; int64_t deadline; int status; size_t output_limit; size_t used, limit; int memory_exceeded; char *message; char *diagnostics; } Control;
static int64_t millis(void) {
#ifdef _WIN32
 return (int64_t)GetTickCount64();
#else
 struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (int64_t)t.tv_sec*1000+t.tv_nsec/1000000;
#endif
}
// Host diagnostics only; never installed as guest JavaScript functions.
static atomic_int live_controls = 0;
static atomic_int live_runtimes = 0;
API int gm_live_controls(void) { return atomic_load(&live_controls); }
API int gm_live_runtimes(void) { return atomic_load(&live_runtimes); }
API Control *gm_control_new(void) { Control *c=calloc(1,sizeof(Control)); if(c)atomic_fetch_add(&live_controls,1); return c; }
API void gm_cancel(Control *c) { atomic_store(&c->cancelled,1); }
API void gm_control_free(Control *c) { free(c->message); free(c->diagnostics); free(c); atomic_fetch_sub(&live_controls,1); }
API int gm_status(Control *c) { return c->status; }
API const char *gm_message(Control *c) { return c->message ? c->message : ""; }
API const char *gm_diagnostics(Control *c) { return c->diagnostics ? c->diagnostics : ""; }
static JSValue retain_diagnostics(JSContext *ctx, JSValueConst receiver, int argc, JSValueConst *argv) {
 (void)receiver; Control *c=JS_GetContextOpaque(ctx);
 if(argc!=1 || !JS_IsString(argv[0]))return JS_UNDEFINED;
 size_t length=0; const char *text=JS_ToCStringLen(ctx,&length,argv[0]);
 if(text && length<=c->output_limit) {
  char *copy=malloc(length+1);
  if(copy){memcpy(copy,text,length+1);free(c->diagnostics);c->diagnostics=copy;}
 }
 if(text)JS_FreeCString(ctx,text); return JS_UNDEFINED;
}
static int interrupted(JSRuntime *rt, void *opaque) {
 (void)rt; Control *c=opaque;
 if(atomic_load(&c->cancelled)) { c->status=3; return 1; }
 if(millis()>=c->deadline) { c->status=2; return 1; } return 0;
}
static void exception(JSContext *ctx, Control *c, JSValue error) {
 const char *s=JS_ToCString(ctx,error);
 JSValue stack=JS_GetPropertyStr(ctx,error,"stack");
 const char *st=JS_ToCString(ctx,stack);
 if(!c->status) c->status=(s && strstr(s,"out of memory"))?4:1;
 size_t n=(s?strlen(s):0)+(st?strlen(st):0)+3;
 if(n>c->output_limit+1){n=c->output_limit+1;if(!c->status || c->status==1)c->status=5;}
 c->message=malloc(n); if(c->message) snprintf(c->message,n,"%s\n%s",s?s:"JavaScript error",st?st:"");
 if(s)JS_FreeCString(ctx,s); if(st)JS_FreeCString(ctx,st); JS_FreeValue(ctx,stack); JS_FreeValue(ctx,error);
}
// Prefix keeps returned pointers maximally aligned and counts exact ownership.
#ifdef _MSC_VER
// MSVC's C headers omit max_align_t. malloc is aligned to the Windows SDK's
// MEMORY_ALLOCATION_ALIGNMENT (16 on Win64, 8 on Win32); a prefix of that size
// preserves the allocator's alignment when returning h+1.
typedef union { char alignment[MEMORY_ALLOCATION_ALIGNMENT]; size_t size; } Header;
#else
typedef union { max_align_t alignment; size_t size; } Header;
#endif
static void *quota_malloc(void *opaque, size_t size) {
 Control *c=opaque;
 if(size > SIZE_MAX-sizeof(Header) || size+sizeof(Header)>c->limit-c->used) { c->memory_exceeded=1; return NULL; }
 Header *h=malloc(size+sizeof(Header)); if(!h) { c->memory_exceeded=1; return NULL; }
 h->size=size; c->used+=size+sizeof(Header); return h+1;
}
static void quota_free(void *opaque, void *ptr) { if(!ptr)return; Control *c=opaque; Header *h=(Header*)ptr-1; c->used-=h->size+sizeof(Header); free(h); }
static size_t quota_size(const void *ptr) { return ptr?((const Header*)ptr-1)->size:0; }
static void *quota_calloc(void *opaque, size_t count, size_t size) { if(size && count>SIZE_MAX/size)return NULL; void *p=quota_malloc(opaque,count*size); if(p)memset(p,0,count*size); return p; }
static void *quota_realloc(void *opaque, void *ptr, size_t size) {
 if(!ptr)return quota_malloc(opaque,size); if(!size){quota_free(opaque,ptr);return NULL;}
 size_t old=quota_size(ptr); void *p=quota_malloc(opaque,size); if(p){memcpy(p,ptr,old<size?old:size);quota_free(opaque,ptr);} return p;
}
static const JSMallocFunctions quota={quota_calloc,quota_malloc,quota_free,quota_realloc,quota_size};
API void gm_eval(Control *c, const char *source, const char *filename, int timeout, int64_t memory, int output_limit) {
 c->deadline=millis()+timeout; c->output_limit=output_limit>0?(size_t)output_limit:0;
 c->limit=(size_t)memory;
 JSRuntime *rt=JS_NewRuntime2(&quota,c); if(!rt){c->status=4;return;}
 atomic_fetch_add(&live_runtimes,1);
 JS_SetMemoryLimit(rt,SIZE_MAX); /* Exact quota is tracked by allocator. */ JS_SetMaxStackSize(rt,512*1024); JS_SetInterruptHandler(rt,interrupted,c);
 JSContext *ctx=JS_NewContext(rt); if(!ctx){c->status=4;JS_FreeRuntime(rt);atomic_fetch_sub(&live_runtimes,1);return;}
 JS_SetContextOpaque(ctx,c);
 JSValue global=JS_GetGlobalObject(ctx);
 JS_SetPropertyStr(ctx,global,"__getmanDiagnosticSink",JS_NewCFunction(ctx,retain_diagnostics,"",1));
 JS_FreeValue(ctx,global);
 JSValue value=JS_Eval(ctx,source,strlen(source),filename,JS_EVAL_TYPE_GLOBAL);
 if(JS_IsException(value)) exception(ctx,c,JS_GetException(ctx));
 else {
  while(JS_PromiseState(ctx,value)==JS_PROMISE_PENDING && !interrupted(rt,c)) {
   JSContext *jobctx=NULL; int jobs=JS_ExecutePendingJob(rt,&jobctx);
   if(jobs<0) { exception(jobctx,c,JS_GetException(jobctx)); break; }
   if(!jobs) {
#ifdef _WIN32
    Sleep(1);
#else
    struct timespec pause={0,1000000}; nanosleep(&pause,NULL);
#endif
   }
  }
  if(!c->status && JS_PromiseState(ctx,value)==JS_PROMISE_REJECTED) exception(ctx,c,JS_PromiseResult(ctx,value));
 }
 if(!c->status && JS_PromiseState(ctx,value)==JS_PROMISE_FULFILLED) {
  JSValue result=JS_PromiseResult(ctx,value); size_t length=0;
  const char *text=JS_ToCStringLen(ctx,&length,result);
  if(text && length>(size_t)output_limit)c->status=5;
  else if(text){c->message=malloc(length+1); if(c->message)memcpy(c->message,text,length+1);else c->status=4;}
  if(text)JS_FreeCString(ctx,text);JS_FreeValue(ctx,result);
 }
 if(c->memory_exceeded && c->status!=2 && c->status!=3)c->status=4;
 JS_FreeValue(ctx,value); JS_FreeContext(ctx); JS_FreeRuntime(rt); atomic_fetch_sub(&live_runtimes,1);
}
