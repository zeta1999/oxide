type var = int [@@deriving show]
type ty_var = int [@@deriving show]
type prov_var = int [@@deriving show]

type muta = Shared | Unique [@@deriving show]
type place =
  | Var of var
  | Deref of place
  | FieldProj of place * string
  | IndexProj of place * int
[@@deriving show]
type loan = muta * place [@@deriving show]
type loans = (muta * place) list [@@deriving show]
type prov =
  | ProvVar of prov_var
  | ProvSet of loans
[@@deriving show]

type kind = Star | Prov [@@deriving show]
type base_ty = Bool | U32 | Unit [@@deriving show]
type ty =
  | BaseTy of base_ty
  | TyVar of ty_var
  | Ref of prov * muta * ty
  | Fun of prov_var list * ty_var list * ty list * ty
  | Array of ty * int
  | Tup of ty list
[@@deriving show]

type prim =
  | Unit
  | Num of int
  | True
  | False
[@@deriving show]

type expr =
  | Prim of prim
  | Borrow of muta * place
  | BorrowIdx of muta * place * expr
  | BorrowSlice of muta * place * expr * expr
  | Let of var * ty * expr * expr
  | Assign of place * expr
  | Seq of expr * expr
  | Fun of prov_var list * ty_var list * (var * ty) list * expr
  | App of expr * prov list * ty list * expr list
  | Idx of place * expr
  | Abort of string
  | Branch of expr * expr * expr
  | For of var * expr * expr
  | Tup of expr list
  | Array of expr list
  | Ptr of muta * place
[@@deriving show]

type value =
  | Prim of prim
  | Fun of prov_var list * ty_var list * (var * ty) list * expr
  | Tup of value list
  | Array of value list
  | Ptr of muta * place
[@@deriving show]

type shape =
  | Hole
  | Prim of prim
  | Fun of prov_var list * ty_var list * (var * ty) list * expr
  | Tup of unit list
  | Array of value list
  | Ptr of muta * place
[@@deriving show]

type store = (place * shape) list [@@deriving show]

type global_env = unit (* TODO: actual global environment definition *)
type tyvar_env = prov_var list * ty_var list [@@deriving show]
type var_env = (var * ty) list [@@deriving show]

let var_env_lookup (gamma : var_env) (x : var) : ty = List.assoc x gamma
let var_env_include (gamma : var_env) (x : var) (typ : ty) = List.cons (x, typ) gamma
let var_env_exclude (gamma : var_env) (x : var) = List.remove_assoc x gamma

let is_empty (lst : 'a list) : bool = List.length lst = 0

(* checks that mu_prime is at least mu *)
let is_at_least (mu : muta) (mu_prime : muta) : bool =
  match (mu, mu_prime) with
  | (Shared, _) -> true
  | (Unique, Unique) -> true
  | (Unique, Shared) -> false

(* extract all the specific loans from a given region *)
let prov_to_loans (prov : prov) : loans =
  match prov with
  | ProvVar _ -> []
  | ProvSet lns -> lns

(* compute all the at-least-mu loans in a given gamma *)
let all_loans (mu : muta) (gamma : var_env) : loans =
  let rec work (typ : ty) (loans : loans) : loans =
    match typ with
    | BaseTy _ -> loans
    | TyVar _ -> loans
    | Ref (prov, mu_prime, typ) ->
      if is_at_least mu mu_prime then List.append (prov_to_loans prov) (work typ loans)
      else work typ loans
    | Fun (_, _, _, _) -> loans
    | Array (typ, _) -> work typ loans
    | Tup typs -> List.fold_right List.append (List.map (fun typ -> work typ []) typs) loans
  in List.fold_right (fun entry -> work (snd entry)) gamma []

(*  compute all subplaces from a given place *)
let all_subplaces (pi : place) : place list =
  let rec work (pi : place) (places : place list) : place list =
    match pi with
    | Var _ -> List.cons pi places
    | Deref pi_prime -> work pi_prime (List.cons pi places)
    | FieldProj (pi_prime, _) -> work pi_prime (List.cons pi places)
    | IndexProj (pi_prime, _) -> work pi_prime (List.cons pi places)
  in work pi []

(* find the root of a given place *)
let rec root_of (pi : place) : var =
  match pi with
  | Var root -> root
  | Deref pi_prime -> root_of pi_prime
  | FieldProj (pi_prime, _) -> root_of pi_prime
  | IndexProj (pi_prime, _) -> root_of pi_prime

(* find all at-least-mu loans in gamma that have to do with pi *)
let find_loans (mu : muta) (gamma : var_env) (pi : place) : loans =
  (* n.b. this is actually too permissive because of reborrowing and deref *)
  let root_of_pi = root_of pi
  in let relevant (pair : muta * place) : bool =
    (* a loan is relevant if it is a descendant of any subplace of pi *)
    let (_, pi_prime) = pair
       (* the easiest way to check is to check if their roots are the same *)
    in root_of_pi = root_of pi_prime
  in List.filter relevant (all_loans mu gamma)

(* given a gamma, determines whether it is safe to use pi according to mu *)
let is_safe (gamma : var_env) (mu : muta) (pi : place) : bool =
  let subplaces_of_pi = all_subplaces pi
  in let relevant (pair : muta * place) : bool =
    (* a loan is relevant if it is for either a subplace or an ancestor of pi *)
    let (_, pi_prime) = pair
        (* either pi is an ancestor of pi_prime *)
    in List.exists (fun x -> x = pi) (all_subplaces pi_prime)
        (* or pi_prime is a subplace of pi *)
        || List.exists (fun x -> x = pi_prime) subplaces_of_pi
  in match mu with
  | Unique -> (* for unique use to be safe, we need _no_ relevant loans *)
              is_empty (List.filter relevant (find_loans Shared gamma pi))
  | Shared -> (* for shared use, we only care that there are no relevant _unique_ loans *)
              is_empty (List.filter relevant (find_loans Unique gamma pi))

(* given a root identier x, compute all the places based on tau *)
let rec places_typ (pi : place) (tau : ty) : (place * ty) list =
  match tau with
  | BaseTy _ -> [(pi, tau)]
  | TyVar _ -> [(pi, tau)]
  | Ref (_, _, tauPrime) -> List.cons (pi, tau) (places_typ (Deref pi) tauPrime)
  | Fun (_, _, _, _) -> [(pi, tau)]
  | Array(_, _) -> [(pi, tau)]
  | Tup(tys) ->
    let work (acc : (place * ty) list) (pair : place * ty) =
      let (pi, ty) = pair
      in List.concat [acc; places_typ pi ty]
    in let projs = List.mapi (fun idx -> fun ty -> (IndexProj  (pi, idx), ty)) tys
    in List.fold_left work [(pi, tau)] projs

let rec prefixed_by (target : place) (in_pi : place) : bool =
  if target = in_pi then true
  else match in_pi with
  | Var _ -> false
  | Deref piPrime -> prefixed_by target piPrime
  | FieldProj (piPrime, _) -> prefixed_by target piPrime
  | IndexProj (piPrime, _) -> prefixed_by target piPrime

let rec replace (prefix : place) (new_pi : place)  (in_pi : place) : place =
  if prefix = in_pi then new_pi
  else match in_pi with
  | Var x -> Var x
  | Deref piPrime -> Deref (replace prefix new_pi piPrime)
  | FieldProj (piPrime, field) -> FieldProj (replace prefix new_pi piPrime, field)
  | IndexProj (piPrime, idx) -> IndexProj (replace prefix new_pi piPrime, idx)

(* given a root place pi, compute all the places and shapes based on v *)
let rec places_val (sigma : store) (pi : place) (v : value) : (place * shape) list =
  match v with
  | Prim p -> [(pi, Prim p)]
  | Ptr (mu, piPrime) ->
    let work (pair : place * shape) =
      let (pi, _) = pair
      in (replace piPrime (Deref pi) pi, Hole)
    in let inner_places = List.filter (fun (store_pi, _) -> prefixed_by pi store_pi) sigma
    in List.cons (pi, Ptr (mu, piPrime)) (List.map work inner_places)
  | Fun (provvars, tyvars, params, body) -> [(pi, Fun (provvars, tyvars, params, body))]
  | Tup values ->
    let work (acc : (place * shape) list) (pair : place * value) =
      let (pi, v) = pair
      in List.concat [acc; places_val sigma pi v]
    in let projs = List.mapi (fun idx -> fun v -> (IndexProj  (pi, idx), v)) values
    in List.fold_left work [(pi, Tup (List.map (fun _ -> ()) values))] projs
  | Array values -> [(pi, Array values)]

(* follow dereferences appropriately to find the pi where the non-trivial shape is located *)
let rec handle_derefs (sigma : store) (pi : place) : place =
  match pi with
  | Var x -> Var x
  | FieldProj (piPrime, field) -> FieldProj (handle_derefs sigma piPrime, field)
  | IndexProj (piPrime, idx) -> IndexProj (handle_derefs sigma piPrime, idx)
  | Deref piPrime ->
    match List.assoc (handle_derefs sigma piPrime) sigma with
    | Ptr (_, targetpi) -> targetpi
    | _ -> failwith "malformed store"

(* given a store sigma, compute the value at pi from its shape in sigma *)
let rec value (sigma : store) (pi : place) : value =
  match List.assoc pi sigma with
  | Hole -> value sigma (handle_derefs sigma pi)
  | Prim p -> Prim p
  | Ptr (mu, pi) -> Ptr (mu, pi)
  | Fun (provvars, tyvars, params, body) -> Fun (provvars, tyvars, params, body)
  | Tup boxes ->
    let values = List.mapi (fun idx -> fun () -> value sigma (IndexProj (pi, idx))) boxes
    in Tup values
  | Array values -> Array values

let print_is_safe (gamma : var_env) (mu : muta) (pi : place) =
  (if is_safe gamma mu pi then Format.printf "%a is %a safe in@.  %a@."
   else Format.printf "%a is not %a safe in@.  %a@.") pp_place pi pp_muta mu pp_var_env gamma

let main =
  let (x, y, _) = (1, 2, 3)
  in let u32  = BaseTy U32
  in let pi1 = Var x
  in let pi2 = IndexProj (Var x, 0)
  in let shared_ref from ty : ty = Ref (ProvSet [(Shared, from)], Shared, ty)
  in let env1 : var_env = [(x, Tup [u32])]
  in let env2 : var_env = [(x, Tup [u32]); (y, shared_ref pi2 u32)]
  in let env3 : var_env = [(x, Tup [u32]); (y, shared_ref pi1 (Tup [u32]))]
  in begin
    print_is_safe env1 Unique pi1;
    print_is_safe env1 Unique pi2;
    print_is_safe env2 Unique pi1;
    print_is_safe env2 Unique pi2;
    print_is_safe env2 Shared pi1;
    print_is_safe env2 Shared pi2;
    print_is_safe env3 Shared pi2;
    print_is_safe env3 Unique pi2;
  end
