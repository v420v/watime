(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Static memory layout
  ;;   0x000  iovec for fd_write (ptr at 0x000, len at 0x004)
  ;;   0x008  nwritten
  ;;   0x010  digit buffer for $print_u32 (0x010..0x019)
  ;;   0x100  string constants
  ;;   0x400  input module

  (data (i32.const 0x100) "error: ")            ;; 7 bytes  (0x100..0x106)
  (data (i32.const 0x107) "\n")                 ;; 1 byte   (0x107)
  (data (i32.const 0x108) "not a wasm module")  ;; 17 bytes (0x108..0x118)
  (data (i32.const 0x119) "unexpected end")     ;; 14 bytes (0x119..0x126)
  (data (i32.const 0x127) "bad section id")     ;; 14 bytes (0x127..0x134)
  (data (i32.const 0x135) "ok\n")               ;; 3 bytes  (0x135..0x137)
  (data (i32.const 0x138) "section ")           ;; 8 bytes  (0x138..0x13f)
  (data (i32.const 0x140) " size ")             ;; 6 bytes  (0x140..0x145)
  (data (i32.const 0x400)
    "\25\00\00\00" ;; length
    ;; (module (func (export "main") (result i32) i32.const 42))
    "\00\61\73\6d" "\01\00\00\00"
    "\01\05\01\60\00\01\7f" "\03\02\01\00"
    "\07\08\01\04main\00\00" "\0a\06\01\04\00\41\2a\0b")

  (global $input_ptr (mut i32) (i32.const 0))
  (global $input_len (mut i32) (i32.const 0))
  (global $pos (mut i32) (i32.const 0))

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

  ;; print n in decimal
  (func $print_u32 (param $fd i32) (param $n i32)
    (local $p i32)
    (local.set $p (i32.const 0x1a))
    (loop $next
      (local.set $p (i32.sub (local.get $p) (i32.const 1)))
      (i32.store8 (local.get $p)
        (i32.add (i32.rem_u (local.get $n) (i32.const 10)) (i32.const 48)))
      (local.set $n (i32.div_u (local.get $n) (i32.const 10)))
      (br_if $next (local.get $n)))
    (call $print_str (local.get $fd) (local.get $p) (i32.sub (i32.const 0x1a) (local.get $p))))

  ;; read one byte at $pos and advance
  (func $read_u8 (result i32)
    (local $b i32)
    (if (i32.ge_u (global.get $pos) (i32.add (global.get $input_ptr) (global.get $input_len)))
      (then (call $print_err (i32.const 0x119) (i32.const 14))))  ;; "unexpected end"
    (local.set $b (i32.load8_u (global.get $pos)))
    (global.set $pos (i32.add (global.get $pos) (i32.const 1)))
    (local.get $b))

  ;; read unsigned LEB128
  (func $read_u32 (result i32)
    (local $result i32) (local $shift i32) (local $b i32)
    (loop $next
      (local.set $b (call $read_u8))
      (local.set $result (i32.or (local.get $result)
        (i32.shl (i32.and (local.get $b) (i32.const 0x7f)) (local.get $shift))))
      (local.set $shift (i32.add (local.get $shift) (i32.const 7)))
      (br_if $next (i32.and (local.get $b) (i32.const 0x80))))
    (local.get $result))

  (func (export "_start")
    (local $end i32)
    (local $id i32)
    (local $size i32)
    (global.set $input_len (i32.load (i32.const 0x400)))
    (global.set $input_ptr (i32.const 0x404))
    (if (i32.lt_u (global.get $input_len) (i32.const 8))
      (then (call $print_err (i32.const 0x119) (i32.const 14))))
    ;; throw a error if header is not 0x6d736100, or version not 1
    (if (i32.or
        (i32.ne (i32.load (global.get $input_ptr)) (i32.const 0x6d736100))
        (i32.ne (i32.load offset=4 (global.get $input_ptr)) (i32.const 1)))
      (then (call $print_err (i32.const 0x108) (i32.const 17)))
      (else (call $print_str (i32.const 1) (i32.const 0x135) (i32.const 3))))
    ;; parse and print section id and size
    (local.set $end (i32.add (global.get $input_ptr) (global.get $input_len)))
    (global.set $pos (i32.add (global.get $input_ptr) (i32.const 8)))
    (block $done
      (loop $continue
        (br_if $done (i32.ge_u (global.get $pos) (local.get $end)))
        (local.set $id (call $read_u8))
        (local.set $size (call $read_u32))
        (if (i32.gt_u (local.get $id) (i32.const 12))
          (then (call $print_err (i32.const 0x127) (i32.const 14))))
        (if (i32.gt_u (i32.add (global.get $pos) (local.get $size)) (local.get $end))
          (then (call $print_err (i32.const 0x119) (i32.const 14))))
        (call $print_str (i32.const 1) (i32.const 0x138) (i32.const 8))
        (call $print_u32 (i32.const 1) (local.get $id))
        (call $print_str (i32.const 1) (i32.const 0x140) (i32.const 6))
        (call $print_u32 (i32.const 1) (local.get $size))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        (global.set $pos (i32.add (global.get $pos) (local.get $size)))
        (br $continue))))
)
