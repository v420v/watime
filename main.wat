(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Static memory layout
  ;;   0x000   iovec for fd_write (ptr at 0x000, len at 0x004)
  ;;   0x008   nwritten
  ;;   0x010   digit buffer for $print_u32 (0x010..0x019)
  ;;   0x100   string constants
  ;;   0x400   input module
  ;;   0x1000  type table: 256 entries (0x1000..0x1fff)
  ;;   0x2000  func table: 1024 entries (0x2000..0x5fff)

  (data (i32.const 0x100) "error: ")                ;; 7 bytes  (0x100..0x106)
  (data (i32.const 0x107) "\n")                     ;; 1 byte   (0x107)
  (data (i32.const 0x108) "not a wasm module")      ;; 17 bytes (0x108..0x118)
  (data (i32.const 0x119) "unexpected end")         ;; 14 bytes (0x119..0x126)
  (data (i32.const 0x127) "bad section id")         ;; 14 bytes (0x127..0x134)
  (data (i32.const 0x135) "ok\n")                   ;; 3 bytes  (0x135..0x137)
  (data (i32.const 0x138) "section ")               ;; 8 bytes  (0x138..0x13f)
  (data (i32.const 0x140) " size ")                 ;; 6 bytes  (0x140..0x145)
  (data (i32.const 0x146) "table full")             ;; 10 bytes (0x146..0x14f)
  (data (i32.const 0x150) "bad functype")           ;; 12 bytes (0x150..0x15b)
  (data (i32.const 0x15c) "unsupported valtype")    ;; 19 bytes (0x15c..0x16e)
  (data (i32.const 0x16f) "bad type index")         ;; 14 bytes (0x16f..0x17c)
  (data (i32.const 0x17d) "section size mismatch")  ;; 21 bytes (0x17d..0x191)
  (data (i32.const 0x192) "type ")                  ;; 5 bytes  (0x192..0x196)
  (data (i32.const 0x197) ": ")                     ;; 2 bytes  (0x197..0x198)
  (data (i32.const 0x199) " -> ")                   ;; 4 bytes  (0x199..0x19c)
  (data (i32.const 0x19d) "func ")                  ;; 5 bytes  (0x19d..0x1a1)
  (data (i32.const 0x400)
    "\25\00\00\00" ;; length
    ;; (module (func (export "main") (result i32) i32.const 42))
    "\00\61\73\6d" "\01\00\00\00"
    "\01\05\01\60\00\01\7f" "\03\02\01\00"
    "\07\08\01\04main\00\00" "\0a\06\01\04\00\41\2a\0b")

  (global $input_ptr (mut i32) (i32.const 0))
  (global $input_len (mut i32) (i32.const 0))
  (global $pos (mut i32) (i32.const 0))
  (global $type_count (mut i32) (i32.const 0))
  (global $func_count (mut i32) (i32.const 0))

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

  ;; returns the address of type table entry i
  (func $get_type_entry (param $i i32) (result i32)
    (i32.add (i32.const 0x1000) (i32.shl (local.get $i) (i32.const 4))))

  ;; returns the address of func table entry i
  (func $get_func_entry (param $i i32) (result i32)
    (i32.add (i32.const 0x2000) (i32.shl (local.get $i) (i32.const 4))))

  ;; read n valtypes
  (func $read_valtypes (param $n i32)
    (local $t i32)
    (block $done
      (loop $next
        (br_if $done (i32.eqz (local.get $n)))
        (local.set $t (call $read_u8))
        ;; only i32 (0x7f) and i64 (0x7e) are accepted
        (if (i32.and (i32.ne (local.get $t) (i32.const 0x7f)) (i32.ne (local.get $t) (i32.const 0x7e)))
          (then (call $print_err (i32.const 0x15c) (i32.const 19))))
        (local.set $n (i32.sub (local.get $n) (i32.const 1)))
        (br $next))))

  ;; decode the type section into the type table
  (func $decode_type_section
    (local $i i32) (local $entry i32) (local $n i32)
    (global.set $type_count (call $read_u32))
    (if (i32.gt_u (global.get $type_count) (i32.const 256))
      (then (call $print_err (i32.const 0x146) (i32.const 10))))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $type_count)))
        (local.set $entry (call $get_type_entry (local.get $i)))
        (if (i32.ne (call $read_u8) (i32.const 0x60))
          (then (call $print_err (i32.const 0x150) (i32.const 12))))
        (local.set $n (call $read_u32))
        (i32.store (local.get $entry) (local.get $n))
        (i32.store offset=8 (local.get $entry) (global.get $pos))
        (call $read_valtypes (local.get $n))
        (local.set $n (call $read_u32))
        (i32.store offset=4 (local.get $entry) (local.get $n))
        (i32.store offset=12 (local.get $entry) (global.get $pos))
        (call $read_valtypes (local.get $n))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

  ;; decode the function section into the func table
  (func $decode_function_section
    (local $i i32) (local $t i32)
    (global.set $func_count (call $read_u32))
    (if (i32.gt_u (global.get $func_count) (i32.const 1024))
      (then (call $print_err (i32.const 0x146) (i32.const 10))))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $func_count)))
        (local.set $t (call $read_u32))
        (if (i32.ge_u (local.get $t) (global.get $type_count))
          (then (call $print_err (i32.const 0x16f) (i32.const 14))))
        (i32.store (call $get_func_entry (local.get $i)) (local.get $t))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

  ;; print types and functions
  (func $print_tables
    (local $i i32) (local $entry i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $type_count)))
        (local.set $entry (call $get_type_entry (local.get $i)))
        (call $print_str (i32.const 1) (i32.const 0x192) (i32.const 5))
        (call $print_u32 (i32.const 1) (local.get $i))
        (call $print_str (i32.const 1) (i32.const 0x197) (i32.const 2))
        (call $print_u32 (i32.const 1) (i32.load (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x199) (i32.const 4))
        (call $print_u32 (i32.const 1) (i32.load offset=4 (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (local.set $i (i32.const 0))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $func_count)))
        (call $print_str (i32.const 1) (i32.const 0x19d) (i32.const 5))
        (call $print_u32 (i32.const 1) (local.get $i))
        (call $print_str (i32.const 1) (i32.const 0x197) (i32.const 2))
        (call $print_str (i32.const 1) (i32.const 0x192) (i32.const 5))
        (call $print_u32 (i32.const 1) (i32.load (call $get_func_entry (local.get $i))))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

  (func (export "_start")
    (local $end i32)
    (local $id i32)
    (local $size i32)
    (local $start i32)
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
    ;; parse and print id, size
    (local.set $end (i32.add (global.get $input_ptr) (global.get $input_len)))
    (global.set $pos (i32.add (global.get $input_ptr) (i32.const 8)))
    (block $done
      (loop $continue
        (br_if $done (i32.ge_u (global.get $pos) (local.get $end)))
        (local.set $id (call $read_u8))
        (local.set $size (call $read_u32))
        (if (i32.gt_u (local.get $id) (i32.const 12))
          (then (call $print_err (i32.const 0x127) (i32.const 14))))
        (if (i32.gt_u (local.get $size) (i32.sub (local.get $end) (global.get $pos)))
          (then (call $print_err (i32.const 0x119) (i32.const 14))))
        (call $print_str (i32.const 1) (i32.const 0x138) (i32.const 8))
        (call $print_u32 (i32.const 1) (local.get $id))
        (call $print_str (i32.const 1) (i32.const 0x140) (i32.const 6))
        (call $print_u32 (i32.const 1) (local.get $size))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        ;; decode the body or skip it
        (local.set $start (global.get $pos))
        (if (i32.eq (local.get $id) (i32.const 1))
          (then (call $decode_type_section))
          (else (if (i32.eq (local.get $id) (i32.const 3))
            (then (call $decode_function_section))
            (else (global.set $pos (i32.add (global.get $pos) (local.get $size)))))))
        (if (i32.ne (global.get $pos) (i32.add (local.get $start) (local.get $size)))
          (then (call $print_err (i32.const 0x17d) (i32.const 21))))
        (br $continue)))
    (call $print_tables))
)
