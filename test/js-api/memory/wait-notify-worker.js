onmessage = function(event) {
  try {
    const {module, memory, address, expected, timeout, readyIndex} = event.data;
    const instance = new WebAssembly.Instance(module, {env: {memory: memory}});
    const view = new Int32Array(memory.buffer);

    // Signal readiness.
    Atomics.store(view, readyIndex, 1);

    // Wait.
    const result = instance.exports.wait(address, expected, timeout);

    postMessage({type: 'result', value: result});
  } catch (e) {
    postMessage({type: 'error', message: e.toString()});
  }
};
