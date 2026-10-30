// Reproducible offline browser engine bundle; no CDN or dynamic import survives.
import {build} from 'esbuild';
import {copyFile, mkdir, readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const output = new URL('../../assets/scripting/', import.meta.url);
await mkdir(output, {recursive:true});
await build({entryPoints:[new URL('worker.js',import.meta.url).pathname], outfile:new URL('quickjs_worker.js',output).pathname, bundle:true, format:'iife', platform:'browser', target:'es2022', minify:true, legalComments:'eof'});
await copyFile(new URL('node_modules/@jitl/quickjs-wasmfile-release-sync/dist/emscripten-module.wasm',import.meta.url),new URL('emscripten-module.wasm',output));
await copyFile(new URL('node_modules/@jitl/quickjs-wasmfile-release-sync/LICENSE',import.meta.url),new URL('quickjs-emscripten-LICENSE',output));
const hashes = {};
for (const file of ['quickjs_worker.js','emscripten-module.wasm']) hashes[file] = createHash('sha256').update(await readFile(new URL(file,output))).digest('hex');
await writeFile(new URL('web-runtime-manifest.json',import.meta.url), JSON.stringify({quickjsEmscripten:'0.31.0',esbuild:'0.25.12',hashes},null,2)+'\n');
