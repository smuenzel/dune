open Import
open Action_types
module Stanza = Dune_lang.Stanza

type t =
  | Run of String_with_vars.t * String_with_vars.t list
  | With_accepted_exit_codes of int Predicate_lang.t * t
  | Dynamic_run of String_with_vars.t * String_with_vars.t list
  | Chdir of String_with_vars.t * t
  | Setenv of String_with_vars.t * String_with_vars.t * t
  (* It's not possible to use a build String_with_vars.t here since jbuild
     supports redirecting to /dev/null. In [dune] files this is replaced with
     %{null} *)
  | Redirect_out of Outputs.t * String_with_vars.t * File_perm.t * t
  | Redirect_in of Inputs.t * String_with_vars.t * t
  | Ignore of Outputs.t * t
  | Progn of t list
  | Echo of String_with_vars.t list
  | Cat of String_with_vars.t
  | Copy of String_with_vars.t * String_with_vars.t
  | Symlink of String_with_vars.t * String_with_vars.t
  | Copy_and_add_line_directive of String_with_vars.t * String_with_vars.t
  | System of String_with_vars.t
  | Bash of String_with_vars.t
  | Write_file of String_with_vars.t * File_perm.t * String_with_vars.t
  | Mkdir of String_with_vars.t
  | Diff of (String_with_vars.t, String_with_vars.t) Diff.t
  | No_infer of t
  | Pipe of Outputs.t * t list
  | Cram of String_with_vars.t

let is_dev_null t = String_with_vars.is_pform t (Var Dev_null)

let translate_to_ignore fn output action =
  if is_dev_null fn then Ignore (output, action)
  else Redirect_out (output, fn, Normal, action)

let two_or_more decode =
  let open Dune_lang.Decoder in
  let+ n1 = decode
  and+ n2 = decode
  and+ rest = repeat decode in
  n1 :: n2 :: rest

let decode =
  let open Dune_lang.Decoder in
  let sw = String_with_vars.decode in
  Dune_lang.Decoder.fix (fun t ->
      sum
        [ ( "run"
          , let+ prog = sw
            and+ args = repeat sw in
            Run (prog, args) )
        ; ( "with-accepted-exit-codes"
          , let open Dune_lang in
            Syntax.since Stanza.syntax (2, 0)
            >>> let+ codes = Predicate_lang.decode_one Dune_lang.Decoder.int
                and+ version = Syntax.get_exn Stanza.syntax
                and+ loc, t = located t in
                let nesting_support_version = (2, 2) in
                let nesting_support =
                  Syntax.Version.Infix.(version >= nesting_support_version)
                in
                let rec is_ok = function
                  | Run _ | Bash _ | System _ -> true
                  | Chdir (_, t)
                  | Setenv (_, _, t)
                  | Ignore (_, t)
                  | Redirect_in (_, _, t)
                  | Redirect_out (_, _, _, t)
                  | No_infer t ->
                    if nesting_support then is_ok t
                    else
                      Syntax.Error.since loc Stanza.syntax
                        nesting_support_version
                        ~what:
                          "nesting modifiers under 'with-accepted-exit-codes'"
                  | _ -> false
                in
                let quote = List.map ~f:(Printf.sprintf "\"%s\"") in
                match (is_ok t, nesting_support) with
                | true, _ -> With_accepted_exit_codes (codes, t)
                | false, true ->
                  User_error.raise ~loc
                    [ Pp.textf
                        "Only %s can be nested under \
                         \"with-accepted-exit-codes\""
                        (Stdune.String.enumerate_and
                           (quote
                              [ "run"
                              ; "bash"
                              ; "system"
                              ; "chdir"
                              ; "setenv"
                              ; "ignore-<outputs>"
                              ; "with-stdin-from"
                              ; "with-<outputs>-to"
                              ; "no-infer"
                              ]))
                    ]
                | false, false ->
                  User_error.raise ~loc
                    [ Pp.textf
                        "with-accepted-exit-codes can only be used with %s"
                        (Stdune.String.enumerate_or
                           (quote [ "run"; "bash"; "system" ]))
                    ] )
        ; ( "dynamic-run"
          , Dune_lang.Syntax.since Action_plugin.syntax (0, 1)
            >>> let+ prog = sw
                and+ args = repeat sw in
                Dynamic_run (prog, args) )
        ; ( "chdir"
          , let+ dn = sw
            and+ t = t in
            Chdir (dn, t) )
        ; ( "setenv"
          , let+ k = sw
            and+ v = sw
            and+ t = t in
            Setenv (k, v, t) )
        ; ( "with-stdout-to"
          , let+ fn = sw
            and+ t = t in
            translate_to_ignore fn Stdout t )
        ; ( "with-stderr-to"
          , let+ fn = sw
            and+ t = t in
            translate_to_ignore fn Stderr t )
        ; ( "with-outputs-to"
          , let+ fn = sw
            and+ t = t in
            translate_to_ignore fn Outputs t )
        ; ( "with-stdin-from"
          , Dune_lang.Syntax.since Stanza.syntax (2, 0)
            >>> let+ fn = sw
                and+ t = t in
                Redirect_in (Stdin, fn, t) )
        ; ("ignore-stdout", t >>| fun t -> Ignore (Stdout, t))
        ; ("ignore-stderr", t >>| fun t -> Ignore (Stderr, t))
        ; ("ignore-outputs", t >>| fun t -> Ignore (Outputs, t))
        ; ("progn", repeat t >>| fun l -> Progn l)
        ; ( "echo"
          , let+ x = sw
            and+ xs = repeat sw in
            Echo (x :: xs) )
        ; ("cat", sw >>| fun x -> Cat x)
        ; ( "copy"
          , let+ src = sw
            and+ dst = sw in
            Copy (src, dst) )
        ; ( "copy#"
          , let+ src = sw
            and+ dst = sw in
            Copy_and_add_line_directive (src, dst) )
        ; ( "copy-and-add-line-directive"
          , let+ src = sw
            and+ dst = sw in
            Copy_and_add_line_directive (src, dst) )
        ; ("system", sw >>| fun cmd -> System cmd)
        ; ("bash", sw >>| fun cmd -> Bash cmd)
        ; ( "write-file"
          , let+ fn = sw
            and+ s = sw in
            Write_file (fn, Normal, s) )
        ; ( "diff"
          , let+ diff = Diff.decode sw sw ~optional:false in
            Diff diff )
        ; ( "diff?"
          , let+ diff = Diff.decode sw sw ~optional:true in
            Diff diff )
        ; ( "cmp"
          , let+ diff = Diff.decode_binary sw sw in
            Diff diff )
        ; ( "no-infer"
          , Dune_lang.Syntax.since Stanza.syntax (2, 6) >>> t >>| fun t ->
            No_infer t )
        ; ( "pipe-stdout"
          , Dune_lang.Syntax.since Stanza.syntax (2, 7)
            >>> let+ ts = two_or_more t in
                Pipe (Stdout, ts) )
        ; ( "pipe-stderr"
          , Dune_lang.Syntax.since Stanza.syntax (2, 7)
            >>> let+ ts = two_or_more t in
                Pipe (Stderr, ts) )
        ; ( "pipe-outputs"
          , Dune_lang.Syntax.since Stanza.syntax (2, 7)
            >>> let+ ts = two_or_more t in
                Pipe (Outputs, ts) )
        ; ( "cram"
          , Dune_lang.Syntax.since Stanza.syntax (2, 7)
            >>> let+ script = sw in
                Cram script )
        ])

let rec encode =
  let open Dune_lang in
  let sw = String_with_vars.encode in
  function
  | Run (a, xs) -> List (atom "run" :: sw a :: List.map xs ~f:sw)
  | With_accepted_exit_codes (pred, t) ->
    List
      [ atom "with-accepted-exit-codes"
      ; Predicate_lang.encode Dune_lang.Encoder.int pred
      ; encode t
      ]
  | Dynamic_run (a, xs) -> List (atom "run_dynamic" :: sw a :: List.map xs ~f:sw)
  | Chdir (a, r) -> List [ atom "chdir"; sw a; encode r ]
  | Setenv (k, v, r) -> List [ atom "setenv"; sw k; sw v; encode r ]
  | Redirect_out (outputs, fn, perm, r) ->
    List
      [ atom
          (sprintf "with-%s-to%s"
             (Outputs.to_string outputs)
             (File_perm.suffix perm))
      ; sw fn
      ; encode r
      ]
  | Redirect_in (inputs, fn, r) ->
    List
      [ atom (sprintf "with-%s-from" (Inputs.to_string inputs))
      ; sw fn
      ; encode r
      ]
  | Ignore (outputs, r) ->
    List [ atom (sprintf "ignore-%s" (Outputs.to_string outputs)); encode r ]
  | Progn l -> List (atom "progn" :: List.map l ~f:encode)
  | Echo xs -> List (atom "echo" :: List.map xs ~f:sw)
  | Cat x -> List [ atom "cat"; sw x ]
  | Copy (x, y) -> List [ atom "copy"; sw x; sw y ]
  | Symlink (x, y) -> List [ atom "symlink"; sw x; sw y ]
  | Copy_and_add_line_directive (x, y) -> List [ atom "copy#"; sw x; sw y ]
  | System x -> List [ atom "system"; sw x ]
  | Bash x -> List [ atom "bash"; sw x ]
  | Write_file (x, perm, y) ->
    List [ atom ("write-file" ^ File_perm.suffix perm); sw x; sw y ]
  | Mkdir x -> List [ atom "mkdir"; sw x ]
  | Diff { optional; file1; file2; mode = Binary } ->
    assert (not optional);
    List [ atom "cmp"; sw file1; sw file2 ]
  | Diff { optional = false; file1; file2; mode = _ } ->
    List [ atom "diff"; sw file1; sw file2 ]
  | Diff { optional = true; file1; file2; mode = _ } ->
    List [ atom "diff?"; sw file1; sw file2 ]
  | No_infer r -> List [ atom "no-infer"; encode r ]
  | Pipe (outputs, l) ->
    List
      (atom (sprintf "pipe-%s" (Outputs.to_string outputs))
      :: List.map l ~f:encode)
  | Cram script -> List [ atom "cram"; sw script ]

(* In [Action_exec] we rely on one-to-one mapping between the cwd-relative paths
   seen by the action and [Path.t] seen by dune.

   Having more than one dynamic_run with different cwds could break that. Also,
   we didn't really want to think about how multiple dynamic actions would
   interact (do we want dependencies requested by one to be visible to the
   other?).

   Moreover, we also check that 'dynamic-run' is not used within
   'with-exit-codes', since the meaning of this interaction is not clear. *)
let ensure_at_most_one_dynamic_run ~loc action =
  let rec loop : t -> bool = function
    | Dynamic_run _ -> true
    | Chdir (_, t)
    | Setenv (_, _, t)
    | Redirect_out (_, _, _, t)
    | Redirect_in (_, _, t)
    | Ignore (_, t)
    | With_accepted_exit_codes (_, t)
    | No_infer t -> loop t
    | Run _
    | Echo _
    | Cat _
    | Copy _
    | Symlink _
    | Copy_and_add_line_directive _
    | System _
    | Bash _
    | Write_file _
    | Mkdir _
    | Diff _
    | Cram _ -> false
    | Pipe (_, ts) | Progn ts ->
      List.fold_left ts ~init:false ~f:(fun acc t ->
          let have_dyn = loop t in
          if acc && have_dyn then
            User_error.raise ~loc
              [ Pp.text
                  "Multiple 'dynamic-run' commands within single action are \
                   not supported."
              ]
          else acc || have_dyn)
  in
  ignore (loop action)

let validate ~loc t = ensure_at_most_one_dynamic_run ~loc t

let rec map_string_with_vars t ~f =
  match t with
  | Run (sw, xs) -> Run (f sw, xs)
  | With_accepted_exit_codes (lang, t) ->
    With_accepted_exit_codes (lang, map_string_with_vars t ~f)
  | Dynamic_run (sw, sws) -> Dynamic_run (f sw, List.map sws ~f)
  | Chdir (sw, t) -> Chdir (f sw, map_string_with_vars ~f t)
  | Setenv (sw1, sw2, t) -> Setenv (f sw1, f sw2, map_string_with_vars t ~f)
  | Redirect_out (o, sw, p, t) ->
    Redirect_out (o, f sw, p, map_string_with_vars t ~f)
  | Redirect_in (i, sw, t) -> Redirect_in (i, f sw, t)
  | Ignore (o, t) -> Ignore (o, map_string_with_vars t ~f)
  | Progn xs -> Progn (List.map xs ~f:(map_string_with_vars ~f))
  | Echo xs -> Echo xs
  | Cat sw -> Cat (f sw)
  | Copy (sw1, sw2) -> Copy (f sw1, f sw2)
  | Symlink (sw1, sw2) -> Symlink (f sw1, f sw2)
  | Copy_and_add_line_directive (sw1, sw2) ->
    Copy_and_add_line_directive (f sw1, f sw2)
  | System sw -> System (f sw)
  | Bash sw -> Bash (f sw)
  | Write_file (sw1, perm, sw2) -> Write_file (f sw1, perm, f sw2)
  | Mkdir sw -> Mkdir (f sw)
  | Diff diff -> Diff (Diff.map diff ~path:f ~target:f)
  | No_infer t -> No_infer (map_string_with_vars t ~f)
  | Pipe (o, ts) -> Pipe (o, List.map ts ~f:(map_string_with_vars ~f))
  | Cram sw -> Cram (f sw)

let remove_locs = map_string_with_vars ~f:String_with_vars.remove_locs

let compare_no_locs t1 t2 = Poly.compare (remove_locs t1) (remove_locs t2)

open Dune_lang.Decoder

let decode =
  (let+ loc, action = located decode in
   validate ~loc action;
   action)
  <|> let+ loc = loc in
      User_error.raise ~loc
        [ Pp.textf
            "if you meant for this to be executed with bash, write (bash \
             \"...\") instead"
        ]

let to_dyn a = Dune_lang.to_dyn (encode a)

let equal x y = Poly.equal x y

let chdir dir t = Chdir (dir, t)

let run prog args = Run (prog, args)
