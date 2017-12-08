#lang racket/base

(require redex
         redex-chk
         racket/list)

(define-language Rust0
  ;; programs
  (prog ::= (tls ...))

  ;; top-level statements
  (tls ::=
       (struct sid [(lft ι) ... T ...] {(x t) ...})
       (enum sid [(lft ι) ... T ...] {dt ...})
       (fn f [(lft ι) ... T ...] ((x t) ...) { st ... }))

  ;; statements
  (st ::=
      ;; let bindings (immutable and mutable)
      (let (pat t) = e)
      (let mut (pat t) = e)
      ;; assignment (only for mutable bindings)
      (lv := e)

      ;; expressions
      e)

  ;; lvalues - expressions that can appear on the left-side of an assignment
  (lv ::=
      ;; variable
      x
      ;; pointer dereference
      (deref lv)
      ;; projecting a field from a struct variable
      (proj x x)
      ;; lvalue products
      (tup lv ...))

  ;; data structures - struct and variant kinds
  (d ::=
     ;; named tuple - a kind of struct and enum variant
     (sid e ...)
     ;; named record - a kind of struct and enum variant
     (sid {(x e) ...}))

  ;; data structure typeforms - struct and variant kinds with types
  ;; n.b. these are not an actual kind of type, but are used in definitions
  (dt ::=
      (sid t ...)
      (sid {(x t) ...}))

  ;; expressions
  (e ::=
     ;; variables
     x
     ;; branching
     (if e e e)
     ;; tuples
     (tup e ...)
     ;; data structures
     d
     ;; project the first arg from the second arg
     (proj e e)

     ;; function calls
     (f [(lft ι) ... t ...] (e ...))
     ;; blocks - sequence of statements, takes value of last expression or unit if statement
     (block st ...)
     ;; pattern matching
     (match e {(pat => e) ...})

     ;; base values
     const
     ;; references
     (ref ι e)

     ;; abort (errors) -- in real Rust, there's multiple options here with messages, etc.
     (abort!)

     ;; operations
     (e binop e)
     (unop e))

  ;; constants
  (const ::=
         number
         true
         false)

  ;; patterns
  (pat ::=
       ;; wildcard pattern
       underscore
       ;; variable pattern
       x
       ;; tuple pattern
       (tup pat ...)
       ;; named tuple pattern
       (sid pat ...)
       ;; named record pattern
       (sid {(x pat) ...})
       ;; reference pattern
       (ref pat))

  ;; operators
  (binop ::= + = ∧ ∨)
  (unop ::= deref - ¬)

  ;; types
  (t ::=
     ;; type variables
     T
     ;; references (&'a t)
     (ref ι t)
     ;; tuple types
     (tup t ...)

     ;; struct and enum names
     sid
     ;; type application e.g. (Option [num])
     (t [t])

     ;; function types - universally quantified, multi-argument functions
     (fn [ι ... T ...] (t ...) -> t)

     ;; base types
     num
     bool)

  ;; shorthand for numbers
  (n ::= number)

  ;; variables
  (x ::= variable-not-otherwise-mentioned)
  ;; type variables
  (T ::= variable-not-otherwise-mentioned)
  ;; lifetime variables
  (ι ::= variable-not-otherwise-mentioned)
  ;; function identifiers
  (f ::= variable-not-otherwise-mentioned)
  ;; struct and enum identifiers
  (sid ::= variable-not-otherwise-mentioned))

;; syntax tests
(redex-chk
 #:lang Rust0

 ;; valid programs
 #:m prog ((enum Option [T] { (None) (Some T) })
           (fn unwrap [T] ((opt (Option [T]))) { (match opt { ((Option::None) => (abort!))
                                                            ((Option::Some x) => x) }) }))
 #:m prog ((fn main [] () { (tup) }))
 #:m prog ((fn main [] () { 7 }))

 ;; valid top-level statements
 #:m tls (struct Point [] { (x num)
                            (y num) })
 #:m tls (struct Ref [(lft α) T] { (inner (ref α T)) })
 #:m tls (enum Option [T] { (None)
                            (Some T) })
 #:m tls (enum WeirdOption [T] { (None)
                                 (Some T)
                                 (Double T T) })
 #:m tls (fn main [] () { (tup) (tup) (tup) })
 #:m tls (fn main [] () { (let [(tup x y) (tup num num)] = (tup 1 2)) })
 #:m tls (fn sum_to [] ((x num)) { (if (x = 0)
                                       1
                                       (x + (sum_to [] ((x + -1))))) })

 ;; invalid top-level statements
 #:f #:m tls (fn main [] () { (let [(tup 1 2) (tup num num)] = (tup 3 4)) }))

(define-extended-language Rust0-Machine Rust0
  ;; flags indicating immutable or mutable
  (flag ::=
     imm
     mut)

  ;; addresses
  (α ::= variable-not-otherwise-mentioned)

  ;; variable environment - maps identifiers to addresses
  (ρ ::= (env (flag x α) ...))
  ;; memory - maps addresses to values
  (ψ ::= (mem (α v) ...))

  ;; values
  (v ::=
     ;; constants
     const
     ;; pointers to α (a live reference)
     (ptr α)
     ;; allocated tuple (tuple with addresses)
     (tup α ...)
     ;; allocated named-tuple
     (sid α ...)
     ;; allocated named-record
     (sid {(x α) ...}))

  ;; control strings
  (c ::=
     ;; empty
     ·
     ;; statement
     st)

  ;; control values - flattened values (i.e. with no indirection via pointers) and abort! and ·
  (cv ::=
      ·
      (abort!)
      (ptr α)
      const
      (tup cv ...)
      (vid cv ...)
      (sid {(x cv) ...}))

  ;; continuations
  (κ ::=
     ;; halt
     halt
     ;; special start continuation indicating main should be called
     start
     ;; function call continuation - the hole in st should be bound to x
     (fun x st ρ κ)
     ;; continuation representing a block of statements to execute before continuing to κ
     (block st ... κ))

  ;; evaluation contexts
  (E ::=
     ;; top-level evaluation context, format: c ρ ψ κ prog
     (E ρ ψ κ prog)

     ;; hole
     hole

     ;; statements
     (let (pat t) = E)
     (let mut (pat t) = E)
     (lv := E)

     ;; data structures (enum variants and structs)
     (sid v ... E e ...)
     (sid {(x v) ... (x E) (x e) ...})

     ;; function calls
     (f [(lft ι) ... t ...] (v ... E e ...))
     ;; pattern matching
     (match E {(pat => e) ...})

     ;; branching
     (if E e e)

     ;; products
     (tup v ... E e ...)
     ;; product projection
     (proj E e)
     (proj v E)

     ;; primitive ops
     (v + E)
     (E + e)
     (v = E)
     (E = e)
     (- E)
     (v ∧ E)
     (E ∧ e)
     (v ∨ E)
     (E ∨ e)
     (¬ E)
     (deref E)))


(define -->Rust0
  (reduction-relation
   Rust0-Machine

   (--> (· ρ ψ start prog)
        (st_0 ρ ψ (block st_1 ... halt) prog)
        (where (fn main [] () { st_0 st_1 ... }) (lookup-fn prog main))
        "E-StartMain")
   (--> (cv ρ ψ halt prog)
        cv
        "E-HaltProgram")

   (--> ((block st ...) ρ ψ κ prog)
        (· ρ ψ (block st ... κ) prog)
        "E-StartBlock")
   (--> (cv ρ ψ (block st_0 st_1 ... κ) prog)
        (st_0 ρ ψ (block st_1 ... κ) prog)
        "E-AdvanceBlock")
   (--> (cv ρ ψ (block κ) prog)
        (cv ρ ψ κ prog)
        "E-EndBlock")

   (--> ((in-hole E (tup cv_n ...))
         (env (flag x α) ...)
         (mem (α_m v_m) ...)
         κ prog)
        ((in-hole E (tup α_n ...))
         (env (flag x α) ...)
         (mem (α_n cv_n) ... (α_m v_m) ...)
         κ prog)
        ;; allocate if it's not a bare expression
        (side-condition (or (not (eq? (term E) (term hole)))
                            ;; or if it is a bare expression and we're returning from a function
                            (and (pair? (term κ))
                                 (eq? (car (term κ)) (term fun)))))
        (where (α_n ...) ,(variables-not-in (term (x ... α ... α_m ... v_m ...))
                                            (map (lambda (x) (gensym)) (term (cv_n ...)))))
        "E-AllocTup")
   (--> ((tup α_t ...) ρ ψ κ prog)
        ;; TODO: actually remove every α_t from ψ
        ((tup (lookup-addr ψ α_t) ...) ρ ψ κ prog)
        ;; dealloc only when we're not returning from a function
        (side-condition (or (not (pair? (term κ)))
                            (not (eq? (car (term κ)) (term fun)))))
        "E-DeallocTup")

   (--> ((let (pat t) = v)
         (env (flag x_e α_e) ...)
         (name ψ (mem (α_m v_m) ...))
         κ prog)
        ((tup)
         (env (imm x_n α_n) ... (flag x_e α_e) ...)
         (mem (α_n v_n) ... (α_m v_m) ...)
         κ prog)
        (where ((x_n v_n) ...) (match-pat-or-err pat v ψ))
        (where (α_n ...) ,(variables-not-in (term (x_e ... x_n ... α_e ... α_m ...))
                                            (term (x_n ...))))
        "E-ImmBinding")
   (--> ((let mut (pat t) = v)
         (env (flag x_e α_e) ...)
         (name ψ (mem (α_m v_m) ...))
         κ prog)
        ((tup)
         (env (mut x_n α_n) ... (flag x_e α_e) ...)
         (mem (α_n v_n) ... (α_m v_m) ...)
         κ prog)
        (where ((x_n v_n) ...) (match-pat-or-err pat v ψ))
        (where (α_n ...) ,(variables-not-in (term (x_e ... x_n ... α_e ... α_m ...))
                                            (term (x_n ...))))
        "E-MutBinding")

   (--> ((in-hole E x)
         (env (flag_1 x_1 α_1) ... (flag x α) (flag_2 x_2 α_2) ...)
         (mem (α_3 v_3) ... (α v) (α_4 v_4) ...)
         κ prog)
        ((in-hole E v)
         (env (flag_1 x_1 α_1) ... (flag x α) (flag_2 x_2 α_2) ...)
         (mem (α_3 v_3) ... (α v) (α_4 v_4) ...)
         κ prog)
        "E-Id")

   (--> ((in-hole E (f [any ...] (v ...))) ρ
         (name ψ (mem (α_m v_m) ...))
         κ prog)
        (st_0
         (env (imm x α) ...)
         (mem (α v) ... (α_m v_m) ...)
         (block st_1 ... (fun x_f (in-hole E x_f) ρ κ)) prog)
        (where (fn f [(lft ι) ... T ...] ((x t) ...) { st_0 st_1 ... })
               (lookup-fn prog f))
        (where (α ...) ,(variables-not-in (term (x_f x ... v ... α_m ... v_m ...))
                                          (term (x ...))))
        (fresh x_f)
        "E-App")
   ;; TODO: return should de-allocate memory that is no longer accessible (equivalent of calling drop)
   (--> (v_1 _ (mem (α_m v_m) ...) (fun x_1 st (env (flag_2 x_2 α_2) ...) κ) prog)
        (st (env (imm x_1 α_1) (flag_2 x_2 α_2) ...) (mem (α_1 v_1) (α_m v_m) ...) κ prog)
        (fresh α_1)
        "E-Return")
   ))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Helper functions for metafunctions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (group n lst)
  (if (empty? lst)
      '()
      (cons (take lst n) (group n (drop lst n)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Rust0-Machine metafunctions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-metafunction Rust0-Machine
  lookup-fn : prog f -> tls
  [(lookup-fn (_ ... (fn f_0 [(lft ι) ... T ...] ((x t) ...) { st ... }) _ ...) f_0)
   (fn f_0 [(lft ι) ... T ...] ((x t) ...) { st ... })]
  [(lookup-fn prog f) ,(error "lookup-fn: function with name not found:" (term f))])

(define-metafunction Rust0-Machine
  lookup-addr : ψ α -> v
  [(lookup-addr (mem (α_!_1 v_1) ... ((name α α_!_1) v_2) (α_!_1 v_3) ...) α) v_2]
  [(lookup-addr (name ψ (mem (α_!_1 v) ...)) (name α α_!_1))
   ,(error "failed to look up address " (term α) " in " (term ψ))])

(redex-chk
 (lookup-addr (mem (α1 3) (α2 5) (α3 6)) α2) 5
 (lookup-addr (mem (α1 3) (α2 5) (α3 6)) α1) 3
 (lookup-addr (mem (α1 3) (α2 5) (α3 6)) α3) 6)

(define-metafunction Rust0-Machine
  match-pat : pat any ψ -> any
  ;; matching against an address directly will dereference it
  [(match-pat x α ψ) ((x (lookup-addr ψ α)))]
  ;; trivial variable patterns produce a binding
  [(match-pat x v ψ) ((x v))]

  ;; tuple patterns recursively match against the components of the tuple
  [(match-pat (tup pat ...) (tup α ...) ψ)
   ,(group 2 (flatten (term ((match-pat pat (lookup-addr ψ α) ψ) ...))))]
  ;; matching a tuple against anything else will fail
  [(match-pat (tup pat ...) v ψ) (failed)]

  ;; named tuple patterns recursively match against the fields of the variant
  [(match-pat (sid pat ...) (sid α ...) ψ)
   ,(group 2 (flatten (term ((match-pat pat (lookup-addr ψ α) ψ) ...))))]
  ;; if there's a name mismatch, the named tuples don't match
  [(match-pat ((name expected sid_!_1) _ ...) ((name found sid_!_1) _ ...) ψ) (failed)]
  ;; matching an named tuple pattern with anything else will fail
  [(match-pat (sid pat ...) v ψ) (failed)]

  ;; wildcard pattern matches everything, but binds nothing
  [(match-pat underscore _ ψ) ()])

(redex-chk
 (match-pat x 5 (mem)) ((x 5))
 (match-pat x α (mem (α 7))) ((x 7))

 (match-pat (Foo x y)
            (Foo α1 α2)
            (mem (α2 5) (α1 17)))
 ((x 17) (y 5))

 (match-pat (Foo (Bar x) (Bar y) z)
            (Foo α1 α2 α3)
            (mem (α5 13) (α4 15) (α3 8) (α2 (Bar α4)) (α1 (Bar α5))))
 ((x 13) (y 15) (z 8)))

(define-metafunction Rust0-Machine
  match-pat-or-err : pat v ψ -> any
  [(match-pat-or-err pat v ψ) ,(let ([binds (term (match-pat pat v ψ))])
                                 (if (not (member (term failed) binds))
                                     binds
                                     (error "failed to match pattern " (term pat)
                                            " against " (term v))))])

(define-metafunction Rust0-Machine
  first-match : ψ v ((pat => e) ...) -> any
  [(first-match ψ v ((pat => e) (pat_2 => e_2) ...))
   ,(let ([binds (term (match-pat pat v ψ))])
      (if (not (member (term failed) binds))
          (cons (term e) binds)
          (term (first-match ψ v ((pat_2 => e_2) ...)))))]
  [(first-match ψ v ()) ,(error "failed to find match for value:" (term v))])

(redex-chk
 (first-match (mem) 3 (((Foo) => 1) (x => 2) (x => 4))) (2 (x 3))
 (first-match (mem (α2 2) (α1 1)) (Foo α1 α2) (((Foo x y) => (x + y)))) ((x + y) (x 1) (y 2)))

(define-metafunction Rust0-Machine
  eval : prog -> any
  [(eval prog) ,(car (apply-reduction-relation* -->Rust0 (term (· (env) (mem) start prog))))])

(redex-chk
 (eval ((fn main [] () { 7 }))) 7
 (eval ((fn main [] () { 3 2 }))) 2
 (eval ((fn main [] () { (block 4 5) }))) 5
 (eval ((fn main [] () { (tup 1 2) }))) (tup 1 2)
 (eval ((fn main [] () { (let (x (tup num num)) = (tup 5 9))
                         x }))) (tup 5 9)
 (eval ((fn main [] () { (id [] (5)) })
        (fn id [] ((x num)) { x }))) 5
 (eval ((fn main [] () { (id [] ((tup 7 4))) })
        (fn id [] ((x (tup num num))) { x }))) (tup 7 4))