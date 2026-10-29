;; wasm_of_ocaml side of the bridge to C stubs compiled by emscripten
;; (prototype).  See bridge.c.
;;
;; to_c: a GC value -> a linear-memory value (copied; closures become
;;   bytecode closures calling back; exception constructors are paired)
;; of_c: a linear-memory value -> a GC value (copied; custom and abstract
;;   blocks become handles on the C value)

(module
   (import "env" "ocaml_exception" (tag $ocaml_exception (param (ref eq))))
   (import "env" "caml_failwith" (func $caml_failwith (param (ref eq))))
   (import "env" "caml_get_global_data"
      (func $caml_get_global_data (param (ref eq)) (result (ref eq))))
   (import "env" "caml_named_value"
      (func $caml_named_value (param (ref eq)) (result (ref null eq))))
   (import "env" "caml_callback_1"
      (func $caml_callback_1 (param (ref eq)) (param (ref eq)) (result (ref eq))))
   (import "env" "caml_is_custom" (func $caml_is_custom (param (ref eq)) (result i32)))
   (import "env" "caml_custom_identifier"
      (func $caml_custom_identifier (param (ref eq)) (result (ref eq))))
   (import "env" "Int64_val" (func $Int64_val (param (ref eq)) (result i64)))
   (import "env" "Int32_val" (func $Int32_val (param (ref eq)) (result i32)))
   (import "env" "caml_copy_int64"
      (func $caml_copy_int64 (param i64) (result (ref eq))))
   (import "env" "caml_copy_int32"
      (func $caml_copy_int32 (param i32) (result (ref eq))))
   (import "env" "caml_copy_nativeint"
      (func $caml_copy_nativeint (param i32) (result (ref eq))))

   (import "c" "memory" (memory $c 1))
   (import "c" "oe_stack_base" (func $oe_stack_base (result i32)))
   (import "c" "oe_handle_new" (func $oe_handle_new (param i32) (result i32)))
   (import "c" "oe_handle_get" (func $oe_handle_get (param i32) (result i32)))
   (import "c" "oe_alloc" (func $oe_alloc (param i32 i32) (result i32)))
   (import "c" "oe_set_field" (func $oe_set_field (param i32 i32 i32)))
   (import "c" "oe_alloc_string" (func $oe_alloc_string (param i32) (result i32)))
   (import "c" "oe_alloc_double" (func $oe_alloc_double (param f64) (result i32)))
   (import "c" "oe_copy_int64" (func $oe_copy_int64 (param i64) (result i32)))
   (import "c" "oe_copy_int32" (func $oe_copy_int32 (param i32) (result i32)))
   (import "c" "oe_copy_nativeint" (func $oe_copy_nativeint (param i32) (result i32)))
   (import "c" "oe_custom_kind" (func $oe_custom_kind (param i32) (result i32)))
   (import "c" "oe_closure" (func $oe_closure (param i32) (result i32)))
   (import "c" "oe_closure_handle" (func $oe_closure_handle (param i32) (result i32)))
   (import "c" "oe_call" (func $oe_call (param i32 i32 i32) (result i32)))
   (import "c" "oe_compare" (func $oe_compare (param i32 i32) (result i32)))
   (import "c" "oe_hash" (func $oe_hash (param i32) (result i32)))
   (import "c" "oe_custom_finalized" (func $oe_custom_finalized (param i32) (result i32)))
   (import "c" "oe_predef_exn" (func $oe_predef_exn (param i32) (result i32)))
   ;; JS: keeps the WAT callbacks for C, frees handles of dead wrappers
   (import "c" "oe_register_wat" (func $oe_register_wat (param funcref funcref)))
   (import "c" "oe_track" (func $oe_track (param (ref eq)) (param i32)))

   (type $block (array (mut (ref eq))))
   (type $bytes (array (mut i8)))
   (type $float (struct (field f64)))
   (type $float_array (array (mut f64)))
   (type $function_1 (func (param (ref eq) (ref eq)) (result (ref eq))))
   (type $closure (sub (struct (field (ref $function_1)))))
   (type $compare
      (func (param (ref eq)) (param (ref eq)) (param i32) (result i32)))
   (type $hash (func (param (ref eq)) (result i32)))
   (type $fixed_length (struct (field $bsize_32 i32) (field $bsize_64 i32)))
   (type $serialize
      (func (param (ref eq)) (param (ref eq)) (result i32) (result i32)))
   (type $deserialize (func (param (ref eq)) (result (ref eq)) (result i32)))
   (type $dup (func (param (ref eq)) (result (ref eq))))
   (type $custom_operations
      (struct
         (field $id (ref $bytes))
         (field $compare (ref null $compare))
         (field $compare_ext (ref null $compare))
         (field $hash (ref null $hash))
         (field $fixed_length (ref null $fixed_length))
         (field $serialize (ref null $serialize))
         (field $deserialize (ref null $deserialize))
         (field $dup (ref null $dup))))
   (type $custom (sub (struct (field (ref $custom_operations)))))
   ;; a C value (custom or abstract block, foreign closure) held by a handle
   (type $cvalue
      (sub final $custom (struct (field (ref $custom_operations)) (field i32))))

   ;; a copy of a custom block without finalizer (zarith's big integers):
   ;; its words, including its custom operations' address
   (type $words (array (mut i32)))
   (type $ccopy
      (sub final $custom (struct (field (ref $custom_operations)) (field (ref $words)))))

   (func $ccopy_compare
      (param $a (ref eq)) (param $b (ref eq)) (param i32) (result i32)
      (local $x i32)
      ;; not interleaved: the first copy is rooted in a stack slot
      (local.set $x (call $to_c (local.get $a)))
      (i32.store $c (call $slot (global.get $sp)) (local.get $x))
      (global.set $sp (i32.add (global.get $sp) (i32.const 1)))
      (local.set $x (call $oe_compare
         (i32.load $c (call $slot (i32.sub (global.get $sp) (i32.const 1))))
         (call $to_c (local.get $b))))
      (global.set $sp (i32.sub (global.get $sp) (i32.const 1)))
      (local.get $x))

   (func $ccopy_hash (param $a (ref eq)) (result i32)
      (call $oe_hash (call $to_c (local.get $a))))

   (global $ccopy_ops (ref $custom_operations)
      (struct.new $custom_operations
         (array.new_fixed $bytes 3 (i32.const 95) (i32.const 111) (i32.const 99)) ;; "_oc"
         (ref.func $ccopy_compare)
         (ref.null $compare)
         (ref.func $ccopy_hash)
         (ref.null $fixed_length)
         (ref.null $serialize)
         (ref.null $deserialize)
         (ref.null $dup)))

   (func $cvalue_compare
      (param $a (ref eq)) (param $b (ref eq)) (param i32) (result i32)
      (call $oe_compare
         (call $oe_handle_get
            (struct.get $cvalue 1 (ref.cast (ref $cvalue) (local.get $a))))
         (call $oe_handle_get
            (struct.get $cvalue 1 (ref.cast (ref $cvalue) (local.get $b))))))

   (func $cvalue_hash (param $a (ref eq)) (result i32)
      (call $oe_hash
         (call $oe_handle_get
            (struct.get $cvalue 1 (ref.cast (ref $cvalue) (local.get $a))))))

   (global $cvalue_ops (ref $custom_operations)
      (struct.new $custom_operations
         (array.new_fixed $bytes 3 (i32.const 95) (i32.const 111) (i32.const 101)) ;; "_oe"
         (ref.func $cvalue_compare)
         (ref.null $compare)
         (ref.func $cvalue_hash)
         (ref.null $fixed_length)
         (ref.null $serialize)
         (ref.null $deserialize)
         (ref.null $dup)))

   ;; GC closures given to C, by handle
   (global $closures (mut (ref $block)) (array.new_fixed $block 0))
   (global $nclosures (mut i32) (i32.const 0))

   ;; exception constructors (and other Object_tag blocks) known on both
   ;; sides: GC value and handle of the C value
   (global $pairs_gc (mut (ref $block)) (array.new_fixed $block 0))
   (global $pairs_c (mut (ref $block)) (array.new_fixed $block 0))
   (global $npairs (mut i32) (i32.const 0))

   ;; top of the C root stack, in slots
   (global $sp (mut i32) (i32.const 0))
   (global $stack (mut i32) (i32.const 0))
   (global $initialized (mut i32) (i32.const 0))

   (func $grow (param $a (ref $block)) (param $n i32) (result (ref $block))
      (local $b (ref $block))
      (if (i32.lt_u (local.get $n) (array.len (local.get $a)))
         (then (return (local.get $a))))
      (local.set $b
         (array.new $block (ref.i31 (i32.const 0))
            (i32.add (i32.mul (local.get $n) (i32.const 2)) (i32.const 8))))
      (array.copy $block $block (local.get $b) (i32.const 0)
         (local.get $a) (i32.const 0) (array.len (local.get $a)))
      (local.get $b))

   (func $add_pair (param $gc (ref eq)) (param $cv i32)
      (global.set $pairs_gc (call $grow (global.get $pairs_gc) (global.get $npairs)))
      (global.set $pairs_c (call $grow (global.get $pairs_c) (global.get $npairs)))
      (array.set $block (global.get $pairs_gc) (global.get $npairs) (local.get $gc))
      (array.set $block (global.get $pairs_c) (global.get $npairs)
         (ref.i31 (call $oe_handle_new (local.get $cv))))
      (global.set $npairs (i32.add (global.get $npairs) (i32.const 1))))

   (func $init
      (local $i i32)
      (global.set $initialized (i32.const 1))
      (global.set $stack (call $oe_stack_base))

      (call $oe_register_wat (ref.func $oe_wat_apply) (ref.func $oe_wat_named_value))
      ;; the predefined exceptions
      (loop $l
         (call $add_pair
            (array.get $block
               (ref.cast (ref $block)
                  (call $caml_get_global_data (ref.i31 (i32.const 0))))
               (i32.add (local.get $i) (i32.const 1)))
            (call $oe_predef_exn (local.get $i)))
         (local.set $i (i32.add (local.get $i) (i32.const 1)))
         (br_if $l (i32.lt_u (local.get $i) (i32.const 12)))))

   ;; ---- GC -> C -------------------------------------------------------

   (func $to_c (param $v (ref eq)) (result i32)
      (local $b (ref $block)) (local $s (ref $bytes)) (local $fa (ref $float_array))
      (local $r i32) (local $i i32) (local $n i32) (local $tag i32)
      (local $w (ref $words))
      (if (ref.test (ref i31) (local.get $v))
         (then
            (return (i32.or (i32.shl (i31.get_s (ref.cast (ref i31) (local.get $v)))
                                     (i32.const 1))
                            (i32.const 1)))))
      (if (ref.test (ref $bytes) (local.get $v))
         (then
            (local.set $s (ref.cast (ref $bytes) (local.get $v)))
            (local.set $n (array.len (local.get $s)))
            (local.set $r (call $oe_alloc_string (local.get $n)))
            (local.set $i (i32.const 0))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (i32.store8 $c (i32.add (local.get $r) (local.get $i))
                     (array.get_u $bytes (local.get $s) (local.get $i)))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (local.get $r))))
      (if (ref.test (ref $float) (local.get $v))
         (then
            (return (call $oe_alloc_double
               (struct.get $float 0 (ref.cast (ref $float) (local.get $v)))))))
      (if (ref.test (ref $float_array) (local.get $v))
         (then
            (local.set $fa (ref.cast (ref $float_array) (local.get $v)))
            (local.set $n (array.len (local.get $fa)))
            (local.set $r (call $oe_alloc (i32.const 254)
                             (i32.mul (local.get $n) (i32.const 2))))
            (local.set $i (i32.const 0))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (f64.store $c
                     (i32.add (local.get $r) (i32.shl (local.get $i) (i32.const 3)))
                     (array.get $float_array (local.get $fa) (local.get $i)))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (local.get $r))))
      (if (ref.test (ref $block) (local.get $v))
         (then
            (local.set $b (ref.cast (ref $block) (local.get $v)))
            (local.set $tag
               (i31.get_u (ref.cast (ref i31) (array.get $block (local.get $b) (i32.const 0)))))
            (if (i32.eq (local.get $tag) (i32.const 248))
               (then
                  ;; an exception constructor: the C value paired with it
                  (local.set $i (i32.const 0))
                  (block $new
                     (loop $l
                        (br_if $new (i32.ge_u (local.get $i) (global.get $npairs)))
                        (if (ref.eq (array.get $block (global.get $pairs_gc) (local.get $i))
                                    (local.get $v))
                           (then
                              (return (call $oe_handle_get
                                 (i31.get_u (ref.cast (ref i31)
                                    (array.get $block (global.get $pairs_c) (local.get $i))))))))
                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                        (br $l)))))
            (local.set $n (i32.sub (array.len (local.get $b)) (i32.const 1)))
            (local.set $r (call $oe_alloc (local.get $tag) (local.get $n)))
            (local.set $i (i32.const 0))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (call $oe_set_field (local.get $r) (local.get $i)
                     (call $to_c (array.get $block (local.get $b)
                                    (i32.add (local.get $i) (i32.const 1)))))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (if (i32.eq (local.get $tag) (i32.const 248))
               (then (call $add_pair (local.get $v) (local.get $r))))
            (return (local.get $r))))
      (if (ref.test (ref $ccopy) (local.get $v))
         (then
            (local.set $w (struct.get $ccopy 1 (ref.cast (ref $ccopy) (local.get $v))))
            (local.set $n (array.len (local.get $w)))
            (local.set $r (call $oe_alloc (i32.const 255) (local.get $n)))
            (local.set $i (i32.const 0))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (i32.store $c (i32.add (local.get $r) (i32.shl (local.get $i) (i32.const 2)))
                     (array.get $words (local.get $w) (local.get $i)))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (local.get $r))))
      (if (ref.test (ref $cvalue) (local.get $v))
         (then
            (return (call $oe_handle_get
               (struct.get $cvalue 1 (ref.cast (ref $cvalue) (local.get $v)))))))
      (if (call $caml_is_custom (local.get $v))
         (then
            ;; "_j", "_i" or "_n"
            (local.set $s (ref.cast (ref $bytes)
                             (call $caml_custom_identifier (local.get $v))))
            (if (i32.eq (array.len (local.get $s)) (i32.const 2))
               (then
                  (local.set $n (array.get_u $bytes (local.get $s) (i32.const 1)))
                  (if (i32.eq (local.get $n) (i32.const 106))
                     (then (return (call $oe_copy_int64 (call $Int64_val (local.get $v))))))
                  (if (i32.eq (local.get $n) (i32.const 105))
                     (then (return (call $oe_copy_int32 (call $Int32_val (local.get $v))))))
                  (if (i32.eq (local.get $n) (i32.const 110))
                     (then (return (call $oe_copy_nativeint (call $Int32_val (local.get $v))))))))))
      (if (ref.test (ref $closure) (local.get $v))
         (then
            (global.set $closures
               (call $grow (global.get $closures) (global.get $nclosures)))
            (array.set $block (global.get $closures) (global.get $nclosures)
               (local.get $v))
            (global.set $nclosures (i32.add (global.get $nclosures) (i32.const 1)))
            (return (call $oe_closure
               (i32.sub (global.get $nclosures) (i32.const 1))))))
      (call $caml_failwith (global.get $unsupported))
      (unreachable))

   (@string $unsupported "bridge: a value of this kind cannot go to C")

   ;; ---- C -> GC -------------------------------------------------------

   (func $of_c (param $v i32) (result (ref eq))
      (local $hd i32) (local $tag i32) (local $n i32) (local $i i32)
      (local $s (ref $bytes)) (local $fa (ref $float_array)) (local $b (ref $block))
      (local $k i32) (local $w (ref $words))
      (if (i32.and (local.get $v) (i32.const 1))
         (then (return (ref.i31 (i32.shr_s (local.get $v) (i32.const 1))))))
      (local.set $hd (i32.load $c (i32.sub (local.get $v) (i32.const 4))))
      (local.set $tag (i32.and (local.get $hd) (i32.const 0xff)))
      (local.set $n (i32.shr_u (local.get $hd) (i32.const 10)))
      (if (i32.eq (local.get $tag) (i32.const 252)) ;; String_tag
         (then
            (local.set $n
               (i32.sub (i32.sub (i32.shl (local.get $n) (i32.const 2)) (i32.const 1))
                  (i32.load8_u $c
                     (i32.sub (i32.add (local.get $v) (i32.shl (local.get $n) (i32.const 2)))
                              (i32.const 1)))))
            (local.set $s (array.new $bytes (i32.const 0) (local.get $n)))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (array.set $bytes (local.get $s) (local.get $i)
                     (i32.load8_u $c (i32.add (local.get $v) (local.get $i))))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (local.get $s))))
      (if (i32.eq (local.get $tag) (i32.const 253)) ;; Double_tag
         (then (return (struct.new $float (f64.load $c (local.get $v))))))
      (if (i32.eq (local.get $tag) (i32.const 254)) ;; Double_array_tag
         (then
            (local.set $n (i32.shr_u (local.get $n) (i32.const 1)))
            (local.set $fa (array.new $float_array (f64.const 0) (local.get $n)))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (array.set $float_array (local.get $fa) (local.get $i)
                     (f64.load $c (i32.add (local.get $v) (i32.shl (local.get $i) (i32.const 3)))))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (local.get $fa))))
      (if (i32.eq (local.get $tag) (i32.const 255)) ;; Custom_tag
         (then
            (local.set $k (call $oe_custom_kind (local.get $v)))
            (if (i32.eq (local.get $k) (i32.const 1))
               (then (return (call $caml_copy_int64
                                (i64.load $c (i32.add (local.get $v) (i32.const 4)))))))
            (if (i32.eq (local.get $k) (i32.const 2))
               (then (return (call $caml_copy_int32
                                (i32.load $c (i32.add (local.get $v) (i32.const 4)))))))
            (if (i32.eq (local.get $k) (i32.const 3))
               (then (return (call $caml_copy_nativeint
                                (i32.load $c (i32.add (local.get $v) (i32.const 4)))))))
            (if (call $oe_custom_finalized (local.get $v))
               (then (return (call $wrap (local.get $v)))))
            (local.set $w (array.new $words (i32.const 0) (local.get $n)))
            (block $done
               (loop $l
                  (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                  (array.set $words (local.get $w) (local.get $i)
                     (i32.load $c (i32.add (local.get $v) (i32.shl (local.get $i) (i32.const 2)))))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (return (struct.new $ccopy (global.get $ccopy_ops) (local.get $w)))))
      (if (i32.eq (local.get $tag) (i32.const 247)) ;; Closure_tag
         (then
            (local.set $k (call $oe_closure_handle (local.get $v)))
            (if (i32.ge_s (local.get $k) (i32.const 0))
               (then (return (array.get $block (global.get $closures) (local.get $k)))))
            (return (call $wrap (local.get $v)))))
      (if (i32.eq (local.get $tag) (i32.const 251)) ;; Abstract_tag
         (then (return (call $wrap (local.get $v)))))
      (if (i32.eq (local.get $tag) (i32.const 248)) ;; Object_tag
         (then
            (block $new
               (loop $l
                  (br_if $new (i32.ge_u (local.get $i) (global.get $npairs)))
                  (if (i32.eq (call $oe_handle_get
                                 (i31.get_u (ref.cast (ref i31)
                                    (array.get $block (global.get $pairs_c) (local.get $i)))))
                              (local.get $v))
                     (then (return (array.get $block (global.get $pairs_gc) (local.get $i)))))
                  (local.set $i (i32.add (local.get $i) (i32.const 1)))
                  (br $l)))
            (local.set $i (i32.const 0))))
      ;; a structured block
      (local.set $b (array.new $block (ref.i31 (local.get $tag))
                       (i32.add (local.get $n) (i32.const 1))))
      (block $done
         (loop $l
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (array.set $block (local.get $b) (i32.add (local.get $i) (i32.const 1))
               (call $of_c (i32.load $c (i32.add (local.get $v)
                                           (i32.shl (local.get $i) (i32.const 2))))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
      (if (i32.eq (local.get $tag) (i32.const 248))
         (then (call $add_pair (local.get $b) (local.get $v))))
      (local.get $b))

   (func $wrap (param $v i32) (result (ref eq))
      (local $h i32) (local $w (ref eq))
      (local.set $h (call $oe_handle_new (local.get $v)))
      (local.set $w (struct.new $cvalue (global.get $cvalue_ops) (local.get $h)))
      (call $oe_track (local.get $w) (local.get $h))
      (local.get $w))

   ;; ---- calls -------------------------------------------------------

   (func $slot (param $i i32) (result i32)
      (i32.add (global.get $stack) (i32.shl (local.get $i) (i32.const 2))))

   (func $invoke (export "oe_invoke")
      (param $prim i32) (param $args (ref $block)) (result (ref eq))
      (local $base i32) (local $n i32) (local $i i32) (local $raised i32)
      (local $res (ref eq)) (local $a (ref eq)) (local $cv i32) (local $len i32)
      (local $s (ref $bytes)) (local $j i32)
      (if (i32.eqz (global.get $initialized)) (then (call $init)))
      (local.set $base (global.get $sp))
      (local.set $n (array.len (local.get $args)))
      (global.set $sp (i32.add (local.get $base) (i32.add (local.get $n) (i32.const 1))))
      (block $done
         (loop $l
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (i32.store $c (call $slot (i32.add (local.get $base) (local.get $i)))
               (call $to_c (array.get $block (local.get $args) (local.get $i))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
      (local.set $raised
         (call $oe_call (local.get $prim) (local.get $base) (local.get $n)))
      ;; mutable arguments: bytes are copied back
      (local.set $i (i32.const 0))
      (block $done
         (loop $l
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (local.set $a (array.get $block (local.get $args) (local.get $i)))
            (if (ref.test (ref $bytes) (local.get $a))
               (then
                  (local.set $s (ref.cast (ref $bytes) (local.get $a)))
                  (local.set $cv (i32.load $c (call $slot (i32.add (local.get $base) (local.get $i)))))
                  (local.set $j (i32.const 0))
                  (local.set $len (array.len (local.get $s)))
                  (block $d2
                     (loop $l2
                        (br_if $d2 (i32.ge_u (local.get $j) (local.get $len)))
                        (array.set $bytes (local.get $s) (local.get $j)
                           (i32.load8_u $c (i32.add (local.get $cv) (local.get $j))))
                        (local.set $j (i32.add (local.get $j) (i32.const 1)))
                        (br $l2)))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
      (local.set $res
         (call $of_c (i32.load $c (call $slot (i32.add (local.get $base) (local.get $n))))))
      ;; clear the slots: their values may die
      (local.set $i (i32.const 0))
      (block $done
         (loop $l
            (br_if $done (i32.gt_u (local.get $i) (local.get $n)))
            (i32.store $c (call $slot (i32.add (local.get $base) (local.get $i))) (i32.const 1))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
      (global.set $sp (local.get $base))
      (if (local.get $raised) (then (throw $ocaml_exception (local.get $res))))
      (local.get $res))

   ;; called by C (through JS) to apply a GC closure: the result, or the
   ;; exception with *raised set
   (func $oe_wat_apply (param $h i32) (param $arg i32) (param $raised i32) (result i32)
      (local $r (ref eq)) (local $exn (ref eq))
      (try (result (ref eq))
         (do
            (call $caml_callback_1
               (array.get $block (global.get $closures) (local.get $h))
               (call $of_c (local.get $arg))))
         (catch $ocaml_exception
            (local.set $exn)
            (i32.store $c (local.get $raised) (i32.const 1))
            (local.get $exn)))
      (local.set $r)
      (call $to_c (local.get $r)))

   ;; called by C (through JS): the value registered under this name by
   ;; Callback.register, 0 if none
   (func $oe_wat_named_value (param $name i32) (param $len i32) (result i32)
      (local $s (ref $bytes)) (local $i i32) (local $v (ref null eq))
      (local.set $s (array.new $bytes (i32.const 0) (local.get $len)))
      (block $done
         (loop $l
            (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
            (array.set $bytes (local.get $s) (local.get $i)
               (i32.load8_u $c (i32.add (local.get $name) (local.get $i))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $l)))
      (local.set $v (call $caml_named_value (local.get $s)))
      (if (ref.is_null (local.get $v)) (then (return (i32.const 0))))
      (call $to_c (ref.as_non_null (local.get $v))))
)
