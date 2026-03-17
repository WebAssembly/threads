// META: global=window,dedicatedworker,jsshell
// META: script=/wasm/jsapi/wasm-module-builder.js

test(() => {
  const builder = new WasmModuleBuilder();
  builder.addMemory(1, 1, false, false);
  builder.addFunction('notify', kSig_i_ii)
      .addBody([
        kExprLocalGet, 0, kExprLocalGet, 1, kAtomicPrefix, kExprAtomicNotify, 2,
        0
      ])
      .exportFunc();
  const instance = builder.instantiate();
  const result = instance.exports.notify(0, 1);
  assert_equals(result, 0, 'Notify on unshared memory should return 0');
}, 'Notify on unshared memory');

test(() => {
  const builder = new WasmModuleBuilder();
  builder.addMemory(1, 1, false, false);
  const kSig_i_iil = makeSig([kWasmI32, kWasmI32, kWasmI64], [kWasmI32]);
  builder.addFunction('wait', kSig_i_iil)
      .addBody([
        kExprLocalGet, 0, kExprLocalGet, 1, kExprLocalGet, 2, kAtomicPrefix,
        kExprI32AtomicWait, 2, 0
      ])
      .exportFunc();
  const instance = builder.instantiate();
  // This should trap. We use a non-infinite timeout to avoid hanging if the
  // trap is not implemented.
  assert_throws_js(
      WebAssembly.RuntimeError, () => instance.exports.wait(0, 0, 1000n),
      'Wait on unshared memory should trap');
}, 'Wait on unshared memory traps');
