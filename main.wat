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
  ;;   0x6000  export table: 256 entries (0x6000..0x6fff)
  ;;   0x8000  value stack: 8-byte slots, grows up (0x8000..0xffff)

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
  (data (i32.const 0x1a2) "main")                   ;; 4 bytes  (0x1a2..0x1a5)
  (data (i32.const 0x1a6) "unsupported section")    ;; 19 bytes (0x1a6..0x1b8)
  (data (i32.const 0x1b9) "func count mismatch")    ;; 19 bytes (0x1b9..0x1cb)
  (data (i32.const 0x1d0) "too many locals")        ;; 15 bytes (0x1d0..0x1de)
  (data (i32.const 0x1df) "bad function body")      ;; 17 bytes (0x1df..0x1ef)
  (data (i32.const 0x1f0) "export not found")       ;; 16 bytes (0x1f0..0x1ff)
  (data (i32.const 0x200) "export ")                ;; 7 bytes  (0x200..0x206)
  (data (i32.const 0x207) ": kind ")                ;; 7 bytes  (0x207..0x20d)
  (data (i32.const 0x20e) " idx ")                  ;; 5 bytes  (0x20e..0x212)
  (data (i32.const 0x213) ", locals ")              ;; 9 bytes  (0x213..0x21b)
  (data (i32.const 0x21c) ", body ")                ;; 7 bytes  (0x21c..0x222)
  (data (i32.const 0x223) "..")                     ;; 2 bytes  (0x223..0x224)
  (data (i32.const 0x225) "0123456789abcdef")       ;; 16 bytes (0x225..0x234)
  (data (i32.const 0x235) "error: unimplemented opcode 0x")  ;; 30 bytes (0x235..0x252)
  (data (i32.const 0x253) "stack overflow")         ;; 14 bytes (0x253..0x260)
  (data (i32.const 0x261) "stack underflow")        ;; 15 bytes (0x261..0x26f)
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
  (global $export_count (mut i32) (i32.const 0))
  (global $sp (mut i32) (i32.const 0x8000))

  (type $op (func (result i32)))
  (table $ops 256 funcref)
  (elem (i32.const 0)
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl
    $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl $op_unimpl)
  (elem (i32.const 0x0b) $op_end)
  (elem (i32.const 0x41) $op_i32_const)

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

  ;; print the low byte of n as two hex digits
  (func $print_hex8 (param $fd i32) (param $n i32)
    (i32.store8 (i32.const 0x10)
      (i32.load8_u (i32.add (i32.const 0x225) (i32.and (i32.shr_u (local.get $n) (i32.const 4)) (i32.const 0xf)))))
    (i32.store8 (i32.const 0x11)
      (i32.load8_u (i32.add (i32.const 0x225) (i32.and (local.get $n) (i32.const 0xf)))))
    (call $print_str (local.get $fd) (i32.const 0x10) (i32.const 2)))

  ;; push an i32 onto the value stack
  (func $push_i32 (param $v i32)
    (if (i32.ge_u (global.get $sp) (i32.const 0x10000))
      (then (call $print_err (i32.const 0x253) (i32.const 14))))
    (i32.store (global.get $sp) (local.get $v))
    (global.set $sp (i32.add (global.get $sp) (i32.const 8))))

  ;; pop an i32 from the vakue stack
  (func $pop_i32 (result i32)
    (if (i32.le_u (global.get $sp) (i32.const 0x8000))
      (then (call $print_err (i32.const 0x261) (i32.const 15))))
    (global.set $sp (i32.sub (global.get $sp) (i32.const 8)))
    (i32.load (global.get $sp)))

  ;; returns 1 if the len bytes at a and b are equal
  (func $memeq (param $a i32) (param $b i32) (param $len i32) (result i32)
    (block $done
      (loop $next
        (br_if $done (i32.eqz (local.get $len)))
        (if (i32.ne (i32.load8_u (local.get $a)) (i32.load8_u (local.get $b)))
          (then (return (i32.const 0))))
        (local.set $a (i32.add (local.get $a) (i32.const 1)))
        (local.set $b (i32.add (local.get $b) (i32.const 1)))
        (local.set $len (i32.sub (local.get $len) (i32.const 1)))
        (br $next)))
    (i32.const 1))

  ;; returns the number of input bytes left after $pos
  (func $remaining (result i32)
    (i32.sub (i32.add (global.get $input_ptr) (global.get $input_len)) (global.get $pos)))

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

  ;; read signed LEB128
  (func $read_s32 (result i32)
    (local $result i32) (local $shift i32) (local $b i32)
    (loop $next
      (local.set $b (call $read_u8))
      (local.set $result (i32.or (local.get $result)
        (i32.shl (i32.and (local.get $b) (i32.const 0x7f)) (local.get $shift))))
      (local.set $shift (i32.add (local.get $shift) (i32.const 7)))
      (br_if $next (i32.and (local.get $b) (i32.const 0x80))))
    (if (i32.and (i32.lt_u (local.get $shift) (i32.const 32))
                 (i32.ne (i32.and (local.get $b) (i32.const 0x40)) (i32.const 0)))
      (then (local.set $result
        (i32.or (local.get $result) (i32.shl (i32.const -1) (local.get $shift))))))
    (local.get $result))

  ;; returns the address of type table entry i
  (func $get_type_entry (param $i i32) (result i32)
    (i32.add (i32.const 0x1000) (i32.shl (local.get $i) (i32.const 4))))

  ;; returns the address of func table entry i
  (func $get_func_entry (param $i i32) (result i32)
    (i32.add (i32.const 0x2000) (i32.shl (local.get $i) (i32.const 4))))

  ;; returns the address of export table entry i
  (func $get_export_entry (param $i i32) (result i32)
    (i32.add (i32.const 0x6000) (i32.shl (local.get $i) (i32.const 4))))

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

  ;; decode the export section into the export table
  (func $decode_export_section
    (local $i i32) (local $entry i32) (local $n i32)
    (global.set $export_count (call $read_u32))
    (if (i32.gt_u (global.get $export_count) (i32.const 256))
      (then (call $print_err (i32.const 0x146) (i32.const 10))))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $export_count)))
        (local.set $entry (call $get_export_entry (local.get $i)))
        (local.set $n (call $read_u32))
        (if (i32.gt_u (local.get $n) (call $remaining))
          (then (call $print_err (i32.const 0x119) (i32.const 14))))
        (i32.store (local.get $entry) (global.get $pos))
        (i32.store offset=4 (local.get $entry) (local.get $n))
        (global.set $pos (i32.add (global.get $pos) (local.get $n)))
        (i32.store offset=8 (local.get $entry) (call $read_u8))
        (i32.store offset=12 (local.get $entry) (call $read_u32))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

  ;; returns the index of the export with this name and kind
  (func $find_export (param $name i32) (param $len i32) (param $kind i32) (result i32)
    (local $i i32) (local $entry i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $export_count)))
        (local.set $entry (call $get_export_entry (local.get $i)))
        (if (i32.and (i32.eq (i32.load offset=8 (local.get $entry)) (local.get $kind))
                     (i32.eq (i32.load offset=4 (local.get $entry)) (local.get $len)))
          (then
            (if (call $memeq (i32.load (local.get $entry)) (local.get $name) (local.get $len))
              (then (return (i32.load offset=12 (local.get $entry)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (i32.const -1))

  ;; decode the code section
  (func $decode_code_section
    (local $i i32) (local $entry i32) (local $size i32) (local $end i32)
    (local $ndecl i32) (local $n i32) (local $nlocals i32)
    (if (i32.ne (call $read_u32) (global.get $func_count))
      (then (call $print_err (i32.const 0x1b9) (i32.const 19))))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $func_count)))
        (local.set $entry (call $get_func_entry (local.get $i)))
        (local.set $size (call $read_u32))
        (if (i32.gt_u (local.get $size) (call $remaining))
          (then (call $print_err (i32.const 0x119) (i32.const 14))))
        (local.set $end (i32.add (global.get $pos) (local.get $size)))
        (local.set $nlocals (i32.const 0))
        (local.set $ndecl (call $read_u32))
        (block $decls_done
          (loop $decl
            (br_if $decls_done (i32.eqz (local.get $ndecl)))
            (local.set $n (call $read_u32))
            (call $read_valtypes (i32.const 1))
            (if (i32.gt_u (local.get $n) (i32.sub (i32.const 65536) (local.get $nlocals)))
              (then (call $print_err (i32.const 0x1d0) (i32.const 15))))
            (local.set $nlocals (i32.add (local.get $nlocals) (local.get $n)))
            (local.set $ndecl (i32.sub (local.get $ndecl) (i32.const 1)))
            (br $decl)))
        (i32.store offset=4 (local.get $entry) (local.get $nlocals))
        (i32.store offset=8 (local.get $entry) (global.get $pos))
        (i32.store offset=12 (local.get $entry) (local.get $end))
        ;; the body must hold at least the final end opcode (0x0b)
        (if (i32.ge_u (global.get $pos) (local.get $end))
          (then (call $print_err (i32.const 0x1df) (i32.const 17))))
        (if (i32.ne (i32.load8_u (i32.sub (local.get $end) (i32.const 1))) (i32.const 0x0b))
          (then (call $print_err (i32.const 0x1df) (i32.const 17))))
        (global.set $pos (local.get $end))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

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
        (local.set $entry (call $get_func_entry (local.get $i)))
        (call $print_str (i32.const 1) (i32.const 0x19d) (i32.const 5))
        (call $print_u32 (i32.const 1) (local.get $i))
        (call $print_str (i32.const 1) (i32.const 0x197) (i32.const 2))
        (call $print_str (i32.const 1) (i32.const 0x192) (i32.const 5))
        (call $print_u32 (i32.const 1) (i32.load (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x213) (i32.const 9))
        (call $print_u32 (i32.const 1) (i32.load offset=4 (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x21c) (i32.const 7))
        (call $print_u32 (i32.const 1) (i32.sub (i32.load offset=8 (local.get $entry)) (global.get $input_ptr)))
        (call $print_str (i32.const 1) (i32.const 0x223) (i32.const 2))
        (call $print_u32 (i32.const 1) (i32.sub (i32.load offset=12 (local.get $entry)) (global.get $input_ptr)))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (local.set $i (i32.const 0))
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (global.get $export_count)))
        (local.set $entry (call $get_export_entry (local.get $i)))
        (call $print_str (i32.const 1) (i32.const 0x200) (i32.const 7))
        (call $print_str (i32.const 1) (i32.load (local.get $entry)) (i32.load offset=4 (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x207) (i32.const 7))
        (call $print_u32 (i32.const 1) (i32.load offset=8 (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x20e) (i32.const 5))
        (call $print_u32 (i32.const 1) (i32.load offset=12 (local.get $entry)))
        (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next))))

  ;; print error `op not implemented yet` and exit
  (func $op_unimpl (result i32)
    (call $print_str (i32.const 2) (i32.const 0x235) (i32.const 30))
    (call $print_hex8 (i32.const 2) (i32.load8_u (i32.sub (global.get $pos) (i32.const 1))))
    (call $print_str (i32.const 2) (i32.const 0x107) (i32.const 1))
    (call $proc_exit (i32.const 1))
    unreachable)

  ;; 0x0b end
  (func $op_end (result i32)
    (i32.const 1))

  ;; 0x41 i32.const push signed LEB128 immediate
  (func $op_i32_const (result i32)
    (call $push_i32 (call $read_s32))
    (i32.const 0))

  ;; run instructions from $pos
  (func $exec_run
    (loop $next
      (br_if $next (i32.eqz (call_indirect (type $op) (call $read_u8))))))

  ;; decode the embedded module
  (func $decode_module
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
        (block $handled
          (if (i32.eq (local.get $id) (i32.const 1)) (then (call $decode_type_section) (br $handled)))
          (if (i32.eq (local.get $id) (i32.const 3)) (then (call $decode_function_section) (br $handled)))
          (if (i32.eq (local.get $id) (i32.const 7)) (then (call $decode_export_section) (br $handled)))
          (if (i32.eq (local.get $id) (i32.const 10)) (then (call $decode_code_section) (br $handled)))
          (if (i32.eqz (local.get $id))
            (then (global.set $pos (i32.add (global.get $pos) (local.get $size))) (br $handled)))
          (call $print_err (i32.const 0x1a6) (i32.const 19)))
        (if (i32.ne (global.get $pos) (i32.add (local.get $start) (local.get $size)))
          (then (call $print_err (i32.const 0x17d) (i32.const 21))))
        (br $continue))))

  ;; run function funcidx on an empty value stack until it returns
  (func $run_func (param $funcidx i32)
    (global.set $sp (i32.const 0x8000))
    (global.set $pos (i32.load offset=8 (call $get_func_entry (local.get $funcidx))))
    (call $exec_run))

  (func (export "_start")
    (local $main i32)
    (call $decode_module)
    (call $print_tables)
    ;; look up `main` and print function index
    (local.set $main (call $find_export (i32.const 0x1a2) (i32.const 4) (i32.const 0)))
    (if (i32.eq (local.get $main) (i32.const -1))
      (then (call $print_err (i32.const 0x1f0) (i32.const 16))))
    (call $print_str (i32.const 1) (i32.const 0x1a2) (i32.const 4))
    (call $print_str (i32.const 1) (i32.const 0x199) (i32.const 4))
    (call $print_str (i32.const 1) (i32.const 0x19d) (i32.const 5))
    (call $print_u32 (i32.const 1) (local.get $main))
    (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1))
    ;; run main and print the result it left on the value stack
    (call $run_func (local.get $main))
    (call $print_u32 (i32.const 1) (call $pop_i32))
    (call $print_str (i32.const 1) (i32.const 0x107) (i32.const 1)))
)
