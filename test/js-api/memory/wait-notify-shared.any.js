// META: global=window,dedicatedworker,jsshell
// META: script=/wasm/jsapi/wasm-module-builder.js

function createModule() {
  const builder = new WasmModuleBuilder();
  // Import memory instead of creating a local one.
  builder.addImportedMemory('env', 'memory', 1, 1, true);  // shared
  builder.exportMemoryAs('memory');

  const kSig_i_iil = makeSig([kWasmI32, kWasmI32, kWasmI64], [kWasmI32]);
  builder.addFunction('wait', kSig_i_iil)
      .addBody([
        kExprLocalGet, 0, kExprLocalGet, 1, kExprLocalGet, 2,
        kAtomicPrefix, kExprI32AtomicWait, 2, 0
      ])
      .exportFunc();

  builder.addFunction('notify', kSig_i_ii)
      .addBody([
        kExprLocalGet, 0, kExprLocalGet, 1,
        kAtomicPrefix, kExprAtomicNotify, 2, 0
      ])
      .exportFunc();

  return builder.toModule();
}

function createInstance(module, memory) {
  if (!memory) {
    memory = new WebAssembly.Memory({initial: 1, maximum: 1, shared: true});
  }
  return new WebAssembly.Instance(module, {env: {memory: memory}});
}

const module = createModule();

test(() => {
  const instance = createInstance(module);
  const buffer = new Int32Array(instance.exports.memory.buffer);
  buffer[0] = 0;

  const result = instance.exports.wait(0, 1, -1n);
  assert_equals(
      result, 1, 'Wait32 should return 1 (not-equal) if value doesn\'t match');
}, 'Wait32 (not-equal) on shared memory');

test(() => {
  const instance = createInstance(module);
  const buffer = new Int32Array(instance.exports.memory.buffer);
  buffer[0] = 0;

  const result = instance.exports.wait(0, 0, 1000000n);  // 1ms timeout
  assert_equals(result, 2, 'Wait32 should return 2 (timed-out) after timeout');
}, 'Wait32 (timed-out) on shared memory');

test(() => {
  const instance = createInstance(module);
  const result = instance.exports.notify(0, 1);
  assert_equals(
      result, 0, 'Notify should return 0 (number of waiters notified)');
}, 'Notify on shared memory (0 waiters)');
