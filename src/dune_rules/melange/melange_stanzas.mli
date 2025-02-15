open Import

(** Stanza to produce JavaScript targets from Melange libraries *)
module Emit : sig
  type t =
    { loc : Loc.t
    ; target : string
    ; alias : Alias.Name.t option
    ; module_systems : (Melange.Module_system.t * string) list
    ; modules : Stanza_common.Modules_settings.t
    ; libraries : Lib_dep.t list
    ; package : Package.t option
    ; preprocess : Preprocess.With_instrumentation.t Preprocess.Per_module.t
    ; runtime_deps : Loc.t * Dep_conf.t list
    ; preprocessor_deps : Dep_conf.t list
    ; promote : Rule.Promote.t option
    ; compile_flags : Ordered_set_lang.Unexpanded.t
    ; allow_overlapping_dependencies : bool
    }

  type Stanza.t += T of t

  val decode : t Dune_lang.Decoder.t
end

val syntax : Syntax.t
