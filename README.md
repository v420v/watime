# watime: WebAssembly runtime written in WAT

A WebAssembly runtime written in WebAssembly Text Format.
The goal is self-hosting, watime running a copy of watime.

## Requirements

- [wabt](https://github.com/WebAssembly/wabt) (`wat2wasm`, `wasm-objdump`)
- [wasmtime](https://wasmtime.dev/)

```sh
brew install wabt wasmtime
```

## Run

```sh
wat2wasm main.wat -o main.wasm
wat2wasm examples/const42.wat -o const42.wasm
wasmtime --dir=. main.wasm const42.wasm
```

The input file is opened relative to the directory passed with `--dir`,
so give a relative path.
