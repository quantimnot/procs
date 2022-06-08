#****h* procs/procs
## PURPOSE
##   Tools and experiments in process managment.
## FEATURES
##
## ATTRIBUTION
##
#* TODO:
#*   - [X] workaround issue of `fgetc` blocking in thread
#*         I worked around it by setting the `O_NONBLOCK` flag on the handles
#*   - [X] determine if blocking io problem is mine
#*   - [ ] Learn from these:
#*     - [ ] https://github.com/cheatfate/asynctools/blob/master/asynctools/asyncproc.nim
#*     - [X] https://github.com/disruptek/golden/blob/master/src/golden/invoke.nim
#*     - [ ] https://github.com/yglukhov/asyncthreadpool/blob/main/asyncthreadpool/private/pipes.nim
#*     - [ ] https://www.boost.org/doc/libs/1_77_0/doc/html/boost_process/tutorial.html
#*   - [ ] Evaluate these issues:
#*     - [ ] https://github.com/status-im/nim-chronos/issues/77
#*     - [ ] https://github.com/nim-lang/Nim/labels/osproc
#******
import std/[selectors, osproc, options, strutils, streams, monotimes, posix, os]

import pkg/sys/[handles, pipes]
import pkg/foreach

import pkg/platforms

export osproc

const
  useProcessSignal {.booldefine.} = true

type
  #****t* procs/ErrorResp
  HandlerResp {.pure.} = enum
    ## PURPOSE
    Unregister, Ignore
   #******
  LimitKind* {.pure.} = enum
    Duration
  LimitHandler = proc(limit: LimitKind) {.closure.}
  Handler = proc() {.closure.}
  ErrorHandler = proc(code: OSErrorCode): HandlerResp {.closure.}
  Handlers* = tuple
    process, stdout, stderr:
      tuple[handle: FD, onEvent: Handler, onError: ErrorHandler]

  Limits* = object
    duration*: int
    grace*: int
    onLimit*: LimitHandler

  Invocation* = object
    process*: Process
    handlers*: Handlers

  #****t* procs/ProcEvent
  ProcEvent* {.pure.} = enum
    ## PURPOSE
    StdIn, StdOut, StdErr, Quit
  #******

# func initConfig*(): Config =
#   discard

# proc spawnProcess*(
#   cmd: string,
#   args: openArray[string] = [],
#   stdinFile = stdin,
#   stdoutFile = stdout,
#   stderrFile = stderr,
#   env: Table[string,string] = initTable[string,string](0),
#   config: Config = initConfig(),
#   workDir: string = ""): Pid

# proc pipeProcess*(
#   cmd: string,
#   args: openArray[string] = [],
#   env: Table[string,string] = initTable[string,string](0),
#   config: Config = initConfig(),
#   workDir: string = ""): Pipes

# proc execute*(
#   cmd: string,
#   args: openArray[string] = [],
#   env: Table[string,string] = initTable[string,string](0),
#   config: Config = initConfig(),
#   workDir: string = ""): ExecOut

func isValid(fd: FD): bool =
  fd != InvalidFD

#****f* procs/monitor
proc monitor*(arg: tuple[invok: Invocation, limits: Limits]): int {.effectsOf: [arg].} =
  ## PURPOSE
  ##   Monitor `stdio` and `stderr` for data to read.
  ##   Monitor for termination.
  ##   Monitor resource limits.
  ## ATTRIBUTION
  ##   Derived from @disruptek's https://github.com/disruptek/golden/blob/master/src/golden/invoke.nim
  ## DESCRIPTION
  ##   keep a process's output streams empty, saving them into the
  ##   invocation with other runtime details; deadline is an epochTime
  ##   after which we should manually terminate the process
  #* TODO
  #*   - cleanup
  #*
  template process: untyped = arg.invok.handlers.process
  template stdout: untyped = arg.invok.handlers.stdout
  template stderr: untyped = arg.invok.handlers.stderr

  # proc toString(str: openArray[char], len = -1): string =
  #   result = newStringOfCap(len(str))
  #   for ch in str:
  #     add(result, ch)

  # proc drainStreamInto(stream: Stream; handler: Handler) =
  #   var output: string
  #   while not stream.atEnd:
  #     output &= stream.readChar
  #   handler(output)

  # proc drainStreamInto(stream: Stream; output: File | Stream) =
  #   while not stream.atEnd:
  #     output.write stream.readChar

  # proc drain(ready: ReadyKey; stream: Stream; handler: Handler) =
  #   if Event.Read in ready.events:
  #     stream.drainStreamInto(handler)
  #   elif {Event.Error} == ready.events:
  #     stream.drainStreamInto(handler)
  #   else:
  #     assert ready.events.card == 0

  # proc drain(ready: ReadyKey; stream: Stream; output: File | Stream) =
  #   if Event.Read in ready.events:
  #     stream.drainStreamInto(output)
  #   elif {Event.Error} == ready.events:
  #     stream.drainStreamInto(output)
  #   else:
  #     assert ready.events.card == 0

  var
    timeout = 1  # start with a timeout in the future
    # clock = getTime()
    watcher = newSelector[ProcEvent]()

  stdout.handle.setBlocking false
  stderr.handle.setBlocking false

  # monitor whether the process has finished or produced output
  when useProcessSignal:
    watcher.registerProcess(process.handle.int, Quit)
  if stdout.handle.isValid:
    watcher.registerHandle(stdout.handle.int, {Error, Read}, StdOut)
  if stderr.handle.isValid:
    watcher.registerHandle(stderr.handle.int, {Error, Read}, StdErr)

  block running:
    try:
      while true:
        template duration: untyped = arg.limits.duration
        if duration <= 0:
          timeout = -1  # wait forever if no deadline is specified
        # otherwise, reset the timeout if it hasn't passed
        elif timeout > 0:
          # cache the current time
          let rightNow = getMonoTime().ticks
          block checktime:
            # we may break the checktime block before setting timeout to -1
            if rightNow < duration:
              # the number of ms remaining until the deadline
              timeout = int( 1000 * (duration - rightNow) )
              # if there is time left, we're done here
              if timeout > 0:
                break checktime
              # otherwise, we'll fall through, setting the timeout to -1
              # which will cause us to kill the process...
            timeout = -1
        # if there's a deadline in place, see if we've passed it
        if duration > 0 and timeout < 0:
          # the deadline has passed; kill the process
          if arg.limits.onLimit != nil:
            arg.limits.onLimit(Duration)
          else:
            arg.invok.process.terminate
            arg.invok.process.kill
          # wait for it to exit so that we pass through the loop below only one
          # additional time.
          #
          # if the process is wedged somehow, we will not continue to spawn more
          # invocations that will DoS the machine.
            return arg.invok.process.waitForExit
          # make sure we catch any remaining output and
          # perform the expected measurements
          # timeout = 0
        let events = watcher.select(timeout)
        foreach ready in events.items of ReadyKey:
          var kind = watcher.getData(ready.fd)
          case kind:
          of StdOut:
            if Read in ready.events:
              stdout.onEvent()
            if Error in ready.events:
              if stdout.onError(ready.errorCode) == Unregister:
                watcher.unregister(ready.fd)
          of StdErr:
            if Read in ready.events:
              stderr.onEvent()
            if Error in ready.events:
              if stderr.onError(ready.errorCode) == Unregister:
                watcher.unregister(ready.fd)
          of Quit:
            process.onEvent()
            break running
          of StdIn: discard
        when not useProcessSignal:
          if arg.process.peekExitCode != -1:
            process.onEvent()
            break
        if duration >= 0:
          assert timeout > 0, "terminating process failed measurements"
    except IOSelectorsException as e:
      stdmsg().writeLine "error talkin' to process: " & e.msg

when windows in platform.os.parents:
  include "."/procs_windows
elif linux in platform.os.parents:
  include "."/procs_linux
elif darwin in platform.os.parents:
  include "."/procs_darwin
else:
  {.error: "platform not supported".}

when isMainModule:
  when defined test:
    import unittests
    suite "":
      test "":
        check:
          discard
