type t

val make : ?executor:(Command_spec.t -> Completed_run.t) -> unit -> t

val run : t -> Command_spec.t -> Completed_run.t

val stream : t -> Command_spec.t -> (string -> string -> unit) -> Completed_run.t
