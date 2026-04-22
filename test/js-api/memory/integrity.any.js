// META: global=window,dedicatedworker,jsshell

test(() => {
  const memory =
      new WebAssembly.Memory({'initial': 1, 'maximum': 2, 'shared': true});
  const buffer = memory.buffer;
  assert_true(Object.isFrozen(buffer), 'Shared buffer should be frozen');
  assert_throws_js(TypeError, () => {
    'use strict';
    buffer.x = 1;
  }, 'Cannot add property to frozen shared buffer');
}, 'Shared memory buffer integrity');

test(() => {
  const memory = new WebAssembly.Memory({'initial': 1});
  const buffer = memory.buffer;
  assert_false(
      Object.isFrozen(buffer), 'Non-shared buffer should not be frozen');
  assert_true(
      Object.isExtensible(buffer), 'Non-shared buffer should be extensible');
  buffer.x = 1;
  assert_equals(
      buffer.x, 1, 'Should be able to add property to non-shared buffer');
  delete buffer.x;
}, 'Non-shared memory buffer integrity');
