module Promote = struct
  type t =
    | Automatically
    | Never
end

let report_errors_config = ref Report_errors_config.default

let debug_digests = ref false

let debug_fs_cache = ref false

let wait_for_filesystem_clock = ref false

let capture_outputs = ref true

let debug_backtraces b =
  Dune_util.Report_error.report_backtraces b;
  Memo.Debug.track_locations_of_lazy_values := b

let debug_load_dir = ref false

let diff_command = ref None

let promote = ref None

let force = ref false

let always_show_command_line = ref false

type on_missing_dune_project_file =
  | Error
  | Warn
  | Ignore

let on_missing_dune_project_file = ref Warn

let display = ref Display.Quiet
