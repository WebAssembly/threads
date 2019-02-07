let harness =
  "'use strict';\n" ^
  "\n" ^
  "let spectest = {\n" ^
  "  print: console.log.bind(console),\n" ^
  "  print_i32: console.log.bind(console),\n" ^
  "  print_i32_f32: console.log.bind(console),\n" ^
  "  print_f64_f64: console.log.bind(console),\n" ^
  "  print_f32: console.log.bind(console),\n" ^
  "  print_f64: console.log.bind(console),\n" ^
  "  global_i32: 666,\n" ^
  "  global_f32: 666,\n" ^
  "  global_f64: 666,\n" ^
  "  table: new WebAssembly.Table({initial: 10, maximum: 20, element: 'anyfunc'}),\n" ^
  "  memory: new WebAssembly.Memory({initial: 1, maximum: 2})\n" ^
  "};\n" ^
  "let handler = {\n" ^
  "  get(target, prop) {\n" ^
  "    return (prop in target) ?  target[prop] : {};\n" ^
  "  }\n" ^
  "};\n" ^
  "let registry = new Proxy({spectest}, handler);\n" ^
  "\n" ^
  "function register(name, instance) {\n" ^
  "  registry[name] = instance.exports;\n" ^
  "}\n" ^
  "\n" ^
  "function module(bytes, valid = true) {\n" ^
  "  let buffer = new ArrayBuffer(bytes.length);\n" ^
  "  let view = new Uint8Array(buffer);\n" ^
  "  for (let i = 0; i < bytes.length; ++i) {\n" ^
  "    view[i] = bytes.charCodeAt(i);\n" ^
  "  }\n" ^
  "  let validated;\n" ^
  "  try {\n" ^
  "    validated = WebAssembly.validate(buffer);\n" ^
  "  } catch (e) {\n" ^
  "    throw new Error(\"Wasm validate throws\");\n" ^
  "  }\n" ^
  "  if (validated !== valid) {\n" ^
  "    throw new Error(\"Wasm validate failure\" + (valid ? \"\" : \" expected\"));\n" ^
  "  }\n" ^
  "  return new WebAssembly.Module(buffer);\n" ^
  "}\n" ^
  "\n" ^
  "function instance(bytes, imports = registry) {\n" ^
  "  return new WebAssembly.Instance(module(bytes), imports);\n" ^
  "}\n" ^
  "\n" ^
  "function call(instance, name, args) {\n" ^
  "  return instance.exports[name](...args);\n" ^
  "}\n" ^
  "\n" ^
  "function get(instance, name) {\n" ^
  "  let v = instance.exports[name];\n" ^
  "  return (v instanceof WebAssembly.Global) ? v.value : v;\n" ^
  "}\n" ^
  "\n" ^
  "function exports(name, instance) {\n" ^
  "  return {[name]: instance.exports};\n" ^
  "}\n" ^
  "\n" ^
  "function run(action) {\n" ^
  "  action();\n" ^
  "}\n" ^
  "\n" ^
  "function assert_malformed(bytes) {\n" ^
  "  try { module(bytes, false) } catch (e) {\n" ^
  "    if (e instanceof WebAssembly.CompileError) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm decoding failure expected\");\n" ^
  "}\n" ^
  "\n" ^
  "function assert_invalid(bytes) {\n" ^
  "  try { module(bytes, false) } catch (e) {\n" ^
  "    if (e instanceof WebAssembly.CompileError) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm validation failure expected\");\n" ^
  "}\n" ^
  "\n" ^
  "function assert_unlinkable(bytes) {\n" ^
  "  let mod = module(bytes);\n" ^
  "  try { new WebAssembly.Instance(mod, registry) } catch (e) {\n" ^
  "    if (e instanceof WebAssembly.LinkError) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm linking failure expected\");\n" ^
  "}\n" ^
  "\n" ^
  "function assert_uninstantiable(bytes) {\n" ^
  "  let mod = module(bytes);\n" ^
  "  try { new WebAssembly.Instance(mod, registry) } catch (e) {\n" ^
  "    if (e instanceof WebAssembly.RuntimeError) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm trap expected\");\n" ^
  "}\n" ^
  "\n" ^
  "function assert_trap(action) {\n" ^
  "  try { action() } catch (e) {\n" ^
  "    if (e instanceof WebAssembly.RuntimeError) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm trap expected\");\n" ^
  "}\n" ^
  "\n" ^
  "let StackOverflow;\n" ^
  "try { (function f() { 1 + f() })() } catch (e) { StackOverflow = e.constructor }\n" ^
  "\n" ^
  "function assert_exhaustion(action) {\n" ^
  "  try { action() } catch (e) {\n" ^
  "    if (e instanceof StackOverflow) return;\n" ^
  "  }\n" ^
  "  throw new Error(\"Wasm resource exhaustion expected\");\n" ^
  "}\n" ^
  "\n" ^
  "function assert_return(action, expected) {\n" ^
  "  let actual = action();\n" ^
  "  if (!Object.is(actual, expected)) {\n" ^
  "    throw new Error(\"Wasm return value \" + expected + \" expected, got \" + actual);\n" ^
  "  };\n" ^
  "}\n" ^
  "\n" ^
  "function assert_return_canonical_nan(action) {\n" ^
  "  let actual = action();\n" ^
  "  // Note that JS can't reliably distinguish different NaN values,\n" ^
  "  // so there's no good way to test that it's a canonical NaN.\n" ^
  "  if (!Number.isNaN(actual)) {\n" ^
  "    throw new Error(\"Wasm return value NaN expected, got \" + actual);\n" ^
  "  };\n" ^
  "}\n" ^
  "\n" ^
  "function assert_return_arithmetic_nan(action) {\n" ^
  "  // Note that JS can't reliably distinguish different NaN values,\n" ^
  "  // so there's no good way to test for specific bitpatterns here.\n" ^
  "  let actual = action();\n" ^
  "  if (!Number.isNaN(actual)) {\n" ^
  "    throw new Error(\"Wasm return value NaN expected, got \" + actual);\n" ^
  "  };\n" ^
  "}\n" ^
  "\n"
