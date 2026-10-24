// Runs a WASI module (`ocaml-emcc link --wasi`) with node's WASI, as
// tests/run.sh --wasi does when wasmtime is not installed:
//   node tests/wasi-run.mjs prog.wasm args...
// The current directory and /tmp are preopened, the environment inherited.
import { WASI } from 'node:wasi';
import { readFileSync } from 'node:fs';

const [file, ...args] = process.argv.slice(2);
const wasi = new WASI({
  version: 'preview1',
  args: [file, ...args],
  env: process.env,
  preopens: { '.': process.cwd(), '/tmp': '/tmp' },
  returnOnExit: true,
});
const { instance } = await WebAssembly.instantiate(readFileSync(file), wasi.getImportObject());
process.exitCode = wasi.start(instance);
