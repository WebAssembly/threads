// META: global=window,dedicatedworker,jsshell
// META: script=/wasm/jsapi/wasm-module-builder.js
// META: script=/wasm/jsapi/memory/worker-path-helper.js

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

function waitForWorker(worker) {
  const msg = worker.getMessage();
  if (msg.type === 'error') {
    throw new Error('Worker error: ' + msg.message);
  }
  return msg.value;
}

function assert_within_timeout(start, seconds, message) {
  if (Date.now() - start > seconds * 1000) {
    throw new Error(message);
  }
}

// Async tests using workers.
if (typeof Worker !== 'undefined') {
  test(() => {
    const memory =
        new WebAssembly.Memory({initial: 1, maximum: 1, shared: true});
    const view = new Int32Array(memory.buffer);
    const worker = new Worker(getWorkerPath('wait-notify-worker.js'));

    view[0] = 0;
    view[1] = 0;  // ready index

    worker.postMessage({
      module: module,
      memory: memory,
      address: 0,
      expected: 0,
      timeout: -1n,
      readyIndex: 1
    });

    while (Atomics.load(view, 1) === 0);

    const instance = createInstance(module, memory);
    let notifyResult;
    const start = Date.now();
    while ((notifyResult = instance.exports.notify(0, 1)) === 0) {
      assert_within_timeout(
          start, 30, 'Worker should wake up within 30 seconds');
    }

    assert_equals(notifyResult, 1, 'Notify should wake up 1 waiter');
    const waitResult = waitForWorker(worker);
    assert_equals(waitResult, 0, 'Wait32 should return 0 (ok) when woken up');
    worker.terminate();
  }, 'Wait32 and Notify wake up 1 waiter');

  test(() => {
    const memory =
        new WebAssembly.Memory({initial: 1, maximum: 1, shared: true});
    const view = new Int32Array(memory.buffer);
    const worker1 = new Worker(getWorkerPath('wait-notify-worker.js'));
    const worker2 = new Worker(getWorkerPath('wait-notify-worker.js'));

    view[0] = 0;  // address 0
    view[1] = 0;  // address 4
    view[2] = 0;  // ready index 1
    view[3] = 0;  // ready index 2

    const msg = {module: module, memory: memory, timeout: -1n, expected: 0};
    worker1.postMessage({...msg, address: 0, readyIndex: 2});
    worker2.postMessage({...msg, address: 4, readyIndex: 3});

    while (Atomics.load(view, 2) === 0);
    while (Atomics.load(view, 3) === 0);

    const instance = createInstance(module, memory);

    let notified1;
    let start = Date.now();
    while ((notified1 = instance.exports.notify(0, 1)) === 0) {
      assert_within_timeout(
          start, 30, 'Worker 1 should wake up within 30 seconds');
    }
    assert_equals(notified1, 1, 'Notify 1');
    assert_equals(waitForWorker(worker1), 0);

    let notified2;
    start = Date.now();
    while ((notified2 = instance.exports.notify(4, 1)) === 0) {
      assert_within_timeout(
          start, 30, 'Worker 2 should wake up within 30 seconds');
    }
    assert_equals(notified2, 1, 'Notify 2');
    assert_equals(waitForWorker(worker2), 0);

    worker1.terminate();
    worker2.terminate();
  }, 'Two waiters on different addresses woken up one after the other');

  test(() => {
    const memory =
        new WebAssembly.Memory({initial: 1, maximum: 1, shared: true});
    const view = new Int32Array(memory.buffer);
    const worker1 = new Worker(getWorkerPath('wait-notify-worker.js'));
    const worker2 = new Worker(getWorkerPath('wait-notify-worker.js'));

    view[0] = 0;  // address 0
    view[2] = 0;  // ready index 1
    view[3] = 0;  // ready index 2

    const msg = {module: module, memory: memory, timeout: -1n, expected: 0};
    worker1.postMessage({...msg, address: 0, readyIndex: 2});
    worker2.postMessage({...msg, address: 0, readyIndex: 3});

    while (Atomics.load(view, 2) === 0);
    while (Atomics.load(view, 3) === 0);

    const instance = createInstance(module, memory);

    let notified = 0;
    const start = Date.now();
    while ((notified += instance.exports.notify(0, 2 - notified)) < 2) {
      assert_within_timeout(
          start, 30, 'Both workers should wake up within 30 seconds');
    }
    assert_equals(notified, 2, 'Notify 2 at once');

    assert_equals(waitForWorker(worker1), 0);
    assert_equals(waitForWorker(worker2), 0);

    worker1.terminate();
    worker2.terminate();
  }, 'Two waiters on same address woken up at once');
}
