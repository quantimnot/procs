import
  std/[oserrors, options, strformat]

export oserrors, options

const
  asyncBackend {.strdefine.} = "std"
  selectorBackend {.strdefine.} = "std"
  streamBackend {.strdefine.} = "std"

when asyncBackend == "none":
  discard
elif asyncBackend == "std" or asyncBackend == "asyncdispatch":
  import std/asyncdispatch
  export asyncdispatch
elif asyncBackend == "chronos":
  import pkg/chronos
  export chronos

when selectorBackend == "none":
  discard
elif selectorBackend == "std":
  import std/selectors
  export selectors
elif selectorBackend == "chronos":
  import pkg/chronos/selectors2
  export selectors2

when streamBackend == "none":
  discard
elif streamBackend == "std":
  import std/streams
  export streams
elif streamBackend == "faststreams":
  import pkg/faststreams
  export faststreams


template log*(msg): untyped =
  when defined debug:
    {.noSideEffect.}:
      try: stderr.writeLine msg
      except: discard


when defined linux:
  import ./linux_backend_types
elif defined openbsd:
  import ./openbsd_backend_types
elif defined macosx:
  import ./darwin_backend_types
elif defined posix:
  import ./posix_backend_types
else: {.error: "procs is not implemented for this platform yet".}


const
  pipeReadIdx* = 0
  pipeWriteIdx* = 1

type
  PID* = ImplPID
  ProcessGroupID* = ImplProcessGroupID
  FD* = ImplFD
  FilePath* = distinct string

  FDPair* = array[2, FD]

  PipeDirection* {.pure.} = enum
    ParentToChild
    ChildToParent

  Pipe* = ref PipeObj

  PipeObj* = object
    fds*: FDPair
    dir*: set[PipeDirection]
    childFD*: Option[FD]

  HandlerResp* {.pure.} = enum
    Unregister, Ignore

  LimitKind* {.pure.} = enum
    Duration

  ProcEvent* {.pure.} = enum
    StdIn, StdOut, StdErr, Quit

  Priority* {.pure.} = enum
    Low
    BelowNormal
    Normal
    AboveNormal
    High
    Realtime

  LimitHandler* = proc(limit: LimitKind) {.closure.}

  Handler* = proc(data: string) {.closure.}

  ErrorHandler* = proc(code: OSErrorCode): HandlerResp {.closure.}

  Handlers* = object
    process*, stdout*, stderr*: tuple[onEvent: Handler, onError: ErrorHandler]

  Limits* = object
    duration*: int
    grace*: int
    onLimit*: LimitHandler

  Invocation* = object
    path*: string
    args*: seq[string]
    env*: seq[string]

  ProcessEventKind* {.pure.} = enum
    Exited
    Stopped
    Continued
    Signaled

  ProcObj = object
    pid*: PID
    pgid*: ProcessGroupID
    impl*: ProcImpl
    # exitCode*: Option[cint]
    # thread*: Thread[Proc]
    # started*: Cond
    # stdinLock*: Lock
    # stdin*: Stream
  Proc* = ref ProcObj


proc `=copy`*(dest: var ProcObj, src: ProcObj) {.error.}

proc `=destroy`*(process: var ProcObj) =
  log "destroying process " & process.repr


proc close*(pipe: var PipeObj)

proc close*(pipe: Pipe) =
  close pipe[]

proc `=copy`*(dest: var PipeObj, src: PipeObj) {.error.}

proc `=destroy`*(pipe: var PipeObj) =
  log "destroying pipe " & pipe.repr
  close pipe

func `$`*(fd: FD): string =
  $fd.int

func toFD*(file: syncio.File): FD =
  FD getOsFileHandle file

func toFD*(file: Option[syncio.File]): Option[FD] =
  if file.isSome:
    some FD getOsFileHandle get file
  else:
    none FD
