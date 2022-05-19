(** Predicates are functions of type 'a -> bool *)

type 'a t = 'a -> bool

val create : ('a -> bool) -> 'a t

(** The predicate that evaluates to [true] for any query. *)
val true_ : _ t

(** The predicate that evaluates to [false] for any query. *)
val false_ : _ t

val test : 'a t -> 'a -> bool
