(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *   INRIA, CNRS and contributors - Copyright 1999-2018       *)
(* <O___,, *       (see CREDITS file for the list of authors)           *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

let fatal_error exn =
  Topfmt.(in_phase ~phase:ParsingCommandLine print_err_exn exn);
  let exit_code = if CErrors.(is_anomaly exn || not (handled exn)) then 129 else 1 in
  exit exit_code

let error_missing_arg s =
  prerr_endline ("Error: extra argument expected after option "^s);
  prerr_endline "See -help for the syntax of supported options";
  exit 1

(******************************************************************************)
(* Imperative effects! This must be fixed at some point.                      *)
(******************************************************************************)
let set_worker_id opt s =
  assert (s <> "master");
  Flags.async_proofs_worker_id := s

let set_type_in_type () =
  let typing_flags = Environ.typing_flags (Global.env ()) in
  Global.set_typing_flags { typing_flags with Declarations.check_universes = false }

(******************************************************************************)

type compilation_mode = BuildVo | BuildVio | Vio2Vo
type color = [`ON | `AUTO | `OFF]

type coq_cmdopts = {

  load_init   : bool;
  load_rcfile : bool;
  rcfile      : string option;

  ml_includes : Mltop.coq_path list;
  vo_includes : Mltop.coq_path list;
  vo_requires : (string * string option * bool option) list;
  (* None = No Import; Some false = Import; Some true = Export *)

  (* XXX: Fusion? *)
  batch_mode : bool;
  compilation_mode : compilation_mode;

  toplevel_name : Stm.interactive_top;

  compile_list: (string * bool) list;  (* bool is verbosity  *)
  compilation_output_name : string option;

  load_vernacular_list : (string * bool) list;

  vio_checking: bool;
  vio_tasks   : (int list * string) list;
  vio_files   : string list;
  vio_files_j : int;

  color : color;

  impredicative_set : Declarations.set_predicativity;
  indices_matter : bool;
  enable_VM : bool;
  enable_native_compiler : bool;
  stm_flags   : Stm.AsyncOpts.stm_opt;
  debug       : bool;
  diffs_set   : bool;
  time        : bool;

  filter_opts : bool;

  glob_opt    : bool;

  memory_stat : bool;
  print_tags  : bool;
  print_where : bool;
  print_config: bool;
  output_context : bool;

  print_emacs : bool;

  inputstate  : string option;
  outputstate : string option;

}

let default_toplevel = Names.(DirPath.make [Id.of_string "Top"])

let default_opts = {

  load_init   = true;
  load_rcfile = true;
  rcfile      = None;

  ml_includes = [];
  vo_includes = [];
  vo_requires = [];

  batch_mode = false;
  compilation_mode = BuildVo;

  toplevel_name = Stm.TopLogical default_toplevel;

  compile_list = [];
  compilation_output_name = None;

  load_vernacular_list = [];

  vio_checking = false;
  vio_tasks    = [];
  vio_files    = [];
  vio_files_j  = 0;

  color = `AUTO;

  impredicative_set = Declarations.PredicativeSet;
  indices_matter = false;
  enable_VM = true;
  enable_native_compiler = Coq_config.native_compiler;
  stm_flags    = Stm.AsyncOpts.default_opts;
  debug        = false;
  diffs_set    = false;
  time         = false;

  filter_opts  = false;

  glob_opt     = false;

  memory_stat  = false;
  print_tags   = false;
  print_where  = false;
  print_config = false;
  output_context = false;

  print_emacs = false;

  (* Quiet / verbosity options should be here *)

  inputstate  = None;
  outputstate = None;
}

(******************************************************************************)
(* Functional arguments                                                       *)
(******************************************************************************)
let add_ml_include opts s =
  Mltop.{ opts with ml_includes = {recursive = false; path_spec = MlPath s} :: opts.ml_includes }

let add_vo_include opts unix_path coq_path implicit =
  let open Mltop in
  let coq_path = Libnames.dirpath_of_string coq_path in
  { opts with vo_includes = {
        recursive = true;
        path_spec = VoPath { unix_path; coq_path; has_ml = AddNoML; implicit } } :: opts.vo_includes }

let add_vo_require opts d p export =
  { opts with vo_requires = (d, p, export) :: opts.vo_requires }

let add_compat_require opts v =
  match v with
  | Flags.V8_7 -> add_vo_require opts "Coq.Compat.Coq87" None (Some false)
  | Flags.V8_8 -> add_vo_require opts "Coq.Compat.Coq88" None (Some false)
  | Flags.Current -> add_vo_require opts "Coq.Compat.Coq89" None (Some false)

let set_batch_mode opts =
  (* XXX: This should be in the argument record *)
  Flags.quiet := true;
  System.trust_file_cache := true;
  { opts with batch_mode = true }

let add_compile opts verbose s =
  let opts = set_batch_mode opts in
  if not opts.glob_opt then Dumpglob.dump_to_dotglob ();
  (* make the file name explicit; needed not to break up Coq loadpath stuff. *)
  let s =
    let open Filename in
    if is_implicit s
    then concat current_dir_name s
    else s
  in
  { opts with compile_list = (s,verbose) :: opts.compile_list }

let add_load_vernacular opts verb s =
  { opts with load_vernacular_list = (CUnix.make_suffix s ".v",verb) :: opts.load_vernacular_list }

let add_vio_task opts f =
  let opts = set_batch_mode opts in
  { opts with vio_tasks = f :: opts.vio_tasks }

let add_vio_file opts f =
  let opts = set_batch_mode opts in
  { opts with vio_files = f :: opts.vio_files }

let set_vio_checking_j opts opt j =
  try { opts with vio_files_j = int_of_string j }
  with Failure _ ->
    prerr_endline ("The first argument of " ^ opt ^ " must the number");
    prerr_endline "of concurrent workers to be used (a positive integer).";
    prerr_endline "Makefiles generated by coq_makefile should be called";
    prerr_endline "setting the J variable like in 'make vio2vo J=3'";
    exit 1

(** Options for proof general *)
let set_emacs opts =
  Printer.enable_goal_tags_printing := true;
  { opts with color = `OFF; print_emacs = true }

let set_color opts = function
| "yes" | "on" -> { opts with color = `ON }
| "no" | "off" -> { opts with color = `OFF }
| "auto" -> { opts with color = `AUTO }
| _ -> prerr_endline ("Error: on/off/auto expected after option color"); exit 1

let warn_deprecated_inputstate =
  CWarnings.create ~name:"deprecated-inputstate" ~category:"deprecated"
         (fun () -> Pp.strbrk "The inputstate option is deprecated and discouraged.")

let set_inputstate opts s =
  warn_deprecated_inputstate ();
  { opts with inputstate = Some s }

let warn_deprecated_outputstate =
  CWarnings.create ~name:"deprecated-outputstate" ~category:"deprecated"
         (fun () ->
          Pp.strbrk "The outputstate option is deprecated and discouraged.")

let set_outputstate opts s =
  warn_deprecated_outputstate ();
  { opts with outputstate = Some s }

let exitcode opts = if opts.filter_opts then 2 else 0

(******************************************************************************)
(* Parsing helpers                                                            *)
(******************************************************************************)
let get_task_list s = List.map int_of_string (Str.split (Str.regexp ",") s)

let get_bool opt = function
  | "yes" | "on" -> true
  | "no" | "off" -> false
  | _ -> prerr_endline ("Error: yes/no expected after option "^opt); exit 1

let get_int opt n =
  try int_of_string n
  with Failure _ ->
    prerr_endline ("Error: integer expected after option "^opt); exit 1

let get_float opt n =
  try float_of_string n
  with Failure _ ->
    prerr_endline ("Error: float expected after option "^opt); exit 1

let get_host_port opt s =
  match String.split_on_char ':' s with
  | [host; portr; portw] ->
       Some (Spawned.Socket(host, int_of_string portr, int_of_string portw))
  | ["stdfds"] -> Some Spawned.AnonPipe
  | _ ->
     prerr_endline ("Error: host:portr:portw or stdfds expected after option "^opt);
     exit 1

let get_error_resilience opt = function
  | "on" | "all" | "yes" -> `All
  | "off" | "no" -> `None
  | s -> `Only (String.split_on_char ',' s)

let get_priority opt s =
  try CoqworkmgrApi.priority_of_string s
  with Invalid_argument _ ->
    prerr_endline ("Error: low/high expected after "^opt); exit 1

let get_async_proofs_mode opt = let open Stm.AsyncOpts in function
  | "no" | "off" -> APoff
  | "yes" | "on" -> APon
  | "lazy" -> APonLazy
  | _ -> prerr_endline ("Error: on/off/lazy expected after "^opt); exit 1

let get_cache opt = function
  | "force" -> Some Stm.AsyncOpts.Force
  | _ -> prerr_endline ("Error: force expected after "^opt); exit 1

let is_not_dash_option = function
  | Some f when String.length f > 0 && f.[0] <> '-' -> true
  | _ -> false

let rec add_vio_args peek next oval =
  if is_not_dash_option (peek ()) then
    let oval = add_vio_file oval (next ()) in
    add_vio_args peek next oval
  else oval

let get_native_name s =
  (* We ignore even critical errors because this mode has to be super silent *)
  try
    String.concat "/" [Filename.dirname s;
      Nativelib.output_dir; Library.native_name_from_filename s]
  with _ -> ""

(*s Parsing of the command line.
    We no longer use [Arg.parse], in order to use share [Usage.print_usage]
    between coqtop and coqc. *)

let usage_no_coqlib = CWarnings.create ~name:"usage-no-coqlib" ~category:"filesystem"
    (fun () -> Pp.str "cannot guess a path for Coq libraries; dynaminally loaded flags will not be mentioned")

exception NoCoqLib

let usage batch =
  begin
    try Envars.set_coqlib ~fail:(fun x -> raise NoCoqLib)
    with NoCoqLib -> usage_no_coqlib ()
  end;
  let lp = Coqinit.toplevel_init_load_path () in
  (* Necessary for finding the toplevels below *)
  List.iter Mltop.add_coq_path lp;
  if batch
  then Usage.print_usage_coqc ()
  else Usage.print_usage_coqtop ()

(* Main parsing routine *)
let parse_args init_opts arglist : coq_cmdopts * string list =
  let args = ref arglist in
  let extras = ref [] in
  let rec parse oval = match !args with
  | [] ->
    (oval, List.rev !extras)
  | opt :: rem ->
    args := rem;
    let next () = match !args with
      | x::rem -> args := rem; x
      | [] -> error_missing_arg opt
    in
    let peek_next () = match !args with
      | x::_ -> Some x
      | [] -> None
    in
    let noval = begin match opt with

    (* Complex options with many args *)
    |"-I"|"-include" ->
      begin match rem with
      | d :: rem ->
        args := rem;
        add_ml_include oval d
      | [] -> error_missing_arg opt
      end
    |"-Q" ->
      begin match rem with
      | d :: p :: rem ->
        args := rem;
        add_vo_include oval d p false
      | _ -> error_missing_arg opt
      end
    |"-R" ->
      begin match rem with
      | d :: p :: rem ->
        args := rem;
        add_vo_include oval d p true
      | _ -> error_missing_arg opt
      end

    (* Options with two arg *)
    |"-check-vio-tasks" ->
      let tno = get_task_list (next ()) in
      let tfile = next () in
      add_vio_task oval (tno,tfile)

    |"-schedule-vio-checking" ->
      let oval = { oval with vio_checking = true } in
      let oval = set_vio_checking_j oval opt (next ()) in
      let oval = add_vio_file oval (next ()) in
      add_vio_args peek_next next oval

    |"-schedule-vio2vo" ->
      let oval = set_vio_checking_j oval opt (next ()) in
      let oval = add_vio_file oval (next ()) in
      add_vio_args peek_next next oval

    (* Options with one arg *)
    |"-coqlib" ->
      Envars.set_user_coqlib (next ());
      oval

    |"-async-proofs" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_mode = get_async_proofs_mode opt (next())
      }}
    |"-async-proofs-j" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_n_workers = (get_int opt (next ()))
      }}
    |"-async-proofs-cache" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_cache = get_cache opt (next ())
      }}

    |"-async-proofs-tac-j" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_n_tacworkers = (get_int opt (next ()))
      }}

    |"-async-proofs-worker-priority" ->
      CoqworkmgrApi.async_proofs_worker_priority := get_priority opt (next ());
      oval

    |"-async-proofs-private-flags" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_private_flags = Some (next ());
      }}

    |"-async-proofs-tactic-error-resilience" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_tac_error_resilience = get_error_resilience opt (next ())
      }}

    |"-async-proofs-command-error-resilience" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_cmd_error_resilience = get_bool opt (next ())
      }}

    |"-async-proofs-delegation-threshold" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_delegation_threshold = get_float opt (next ())
      }}

    |"-worker-id" -> set_worker_id opt (next ()); oval

    |"-compat" ->
      let v = G_vernac.parse_compat_version (next ()) in
      Flags.compat_version := v;
      add_compat_require oval v

    |"-compile" ->
      add_compile oval false (next ())

    |"-compile-verbose" ->
      add_compile oval true (next ())

    |"-dump-glob" ->
      Dumpglob.dump_into_file (next ());
      { oval with glob_opt = true }

    |"-feedback-glob" ->
      Dumpglob.feedback_glob (); oval

    |"-exclude-dir" ->
      System.exclude_directory (next ()); oval

    |"-init-file" ->
      { oval with rcfile = Some (next ()); }

    |"-inputstate"|"-is" ->
      set_inputstate oval (next ())

    |"-outputstate" ->
      set_outputstate oval (next ())

    |"-load-ml-object" ->
      Mltop.dir_ml_load (next ()); oval

    |"-load-ml-source" ->
      Mltop.dir_ml_use (next ()); oval

    |"-load-vernac-object" ->
      add_vo_require oval (next ()) None None

    |"-load-vernac-source"|"-l" ->
      add_load_vernacular oval false (next ())

    |"-load-vernac-source-verbose"|"-lv" ->
      add_load_vernacular oval true (next ())

    |"-mangle-names" ->
      Goptions.set_bool_option_value ["Mangle"; "Names"] true;
      Goptions.set_string_option_value ["Mangle"; "Names"; "Prefix"] (next ());
      oval

    |"-print-mod-uid" ->
      let s = String.concat " " (List.map get_native_name rem) in print_endline s; exit 0

    |"-profile-ltac-cutoff" ->
      Flags.profile_ltac := true;
      Flags.profile_ltac_cutoff := get_float opt (next ());
      oval

    |"-require" -> add_vo_require oval (next ()) None (Some false)

    |"-top" ->
      let topname = Libnames.dirpath_of_string (next ()) in
      if Names.DirPath.is_empty topname then
        CErrors.user_err Pp.(str "Need a non empty toplevel module name");
      { oval with toplevel_name = Stm.TopLogical topname }

    |"-topfile" ->
      { oval with toplevel_name = Stm.TopPhysical (next()) }

    |"-main-channel" ->
      Spawned.main_channel := get_host_port opt (next()); oval

    |"-control-channel" ->
      Spawned.control_channel := get_host_port opt (next()); oval

    |"-vio2vo" ->
      let oval = add_compile oval false (next ()) in
      { oval with compilation_mode = Vio2Vo }

    |"-w" | "-W" ->
      let w = next () in
      if w = "none" then
        (CWarnings.set_flags w; oval)
      else
        let w = CWarnings.get_flags () ^ "," ^ w in
        CWarnings.set_flags (CWarnings.normalize_flags_string w);
        oval

    |"-o" -> { oval with compilation_output_name = Some (next()) }

    |"-bytecode-compiler" ->
      { oval with enable_VM = get_bool opt (next ()) }

    |"-native-compiler" ->

      (* We use two boolean flags because the four states make sense, even if
      only three are accessible to the user at the moment. The selection of the
      produced artifact(s) (`.vo`, `.vio`, `.coq-native`, ...) should be done by
      a separate flag, and the "ondemand" value removed. Once this is done, use
      [get_bool] here. *)
      let (enable,precompile) =
        match (next ()) with
        | ("yes" | "on") -> true, true
        | "ondemand" -> true, false
        | ("no" | "off") -> false, false
        | _ -> prerr_endline ("Error: (yes|no|ondemand) expected after option -native-compiler"); exit 1
      in
      Flags.output_native_objects := precompile;
      { oval with enable_native_compiler = enable }

    (* Options with zero arg *)
    |"-async-queries-always-delegate"
    |"-async-proofs-always-delegate"
    |"-async-proofs-never-reopen-branch" ->
      { oval with stm_flags = { oval.stm_flags with
        Stm.AsyncOpts.async_proofs_never_reopen_branch = true
      }}
    |"-batch" -> set_batch_mode oval
    |"-test-mode" -> Flags.test_mode := true; oval
    |"-beautify" -> Flags.beautify := true; oval
    |"-boot" -> Flags.boot := true; { oval with load_rcfile = false; }
    |"-bt" -> Backtrace.record_backtrace true; oval
    |"-color" -> set_color oval (next ())
    |"-config"|"--config" -> { oval with print_config = true }
    |"-debug" -> Coqinit.set_debug (); oval
    |"-diffs" -> let opt = next () in
                  if List.exists (fun x -> opt = x) ["off"; "on"; "removed"] then
                    Proof_diffs.write_diffs_option opt
                  else
                    (prerr_endline ("Error: on|off|removed expected after -diffs"); exit 1);
                  { oval with diffs_set = true }
    |"-stm-debug" -> Stm.stm_debug := true; oval
    |"-emacs" -> set_emacs oval
    |"-filteropts" -> { oval with filter_opts = true }
    |"-impredicative-set" ->
      { oval with impredicative_set = Declarations.ImpredicativeSet }
    |"-indices-matter" -> { oval with indices_matter = true }
    |"-m"|"--memory" -> { oval with memory_stat = true }
    |"-noinit"|"-nois" -> { oval with load_init = false }
    |"-no-glob"|"-noglob" -> Dumpglob.noglob (); { oval with glob_opt = true }
    |"-output-context" -> { oval with output_context = true }
    |"-profile-ltac" -> Flags.profile_ltac := true; oval
    |"-q" -> { oval with load_rcfile = false; }
    |"-quiet"|"-silent" ->
      Flags.quiet := true;
      Flags.make_warn false;
      oval
    |"-quick" -> { oval with compilation_mode = BuildVio }
    |"-list-tags" -> { oval with print_tags = true }
    |"-time" -> { oval with time = true }
    |"-type-in-type" -> set_type_in_type (); oval
    |"-unicode" -> add_vo_require oval "Utf8_core" None (Some false)
    |"-where" -> { oval with print_where = true }
    |"-h"|"-H"|"-?"|"-help"|"--help" -> usage oval.batch_mode; oval
    |"-v"|"--version" -> Usage.version (exitcode oval)
    |"-print-version"|"--print-version" ->
      Usage.machine_readable_version (exitcode oval)

    (* Unknown option *)
    | s ->
      extras := s :: !extras;
      oval
    end in
    parse noval
  in
  try
    parse init_opts
  with any -> fatal_error any

(******************************************************************************)
(* Startup LoadPath and Modules                                               *)
(******************************************************************************)
(* prelude_data == From Coq Require Export Prelude. *)
let prelude_data = "Prelude", Some "Coq", Some false

let require_libs opts =
  if opts.load_init then prelude_data :: opts.vo_requires else opts.vo_requires

let cmdline_load_path opts =
  List.rev opts.vo_includes @ List.(rev opts.ml_includes)

let build_load_path opts =
  Coqinit.libs_init_load_path ~load_init:opts.load_init @
  cmdline_load_path opts
