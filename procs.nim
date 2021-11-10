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
#*   - [ ] determine if blocking io problem is mine
#*   - [ ] Learn from these:
#*     - [ ] https://github.com/cheatfate/asynctools/blob/master/asynctools/asyncproc.nim
#*     - [X] https://github.com/disruptek/golden/blob/master/src/golden/invoke.nim
#*     - [ ] https://github.com/yglukhov/asyncthreadpool/blob/main/asyncthreadpool/private/pipes.nim
#*     - [ ] https://www.boost.org/doc/libs/1_77_0/doc/html/boost_process/tutorial.html
#*   - [ ] Evaluate these issues:
#*     - [ ] https://github.com/status-im/nim-chronos/issues/77
#*     - [ ] https://github.com/nim-lang/Nim/labels/osproc
#******

import std/[selectors, osproc, options]
import strutils
# import asyncdispatch
# import asyncfutures
import streams
import times

import pkg/foreach
import pkg/platforms

export osproc

type
  Handler* = proc(o:string) {.nimcall.}
  Pipe* = ref object
  Pid* = distinct int
  Config* = object
  ExecOut* = tuple
    exitCode: int
    output: string
    error: string

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

#****t* procs/Monitor
## PURPOSE
##   Tools and experiments in process managment.
type
  Monitor = enum
    Output = "the process has some data for us on stdout"
    Errors = "the process has some data for us on stderr"
    Finished = "the process has finished"
#******

#****f* procs/monitor
proc monitor*(process: Process; stdout, stderr: Handler; deadline = -1.0): int {.effectsOf: [stdout, stderr].} =
  ## PURPOSE
  ##   Monitor the `stdio` and `stderr` file handles for data.
  ## ATTRIBUTION
  ##   Derived from @disruptek's https://github.com/disruptek/golden/blob/master/src/golden/invoke.nim
  ## DESCRIPTION
  ##   keep a process's output streams empty, saving them into the
  ##   invocation with other runtime details; deadline is an epochTime
  ##   after which we should manually terminate the process
  #* TODO
  #*   - cleanup
  #*

  proc toString(str: openArray[char], len = -1): string =
    result = newStringOfCap(len(str))
    for ch in str:
      add(result, ch)

  proc drainStreamInto(stream: Stream; handler: Handler) =
    var output: string
    while not stream.atEnd:
      output &= stream.readChar
    handler(output)

  proc drainStreamInto(stream: Stream; output: File | Stream) =
    while not stream.atEnd:
      output.write stream.readChar

  proc drain(ready: ReadyKey; stream: Stream; handler: Handler) =
    if Event.Read in ready.events:
      stream.drainStreamInto(handler)
    elif {Event.Error} == ready.events:
      stream.drainStreamInto(handler)
    else:
      assert ready.events.card == 0

  proc drain(ready: ReadyKey; stream: Stream; output: File | Stream) =
    if Event.Read in ready.events:
      stream.drainStreamInto(output)
    elif {Event.Error} == ready.events:
      stream.drainStreamInto(output)
    else:
      assert ready.events.card == 0

  var
    timeout = 1  # start with a timeout in the future
    # clock = getTime()
    watcher = newSelector[Monitor]()

  # I set these to prevent `f_getc` from blocking.
  # I don't know if this is the right thing to do.
  discard process.outputHandle.setNonBlock
  discard process.errorHandle.setNonBlock

  # monitor whether the process has finished or produced output
  when defined(useProcessSignal):
    let signal = watcher.registerProcess(process.processId, Finished)
  if not stdout.isNil:
    watcher.registerHandle(process.outputHandle.int, {Event.Read}, Output)
  if not stderr.isNil:
    watcher.registerHandle(process.errorHandle.int, {Event.Read}, Errors)

  block running:
    try:
      while true:
        # if deadline <= 0.0:
        #   timeout = -1  # wait forever if no deadline is specified
        # # otherwise, reset the timeout if it hasn't passed
        # elif timeout > 0:
        #   # cache the current time
        #   let rightNow = epochTime()
        #   block checktime:
        #     # we may break the checktime block before setting timeout to -1
        #     if rightNow < deadline:
        #       # the number of ms remaining until the deadline
        #       timeout = int( 1000 * (deadline - rightNow) )
        #       # if there is time left, we're done here
        #       if timeout > 0:
        #         break checktime
        #       # otherwise, we'll fall through, setting the timeout to -1
        #       # which will cause us to kill the process...
        #     timeout = -1
        # # if there's a deadline in place, see if we've passed it
        # if deadline > 0.0 and timeout < 0:
        #   # the deadline has passed; kill the process
        #   process.terminate
        #   process.kill
        #   # wait for it to exit so that we pass through the loop below only one
        #   # additional time.
        #   #
        #   # if the process is wedged somehow, we will not continue to spawn more
        #   # invocations that will DoS the machine.
        #   invocation.code = process.waitForExit
        #   # make sure we catch any remaining output and
        #   # perform the expected measurements
        #   timeout = 0
        let events = watcher.select(timeout)
        foreach ready in events.items of ReadyKey:
          var kind: Monitor = watcher.getData(ready.fd)
          case kind:
          of Output:
            # keep the output stream from blocking
            ready.drain(process.outputStream, stdout)
          of Errors:
            # keep the errors stream from blocking
            ready.drain(process.errorStream, stderr)
          of Finished:
            # check the clock and cpu early
            # cpuPreWait(gold, invocation)
            # invocation.wall = getTime() - clock
            # drain any data in the streams
            if not stdout.isNil:
              process.outputStream.drainStreamInto(stdout)
            if not stderr.isNil:
              process.errorStream.drainStreamInto(stderr)
            break running
        when not defined(useProcessSignal):
          if process.peekExitCode != -1:
            # check the clock and cpu early
            # cpuPreWait(gold, invocation)
            # invocation.wall = getTime() - clock
            if not stdout.isNil:
              process.outputStream.drainStreamInto(stdout)
            if not stderr.isNil:
              process.errorStream.drainStreamInto(stderr)
            break
        if deadline >= 0:
          assert timeout > 0, "terminating process failed measurements"
    except IOSelectorsException as e:
      # merely report errors for database safety
      stdmsg().writeLine "error talkin' to process: " & e.msg

  try:
    # cleanup the selector
    when defined(useProcessSignal) and not defined(debugFdLeak):
      watcher.unregister signal
    watcher.close
  except Exception as e:
    # merely report errors for database safety
    stdmsg().writeLine e.msg

  # the process has exited, but this could be useful to Process
  # and in fact is needed for Rusage
  process.waitForExit
  # cpuPostWait(gold, invocation)
#******

when windows in platform.os.parents:
  include "."/procs_windows
elif linux in platform.os.parents:
  include "."/procs_linux
elif darwin in platform.os.parents:
  include "."/procs_darwin
else:
  {.error: "platform not supported".}
