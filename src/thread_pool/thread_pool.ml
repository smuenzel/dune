open Stdune

type t =
  { mutex : Mutex.t
  ; cv : Condition.t
  ; spawn_thread : (unit -> unit) -> unit
  ; tasks : (unit -> unit) Queue.t
  ; min_workers : int
  ; max_workers : int
  ; (* number of threads waiting for a task *)
    mutable idle : int
  ; (* total number of running threads *)
    mutable running : int
  ; mutable dead : Thread.t list
  }

let spawn_worker t =
  let rec loop () =
    while Queue.is_empty t.tasks do
      (* TODO [pthread_cond_timedwait] to set a maximum time for idling *)
      Condition.wait t.cv t.mutex
    done;
    let task = Queue.pop_exn t.tasks in
    t.idle <- t.idle - 1;
    Mutex.unlock t.mutex;
    (match task () with
    | () -> ()
    | exception exn ->
      Code_error.raise "thread pool tasks must not raise"
        [ ("exn", Exn.to_dyn exn) ]);
    Mutex.lock t.mutex;
    maybe_retry ()
  and start () =
    Mutex.lock t.mutex;
    t.idle <- t.idle + 1;
    loop ()
  and maybe_retry () =
    if t.running <= t.min_workers then loop ()
    else (
      t.running <- t.running - 1;
      t.dead <- Thread.self () :: t.dead;
      Mutex.unlock t.mutex)
  in
  t.running <- t.running + 1;
  t.spawn_thread start

let maybe_spawn_worker t =
  if t.idle = 0 && t.running < t.max_workers then spawn_worker t

let create ~min_workers ~max_workers ~spawn_thread =
  let t =
    { min_workers
    ; max_workers
    ; spawn_thread
    ; cv = Condition.create ()
    ; mutex = Mutex.create ()
    ; tasks = Queue.create ()
    ; idle = 0
    ; running = 0
    ; dead = []
    }
  in
  for _ = 0 to min_workers - 1 do
    spawn_worker t
  done;
  t

let task t ~f =
  Mutex.lock t.mutex;
  List.iter t.dead ~f:Thread.join;
  t.dead <- [];
  Queue.push t.tasks f;
  maybe_spawn_worker t;
  Condition.signal t.cv;
  Mutex.unlock t.mutex
