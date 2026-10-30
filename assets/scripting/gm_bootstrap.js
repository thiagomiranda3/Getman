// Getman API v1. Evaluated only inside QuickJS, never the browser host.
// The runner receives capabilities; private state and serializer stay lexical.
(async function (input, runUser, reportDiagnostic) {
  'use strict';
  delete globalThis.__getmanDiagnosticSink;
  const report = typeof reportDiagnostic === 'function' ? reportDiagnostic : () => {};
  const stringify = JSON.stringify.bind(JSON);
  const parse = JSON.parse.bind(JSON);
  const own = Function.call.bind(Object.prototype.hasOwnProperty);
  const freeze = Object.freeze;
  const keysOf = Object.keys;
  const dict = values => Object.assign(Object.create(null), values);
  const temporary = dict(input.temporary);
  const environment = dict(input.environment);
  const sets = dict({});
  const unsets = new Set();
  const headers = dict(input.request.headers);
  const headerSets = dict({});
  const headerUnsets = new Set();
  const requestPatch = {};
  const tests = [];
  const logs = [];
  let error = null;
  const secretKeys = new Set(input.secretKeys || []);
  const secretValues = [];
  const seenSecrets = new Set();
  let secretBytes = 0;
  function recordSecret(key,text) {
    if (!secretKeys.has(key) || !text || seenSecrets.has(text)) return;
    secretBytes += byteCount(text);
    if (secretBytes > input.limits.outputBytes) throw new Error('Secret diagnostic output exceeds limit');
    seenSecrets.add(text);
    secretValues.push(text);
    // A later fatal interrupt must redact logs recorded before this assignment.
    retainDiagnostics();
  }
  function stringMap(values) {
    const keys = keysOf(values);
    let text='{';
    for (let i=0;i<keys.length;i++) text+=(i?',':'')+stringify(keys[i])+':'+stringify(values[keys[i]]);
    return text+'}';
  }
  function stringList(values) {
    let text='[';
    for (let i=0;i<values.length;i++) text+=(i?',':'')+stringify(values[i]);
    return text+']';
  }
  function setList(values) {
    let text='[', separator='';
    values.forEach(value=>{text+=separator+stringify(value);separator=',';});
    return text+']';
  }
  // Private host data is serialized field-by-field. User prototype/toJSON
  // changes cannot replace the envelope or execute code during snapshotting.
  function serializeOutput(includeChanges) {
    let text='{"temporaryVariables":'+(includeChanges?stringMap(temporary):'{}')+',"environmentPatch":{"sets":'+(includeChanges?stringMap(sets):'{}')+',"unsets":'+(includeChanges?setList(unsets):'[]')+'},"requestPatch":{';
    if (includeChanges) {
      for (const key of ['url','method','body']) if (own(requestPatch,key)) text+=stringify(key)+':'+stringify(requestPatch[key])+',';
    }
    text+='"headerSets":'+(includeChanges?stringMap(headerSets):'{}')+',"headerUnsets":'+(includeChanges?setList(headerUnsets):'[]')+'},"tests":[';
    let separator='';
    for (let i=0;i<tests.length;i++) {
      if (!own(tests,i)) continue;
      const test=tests[i];
      text+=separator+'{"id":'+stringify(test.id)+',"name":'+stringify(test.name)+',"passed":'+(test.passed?'true':'false')+',"message":'+stringify(test.message)+'}';
      separator=',';
    }
    text+='],"logs":[';
    for (let i=0;i<logs.length;i++) {
      const entry=logs[i];
      text+=(i?',':'')+'{"level":'+stringify(entry.level)+',"message":'+stringify(entry.message)+'}';
    }
    text+='],"secretValues":'+stringList(secretValues)+',"error":';
    text+=includeChanges && error ? '{"kind":'+stringify(error.kind)+',"message":'+stringify(error.message)+'}' : 'null';
    return text+'}';
  }
  function retainDiagnostics() { report(serializeOutput(false)); }
  const name = value => {
    if (typeof value !== 'string') throw new TypeError('Name must be a string');
    return value;
  };
  function validateJson(value, seen = new Set()) {
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
    if (typeof value === 'number' && Number.isFinite(value)) return;
    if (typeof value !== 'object' || seen.has(value)) throw new TypeError('Variable value must be JSON-compatible');
    const prototype = Object.getPrototypeOf(value);
    if (!Array.isArray(value) && prototype !== Object.prototype && prototype !== null) throw new TypeError('Variable value must be a JSON object');
    if (Object.getOwnPropertySymbols(value).length) throw new TypeError('Symbol keys are not JSON-compatible');
    seen.add(value);
    for (const key of Object.keys(value)) validateJson(value[key], seen);
    seen.delete(value);
  }
  function variableText(value) {
    validateJson(value);
    return typeof value === 'string' ? value : stringify(value);
  }
  const vars = freeze({
    get(key) { name(key); return own(temporary,key) ? temporary[key] : own(environment,key) ? environment[key] : own(input.collection,key) ? input.collection[key] : undefined; },
    has(key) { name(key); return own(temporary,key) || own(environment,key) || own(input.collection,key); },
    set(key,value) { name(key); const text=variableText(value); recordSecret(key,text); temporary[key]=text; },
    unset(key) { delete temporary[name(key)]; },
  });
  function requireEnvironment() {
    if (input.environmentId === null) throw new Error('Select an environment before writing environment variables');
  }
  const env = freeze({
    get(key) { return own(environment,name(key)) ? environment[key] : undefined; },
    has(key) { return own(environment,name(key)); },
    set(key,value) { requireEnvironment(); name(key); const text = variableText(value); recordSecret(key,text); environment[key] = text; sets[key] = text; unsets.delete(key); },
    unset(key) { requireEnvironment(); name(key); delete environment[key]; delete sets[key]; unsets.add(key); },
  });
  function requirePre() {
    if (input.phase !== 'preRequest') throw new Error('Request mutations are only available in PRE-REQUEST');
  }
  const headerKey = (values,key) => Object.keys(values).find(k => k.toLowerCase() === name(key).toLowerCase());
  function removeHeaderPatch(key) {
    for (const existing of Object.keys(headerSets)) if (existing.toLowerCase() === key.toLowerCase()) delete headerSets[existing];
  }
  const request = freeze({
    get url() { return requestPatch.url === undefined ? input.request.url : requestPatch.url; },
    get method() { return requestPatch.method === undefined ? input.request.method : requestPatch.method; },
    get body() { return requestPatch.body === undefined ? input.request.body : requestPatch.body; },
    setUrl(value) { requirePre(); requestPatch.url = name(value); },
    setMethod(value) { requirePre(); if (!input.methods.includes(value)) throw new Error('Unsupported HTTP method'); requestPatch.method = value; },
    setBody(value) { requirePre(); if (input.request.bodyType !== 'raw') throw new Error('setBody requires a raw body'); requestPatch.body = name(value); },
    headers: freeze({
      get(key) { const found = headerKey(headers,key); return found === undefined ? undefined : headers[found]; },
      set(key,value) { requirePre(); name(key); name(value); const old = headerKey(headers,key); if (old !== undefined) delete headers[old]; removeHeaderPatch(key); headers[key] = value; headerSets[key] = value; for (const removed of headerUnsets) if (removed.toLowerCase() === key.toLowerCase()) headerUnsets.delete(removed); },
      unset(key) { requirePre(); name(key); const old = headerKey(headers,key); if (old !== undefined) delete headers[old]; removeHeaderPatch(key); headerUnsets.add(old === undefined ? key : old); },
    }),
  });
  function lookup(root,path) {
    const miss = {found:false,value:null};
    let p = name(path).trim();
    if (!p) return miss;
    if (p === '$') return {found:true,value:root};
    if (p.startsWith('$')) p = p.slice(1);
    const segments = [];
    let i = 0;
    while (i < p.length) {
      if (p[i] === '[') {
        const end = p.indexOf(']',i);
        if (end < 0) return miss;
        const inner = p.slice(i+1,end).trim();
        if (inner.length >= 2 && ((inner[0] === '"' && inner.at(-1) === '"') || (inner[0] === "'" && inner.at(-1) === "'"))) segments.push(inner.slice(1,-1));
        else if (/^\+?\d+$/.test(inner)) segments.push(Number(inner));
        else return miss;
        i = end+1;
      } else {
        if (p[i] === '.') i++;
        const start = i;
        while (i < p.length && p[i] !== '.' && p[i] !== '[') i++;
        if (i === start) return miss;
        segments.push(p.slice(start,i));
      }
    }
    let value = root;
    for (const segment of segments) {
      if (typeof segment === 'number') {
        if (!Array.isArray(value) || segment >= value.length) return miss;
      } else if (value === null || typeof value !== 'object' || Array.isArray(value) || !own(value,segment)) return miss;
      value = value[segment];
    }
    return {found:true,value};
  }
  let responseJson;
  let hasResponseJson = false;
  function responseObject() {
    if (input.phase !== 'postResponse' || input.response === null) throw new Error('Response is only available in POST-RESPONSE');
    return response;
  }
  const response = freeze({
    get status() { return input.response.status; },
    get durationMs() { return input.response.durationMs; },
    text() { return input.response.text; },
    json() { if (!hasResponseJson) { responseJson = parse(input.response.text); hasResponseJson = true; } return responseJson; },
    header(key) { const found = headerKey(input.response.headers,key); return found === undefined ? undefined : input.response.headers[found]; },
    lookup(path) { return lookup(response.json(),path); },
  });
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function encode(text,url = false) {
    const bytes = Array.from(unescape(encodeURIComponent(name(text))), c => c.charCodeAt(0));
    let result = '';
    for (let i=0;i<bytes.length;i+=3) {
      const n = (bytes[i]<<16) | ((bytes[i+1] || 0)<<8) | (bytes[i+2] || 0);
      result += alphabet[(n>>>18)&63] + alphabet[(n>>>12)&63] + (i+1<bytes.length ? alphabet[(n>>>6)&63] : '=') + (i+2<bytes.length ? alphabet[n&63] : '=');
    }
    return url ? result.replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'') : result;
  }
  function base64Bytes(text,url) {
    name(text);
    if (!(url ? /^[A-Za-z0-9_-]*={0,2}$/ : /^[A-Za-z0-9+/]*={0,2}$/).test(text)) throw new Error('Invalid Base64');
    if ((!url || text.includes('=')) && text.length%4 !== 0) throw new Error('Invalid Base64 padding');
    let data = text.replace(/=+$/,'');
    if (data.length%4 === 1) throw new Error('Invalid Base64 length');
    const expectedPadding = (4-data.length%4)%4;
    if (text.includes('=') && text.length-data.length !== expectedPadding) throw new Error('Invalid Base64 padding');
    if (url) data = data.replace(/-/g,'+').replace(/_/g,'/');
    const bytes = [];
    let buffer=0, bits=0;
    for (const char of data) {
      buffer=(buffer<<6)|alphabet.indexOf(char); bits+=6;
      if (bits>=8) { bits-=8; bytes.push((buffer>>>bits)&255); }
    }
    if (bits && (buffer & ((1<<bits)-1))) throw new Error('Invalid Base64 trailing bits');
    return bytes;
  }
  function decode(text,url = false) {
    return decodeURIComponent(base64Bytes(text,url).map(b => '%'+b.toString(16).padStart(2,'0')).join(''));
  }
  const registeredTests = [];
  let testTail = null;
  const pendingTests = [];
  let aborted = false;
  function resourceFailure(failure) {
    return failure && failure.name === 'InternalError' && /out of memory|interrupted|stack overflow/i.test(String(failure));
  }
  function executeTest(test,index) {
    if (aborted) return;
    function finish(passed,message = null) {
      tests[index] = freeze({id:input.executionId+':'+input.phase+':'+index,name:test.name,passed,message});
      retainDiagnostics();
    }
    function failed(failure) {
      if (resourceFailure(failure)) throw failure;
      finish(false,String(failure)+(failure && failure.stack ? '\n'+String(failure.stack) : ''));
    }
    try {
      const result = test.callback();
      if (result && typeof result.then === 'function') {
        const pending = Promise.resolve(result).then(() => finish(true),failed);
        pendingTests.push(pending);
        return pending;
      }
      finish(true);
    } catch (failure) { failed(failure); }
  }
  function display(value) {
    try { return stringify(value) ?? String(value); } catch (failure) { if (resourceFailure(failure)) throw failure; return '[Unserializable]'; }
  }
  function expect(value) {
    function assert(condition,message) { if (!condition) throw new Error(message); }
    function equal(expected) {
      assert((value === null || typeof value !== 'object') && (expected === null || typeof expected !== 'object'), 'Objects require deep.equal');
      assert(value === expected, 'Expected '+display(value)+' to equal '+display(expected));
    }
    function deepEqual(a,b) {
      validateJson(a); validateJson(b);
      if (a === b) return true;
      if (!a || !b || typeof a !== 'object' || typeof b !== 'object' || Array.isArray(a) !== Array.isArray(b)) return false;
      const keys = Object.keys(a);
      return keys.length === Object.keys(b).length && keys.every(key => own(b,key) && deepEqual(a[key],b[key]));
    }
    function numeric(...values) { assert(values.every(n => typeof n === 'number' && Number.isFinite(n)), 'Expected finite numbers'); }
    const chain = {
      equal,
      deep:freeze({equal(expected) { assert(deepEqual(value,expected),'Expected '+display(value)+' to deeply equal '+display(expected)); }}),
      not:freeze({equal(expected) { assert(value !== expected,'Expected values to differ'); }}),
      a(type) {
        const actual = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
        assert(['string','number','boolean','object','array','null','undefined'].includes(type) && actual === type,'Expected '+actual+' to be '+type);
      },
      contain(expected) { assert((typeof value === 'string' && typeof expected === 'string' || Array.isArray(value)) && value.includes(expected),'Expected '+display(value)+' to contain '+display(expected)); },
      lessThan(expected) { numeric(value,expected); assert(value < expected,'Expected '+value+' to be less than '+expected); },
      greaterThan(expected) { numeric(value,expected); assert(value > expected,'Expected '+value+' to be greater than '+expected); },
      within(lo,hi) { numeric(value,lo,hi); assert(value >= lo && value <= hi,'Expected '+value+' within ['+lo+', '+hi+']'); },
      get exist() { assert(value !== undefined,'Expected a defined value'); return chain; },
      get to() { return chain; },
      get be() { return chain; },
    };
    return freeze(chain);
  }
  const gm = freeze({
    apiVersion:1, variables:vars, environment:env, request, expect,
    test(label,callback) {
      name(label);
      if (typeof callback !== 'function') throw new TypeError('Test callback must be a function');
      if (registeredTests.length >= input.limits.testCount) throw new Error('Script test limit exceeded');
      const index = registeredTests.length;
      const test = {name:label,callback};
      registeredTests.push(test);
      if (testTail === null) {
        const pending = executeTest(test,index);
        if (pending) testTail = pending;
      } else {
        testTail = testTail.then(() => executeTest(test,index));
      }
    },
    get response() { return responseObject(); },
    jwt:freeze({decode(token) {
      const parts = name(token).split('.');
      if (parts.length !== 3 || !parts[0] || !parts[1]) throw new Error('Expected compact three-segment JWS');
      const header = parse(decode(parts[0],true));
      if (!header || Array.isArray(header) || typeof header !== 'object') throw new Error('Invalid JWT header');
      base64Bytes(parts[2],true);
      const payload = parse(decode(parts[1],true));
      if (!payload || Array.isArray(payload) || typeof payload !== 'object') throw new Error('JWT payload must be an object');
      return payload;
    }}),
    base64:freeze({encode: text => encode(text), decode:text => decode(text)}),
    base64url:freeze({encode:text => encode(text,true), decode:text => decode(text,true)}),
  });
  let logBytes = 0;
  let truncated = false;
  const byteCount = text => { let size=0; for (const char of text) { const n=char.codePointAt(0); size += n<128 ? 1 : n<2048 ? 2 : n<65536 ? 3 : 4; } return size; };
  function clip(text,maxBytes) {
    let size=0, result='';
    for (const char of text) { const bytes=byteCount(char); if (size+bytes>maxBytes) break; result+=char;size+=bytes; }
    return result;
  }
  function consoleValue(value,seen=new Set(),depth=0) {
    if (typeof value === 'string') return value;
    if (!value || typeof value !== 'object') return String(value);
    if (seen.has(value)) return '[Circular]';
    if (depth>=8) return '[Truncated]';
    seen.add(value);
    const parts=[];
    for (const key of Object.keys(value).slice(0,100)) parts.push((Array.isArray(value) ? '' : key+': ')+consoleValue(value[key],seen,depth+1));
    seen.delete(value);
    return (Array.isArray(value)?'[':'{')+parts.join(', ')+(Array.isArray(value)?']':'}');
  }
  function log(level,values) {
    if (truncated || input.limits.logEntries <= 0 || input.limits.logBytes <= 0) return;
    let message;
    try { message=values.map(value=>consoleValue(value)).join(' '); } catch (failure) { if (resourceFailure(failure)) throw failure; message='[Unserializable]'; }
    const bytes=byteCount(message);
    if (logs.length<input.limits.logEntries && logBytes+bytes<=input.limits.logBytes) {
      logs.push(freeze({level,message})); logBytes+=bytes; retainDiagnostics(); return;
    }
    truncated=true;
    const marker=clip('[Console truncated]',input.limits.logBytes);
    while (logs.length && (logs.length>=input.limits.logEntries || logBytes+byteCount(marker)>input.limits.logBytes)) logBytes-=byteCount(logs.pop().message);
    logs.push(freeze({level:'warn',message:marker}));
    retainDiagnostics();
  }
  const consoleApi = freeze({log:(...values)=>log('log',values),info:(...values)=>log('info',values),warn:(...values)=>log('warn',values),error:(...values)=>log('error',values)});
  try {
    await runUser(gm,consoleApi);
  } catch (failure) {
    if (resourceFailure(failure)) throw failure;
    aborted = true;
    error = {kind:'runtime',message:String(failure)+(failure && failure.stack ? '\n'+String(failure.stack) : '')};
  }
  // A callback may register more asynchronous tests while the current tail is
  // awaited. Track every async callback too, including immediate nested starts.
  let drained = 0;
  while (true) {
    const tail = testTail;
    if (tail !== null) await tail;
    while (drained < pendingTests.length) await pendingTests[drained++];
    if (tail === testTail) break;
  }
  return serializeOutput(true);
})
