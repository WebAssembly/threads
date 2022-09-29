function assert(expected_true, function_name, description, error, substitutions) {
  if (expected_true !== true) {
    console.log(substitutions);
    throw new Error("assert failure in worker " + description);
  }
}

function promise_test(){}

function test(func, name){
  try{
    func();
    console.log("worker - test passed");
  } catch(e) {
    console.log("worker - test failed:");
    const loc = e.stack.toString().replace("Error", "");
    self.postMessage({type: "fail", name: name, loc: loc});
  }
}

function test_num(){ return 0 }

function assert_true(actual, description) {
  assert(actual === true, "assert_true", description,
                        "expected true got ${actual}", {actual:actual});
}

function assert_false(actual, description) {
  assert(actual === false, "assert_false", description,
                         "expected false got ${actual}", {actual:actual});
}

function same_value(x, y) {
if (y !== y) {
    //NaN case
    return x !== x;
}
if (x === 0 && y === 0) {
    //Distinguish +0 and -0
    return 1/x === 1/y;
}
return x === y;
}

function assert_equals(actual, expected, description) {
 /*
  * Test if two primitives are equal or two objects
  * are the same object
  */
  if (typeof actual != typeof expected) {
      assert(false, "assert_equals", description,
                    "expected (" + typeof expected + ") ${expected} but got (" + typeof actual + ") ${actual}",
                    {expected:expected, actual:actual});
    return;
  }
  assert(same_value(actual, expected), "assert_equals", description,
                                       "expected ${expected} but got ${actual}",
                                       {expected:expected, actual:actual});
}


importScripts("async_index.js");

self.onmessage = function(e) {
  e.data.scope.forEach(element => self[element[0]] = Promise.resolve(element[1]));
  importScripts(e.data.filename);
  chain.then(e => {console.log("posting done"); self.postMessage({type: "done"});});
};
