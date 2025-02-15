(** Action builder *)

open! Import

include module type of Action_builder0

module With_targets : sig
  type 'a build := 'a t

  type nonrec 'a t =
    { build : 'a t
    ; targets : Targets.t
    }

  val map_build : 'a t -> f:('a build -> 'b build) -> 'b t

  val return : 'a -> 'a t

  val add : 'a t -> file_targets:Path.Build.t list -> 'a t

  val add_directories : 'a t -> directory_targets:Path.Build.t list -> 'a t

  val map : 'a t -> f:('a -> 'b) -> 'b t

  val map2 : 'a t -> 'b t -> f:('a -> 'b -> 'c) -> 'c t

  val write_file_dyn :
    ?perm:Action.File_perm.t -> Path.Build.t -> string t -> Action.Full.t t

  val all : 'a t list -> 'a list t

  (** [memoize name t] is an action builder that behaves like [t] except that
      its result is computed only once. *)
  val memoize : string -> 'a t -> 'a t

  module O : sig
    val ( >>> ) : unit t -> 'a t -> 'a t

    val ( >>| ) : 'a t -> ('a -> 'b) -> 'b t

    val ( let+ ) : 'a t -> ('a -> 'b) -> 'b t

    val ( and+ ) : 'a t -> 'b t -> ('a * 'b) t
  end
end

(** Add targets to an action builder, turning a target-less [Action_builder.t]
    into [Action_builder.With_targets.t]. *)
val with_targets : 'a t -> targets:Targets.t -> 'a With_targets.t

(** Like [with_targets] but specifies a list of file targets. *)
val with_file_targets :
  'a t -> file_targets:Path.Build.t list -> 'a With_targets.t

(** Create a value of [With_targets.t] with the empty set of targets. *)
val with_no_targets : 'a t -> 'a With_targets.t

(** CR-someday diml: this API is not great, what about:

    {[
      module Action_with_deps : sig
        type t
        val add_file_dependency : t -> Path.t -> t
      end

      (** Same as
          [t >>> arr (fun x -> Action_with_deps.add_file_dependency x p)]
          but better as [p] is statically known *)

      val record_dependency
        :  Path.t
        -> ('a, Action_with_deps.t) t
        -> ('a, Action_with_deps.t) t
    ]} *)

(** [path p] records [p] as a file that is read by the action produced by the
    action builder. *)
val path : Path.t -> unit t

val dep : Dep.t -> unit t

val deps : Dep.Set.t -> unit t

val dyn_deps : ('a * Dep.Set.t) t -> 'a t

val paths : Path.t list -> unit t

val path_set : Path.Set.t -> unit t

(** Evaluate a predicate against all targets and record all the matched files as
    dependencies of the action produced by the action builder. *)
val paths_matching : loc:Loc.t -> File_selector.t -> Path.Set.t t

(** Like [paths_matching], but don't return the resulting set. The action
    dependency is still registered. *)
val paths_matching_unit : loc:Loc.t -> File_selector.t -> unit t

(** [paths_existing paths] will require as dependencies the files that actually
    exist. *)
val paths_existing : Path.t list -> unit t

(** [env_var v] records [v] as an environment variable that is read by the
    action produced by the action builder. *)
val env_var : string -> unit t

module Alias_status : sig
  type t =
    | Defined
    | Not_defined

  include Monoid.S with type t := t
end

val alias : Alias.t -> unit t

val dep_on_alias_if_exists : Alias.t -> Alias_status.t t

module Alias_rec (_ : sig
  (* This API isn't fully baked yet. We might move it to the rules *)

  (** [traverse dir ~f] traverses [dir] and evaluates [f] for every directory.
      Returns [Defined] if [f] returned [Defined] at least once. [Not_defined]
      otherwise. *)
  val traverse :
       Path.Build.t
    -> f:(path:Path.Build.t -> Alias_status.t t)
    -> Alias_status.t t
end) : sig
  (** Depend on an alias recursively. Return [Defined] if the alias is defined
      in at least one directory, and [Not_defined] otherwise. *)
  val dep_on_alias_rec : Alias.Name.t -> Path.Build.t -> Alias_status.t t
end

(** [dyn_memo_deps m] adds the dependencies computed by [m] while returning the
    extra value. *)
val dyn_memo_deps : (Dep.Set.t * 'a) Memo.t -> 'a t

(** Record dynamic dependencies *)
val dyn_paths : ('a * Path.t list) t -> 'a t

val dyn_paths_unit : Path.t list t -> unit t

val dyn_path_set : ('a * Path.Set.t) t -> 'a t

val dyn_path_set_reuse : Path.Set.t t -> Path.Set.t t

(** [contents path] returns a description that when run will return the contents
    of the file at [path]. *)
val contents : Path.t -> string t

(** [lines_of path] returns a description that when run will return the contents
    of the file at [path] as a list of lines. *)
val lines_of : Path.t -> string list t

(** Load an S-expression from a file *)
val read_sexp : Path.t -> Dune_lang.Ast.t t

(** Evaluates to [true] if the file is present on the file system or is the
    target of a rule. It doesn't add the path as dependency *)
val file_exists : Path.t -> bool t

(** [if_file_exists p ~then ~else] is a description that behaves like [then_] if
    [file_exists p] evaluates to [true], and [else_] otherwise. *)
val if_file_exists : Path.t -> then_:'a t -> else_:'a t -> 'a t

(** Create a file with the given contents. *)
val write_file :
     ?perm:Action.File_perm.t
  -> Path.Build.t
  -> string
  -> Action.Full.t With_targets.t

val write_file_dyn :
     ?perm:Action.File_perm.t
  -> Path.Build.t
  -> string t
  -> Action.Full.t With_targets.t

val with_stdout_to :
     ?perm:Action.File_perm.t
  -> Path.Build.t
  -> Action.Full.t t
  -> Action.Full.t With_targets.t

val copy : src:Path.t -> dst:Path.Build.t -> Action.Full.t With_targets.t

val symlink : src:Path.t -> dst:Path.Build.t -> Action.Full.t With_targets.t

val symlink_dir : src:Path.t -> dst:Path.Build.t -> Action.Full.t With_targets.t

val create_file :
  ?perm:Action.File_perm.t -> Path.Build.t -> Action.Full.t With_targets.t

(** Merge a list of actions accumulating the sets of their targets. *)
val progn : Action.Full.t With_targets.t list -> Action.Full.t With_targets.t

(** A version of [dyn_of_memo] that makes it convenient to declare dynamic
    action dependencies. *)
val dyn_of_memo_deps : ('a * Dep.Set.t) Memo.t t -> 'a t
