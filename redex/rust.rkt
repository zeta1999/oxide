#lang racket/base

(require redex
         redex-chk)

(define-language Rust
  ;; programs
  (prog ::= (tls ...))

  ;; top-level statements
  (tls ::=
       (struct sid [(lt ι) ... α ...] {(x t) ...})
       (enum sid [(lt ι) ... α ...] {(vid t ...) ...})
       (fn f [(lt ι) ... α ...] ((x t) ...) { st ... }))

  ;; statements
  (st ::=
      ;; let bindings (immutable and mutable)
      (let lv = rv)
      (let mut lv = rv)
      ;; assignment (only for mutable bindings)
      (lv = rv)

      ;; expressions (rvalues)
      rv)

  ;; lvalues (expressions that can appear on the left-side of a binding or assignment)
  (lv ::=
      ;; variable
      x
      ;; pointer dereference
      (* lv)
      ;; lvalue products
      (tup lv ...))

  ;; rvalues (expressions)
  (rv ::=
      ;; all lvalues
      lv
      ;; branching
      (if rv rv rv)
      ;; rvalue products
      (tup rv ...)

      ;; function calls
      (f [(lt ι) ... t ...] (rv ...))
      ;; blocks (sequence of statements, takes value of last statement)
      (block st ...)
      ;; pattern matching
      (match rv {(pat => rv) ...})

      ;; base values
      number
      true
      false

      ;; abort (errors) -- in real Rust, there's multiple options here with messages, etc.
      (abort!)

      ;; operations
      (rv binop rv)
      (unop rv))

  ;; patterns
  (pat ::=
       ;; enum variant application
       (sid x ...))

  ;; operators
  (binop ::= + = ∧ ∨)
  (unop ::= - ¬)

  ;; type parameters
  (typaram ::=
           α
           (lt ι))

  ;; types
  (t ::=
     ;; type variables
     α
     ;; references (&'a t)
     (ref ι t)

     ;; struct and enum names
     sid
     ;; type application
     (t t)

     ;; base types
     num
     bool)

  ;; variables
  (x ::= variable-not-otherwise-mentioned)
  ;; type variables
  (α ::= variable-not-otherwise-mentioned)
  ;; lifetime variables
  (ι ::= variable-not-otherwise-mentioned)
  ;; function identifiers
  (f ::= variable-not-otherwise-mentioned)
  ;; struct and enum identifiers
  (sid ::= variable-not-otherwise-mentioned)
  ;; enum variant identifiers
  (vid ::= variable-not-otherwise-mentioned))

;; syntax tests
(redex-chk
 #:lang Rust

 ;; valid programs
 #:m prog ((enum Option [T] { (None) (Some T) })
           (fn unwrap [T] ((opt (Option T))) { (match opt { ((None) => (abort!))
                                                            ((Some x) => x) }) }))

 ;; valid top-level statements
 #:m tls (struct Point [] { (x num)
                            (y num) })
 #:m tls (struct Ref [(lt α) T] { (inner (ref α T)) })
 #:m tls (enum Option [T] { (None)
                            (Some T) })
 #:m tls (enum WeirdOption [T] { (None)
                                 (Some T)
                                 (Double T T) })
 #:m tls (fn main [] () { (let (tup x y) = (tup 1 2)) })
 #:m tls (fn sum_to [] ((x num)) { (if (x = 0)
                                       1
                                       (x + (sum_to [] ((x + -1))))) })

 ;; invalid top-level statements
 #:f #:m tls (fn main [] () { (let (tup 1 2) = (tup 3 4)) }))