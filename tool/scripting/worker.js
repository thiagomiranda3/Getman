// QuickJS guest execution: browser capabilities never enter the guest heap.
import { newQuickJSWASMModuleFromVariant, newVariant } from 'quickjs-emscripten-core';
import variant from '@jitl/quickjs-wasmfile-release-sync';
const engine = newQuickJSWASMModuleFromVariant(newVariant(variant, {wasmLocation: new URL("emscripten-module.wasm", self.location.href).href}));
self.onmessage = async ({data}) => {
  let runtime, context, result;
  let diagnostics = "";
  const send = value => self.postMessage(JSON.stringify({...value,diagnostics}));
  try {
    const job = JSON.parse(data);
    if (typeof job.source !== 'string' || typeof job.filename !== 'string' ||
        !Number.isSafeInteger(job.timeout) || job.timeout < 1 ||
        !Number.isSafeInteger(job.memory) || job.memory < 1 ||
        !Number.isSafeInteger(job.output) || job.output < 1) {
      throw Error('Invalid execution envelope');
    }
    const module = await engine;
    const deadline = performance.now() + job.timeout;
    runtime = module.newRuntime();
    runtime.setMemoryLimit(job.memory);
    runtime.setMaxStackSize(512 * 1024);
    runtime.setInterruptHandler(() => performance.now() >= deadline);
    context = runtime.newContext();
    // Only the bootstrap receives this function and deletes its global before
    // user execution. Copy bounded primitive text; never inspect guest objects.
    const report = context.newFunction('', value => {
      if (context.typeof(value) !== 'string') return;
      const snapshot = context.getString(value);
      if (new TextEncoder().encode(snapshot).length <= job.output) {
        diagnostics = snapshot;
        send({kind:'diagnostic'});
      }
    });
    context.setProp(context.global,'__getmanDiagnosticSink',report);
    report.dispose();
    result = context.evalCode(job.source, job.filename);
    const fail = handle => {
      const error = context.dump(handle);
      const message = typeof error === 'object' ? `${error.name}: ${error.message}\n${error.stack || ''}` : String(error);
      if (new TextEncoder().encode(message).length > job.output) { send({kind:'outputTooLarge',message:'Script output exceeds limit'}); return; }
      send({kind: performance.now() >= deadline ? 'timeout' : /out of memory/i.test(message) ? 'memoryLimit' : /^SyntaxError/.test(message) ? 'syntax' : 'runtime', message});
    };
    if (result.error) { fail(result.error); return; }
    while (true) {
      if (performance.now() >= deadline) { send({kind:'timeout',message:'Script execution timed out'}); return; }
      const state = context.getPromiseState(result.value);
      if (state.type === 'fulfilled') {
        try {
          const value = context.dump(state.value);
          const output = typeof value === 'string' ? value : JSON.stringify(value) ?? '';
          send(new TextEncoder().encode(output).length > job.output ? {kind:'outputTooLarge',message:'Script output exceeds limit'} : {kind:'ok',value:output});
        } finally { state.value.dispose(); }
        return;
      }
      if (state.type === 'rejected') {
        try { fail(state.error); } finally { state.error.dispose(); }
        return;
      }
      if (runtime.hasPendingJob()) {
        const pending = runtime.executePendingJobs(1);
        if (pending.error) { try { fail(pending.error); } finally { pending.error.dispose(); } return; }
      } else {
        await new Promise(resolve => setTimeout(resolve, 1));
      }
    }
  } catch (_) { send({kind:'runtime',message:'Script worker failed'}); }
  finally { result?.dispose(); context?.dispose(); runtime?.dispose(); }
};
