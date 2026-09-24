(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Static memory layout
  ;;   0x000  iovec for fd_write (ptr at 0x000, len at 0x004)
  ;;   0x008  nwritten
  ;;   0x100  string constants
  ;;   0x400  input module

  (data (i32.const 0x100) "error: ")            ;; 7 bytes
  (data (i32.const 0x107) "\n")                 ;; 1 byte
  (data (i32.const 0x108) "not a wasm module")  ;; 17 bytes
  (data (i32.const 0x115) "ok\n")               ;; 3 bytes
  (data (i32.const 0x400)
    "\25\00\00\00" ;; length
    ;; (module (func (export "main") (result i32) i32.const 42))
    "\00\61\73\6d" "\01\00\00\00"
    "\01\05\01\60\00\01\7f" "\03\02\01\00"
    "\07\08\01\04main\00\00" "\0a\06\01\04\00\41\2a\0b")

  (global $input_ptr (mut i32) (i32.const 0))
  (global $input_len (mut i32) (i32.const 0))

  ;; write len bytes from ptr to fd
  (func $print_str (param $fd i32) (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (drop (call $fd_write (local.get $fd) (i32.const 0) (i32.const 1) (i32.const 8))))

  ;; print "error: " + ptr message + "\n" to stderr and exit with code 1
  (func $print_err (param $ptr i32) (param $len i32)
    (call $print_str (i32.const 2) (i32.const 0x100) (i32.const 7))
    (call $print_str (i32.const 2) (local.get $ptr) (local.get $len))
    (call $print_str (i32.const 2) (i32.const 0x107) (i32.const 1))
    (call $proc_exit (i32.const 1)))

  (func (export "_start")
    (global.set $input_len (i32.load (i32.const 0x400)))
    (global.set $input_ptr (i32.const 0x404))
    ;; throw a error if header is not 0x6d736100, or version not 1
    (if (i32.or
        (i32.ne (i32.load (global.get $input_ptr)) (i32.const 0x6d736100))
        (i32.ne (i32.load offset=4 (global.get $input_ptr)) (i32.const 1)))
      (then (call $print_err (i32.const 0x108) (i32.const 17)))
      (else (call $print_str (i32.const 1) (i32.const 0x115) (i32.const 3)))))
)
