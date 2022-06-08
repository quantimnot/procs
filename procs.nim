#****h* procs/procs
#* PURPOSE
#*   Tools and experiments in process managment.
#* 
#* FEATURES
#* 
#* - [x] Specify any IPC pipe between parent and child.
#* - [x] Assign child FD duplication.
#* - [ ] High level generic API.
#* - [ ] Support process groups.
#* - [ ] Set user and group.
#* - [ ] Set resource limits.
#* - [ ] High level OS specialized API.
#*   - [ ] POSIX
#*   - [ ] Windows
#*   - [ ] Linux
#*   - [ ] OpenBSD
#* - [ ] Comprehensive CI tests.
#*   - [ ] Linux
#*   - [ ] OpenBSD
#*   - [ ] macOS
#*   - [ ] Windows
#*   - [ ] FreeBSD
#*   - [ ] NetBSD
#*   - [ ] DragonFlyBSD
#*   - [ ] Android
#*   - [ ] Haiku https://github.com/hectorm/docker-qemu-haiku
#*   - [ ] uClibc
#* 
#* ATTRIBUTION
#*
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

import
  std/[options, strutils, monotimes, locks, macros]

when defined linux:
  import ./private/linux_backend as backend
elif defined openbsd:
  import ./private/openbsd_backend as backend
elif defined macosx:
  import ./private/darwin_backend as backend
elif defined posix:
  import ./private/posix_backend as backend
else: {.error: "procs is not implemented for this platform yet".}

# import pkg/sys/[handles, pipes]
# import pkg/platforms

# const
  # useProcessSignal {.booldefine.} = true


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

# func isValid(fd: FD): bool =
#   fd != InvalidFD

# #****f* procs/monitor
# proc monitor*(arg: tuple[invoc: Invocation, limits: Limits]): int {.effectsOf: [arg].} =
#   #* PURPOSE
#   #*   Monitor `stdio` and `stderr` for data to read.
#   #*   Monitor for termination.
#   #*   Monitor resource limits.
#   #* ATTRIBUTION
#   #*   Derived from @disruptek's https://github.com/disruptek/golden/blob/master/src/golden/invoke.nim
#   #* DESCRIPTION
#   #*   keep a process's output streams empty, saving them into the
#   #*   invocation with other runtime details; deadline is an epochTime
#   #*   after which we should manually terminate the process
#   #* TODO
#   #*   - cleanup
#   #*
#   template process: untyped = arg.invoc.handlers.process
#   template stdout: untyped = arg.invoc.handlers.stdout
#   template stderr: untyped = arg.invoc.handlers.stderr

#   # proc toString(str: openArray[char], len = -1): string =
#   #   result = newStringOfCap(len(str))
#   #   for ch in str:
#   #     add(result, ch)

#   # proc drainStreamInto(stream: Stream; handler: Handler) =
#   #   var output: string
#   #   while not stream.atEnd:
#   #     output &= stream.readChar
#   #   handler(output)

#   # proc drainStreamInto(stream: Stream; output: File | Stream) =
#   #   while not stream.atEnd:
#   #     output.write stream.readChar

#   # proc drain(ready: ReadyKey; stream: Stream; handler: Handler) =
#   #   if Event.Read in ready.events:
#   #     stream.drainStreamInto(handler)
#   #   elif {Event.Error} == ready.events:
#   #     stream.drainStreamInto(handler)
#   #   else:
#   #     assert ready.events.card == 0

#   # proc drain(ready: ReadyKey; stream: Stream; output: File | Stream) =
#   #   if Event.Read in ready.events:
#   #     stream.drainStreamInto(output)
#   #   elif {Event.Error} == ready.events:
#   #     stream.drainStreamInto(output)
#   #   else:
#   #     assert ready.events.card == 0

#   var
#     timeout = 1  # start with a timeout in the future
#     # clock = getTime()
#     watcher = newSelector[ProcEvent]()

#   stdout.handle.setBlocking false
#   stderr.handle.setBlocking false

#   # monitor whether the process has finished or produced output
#   when useProcessSignal:
#     watcher.registerProcess(process.handle.int, Quit)
#   if stdout.handle.isValid:
#     watcher.registerHandle(stdout.handle.int, {Error, Read}, StdOut)
#   if stderr.handle.isValid:
#     watcher.registerHandle(stderr.handle.int, {Error, Read}, StdErr)

#   block running:
#     try:
#       while true:
#         template duration: untyped = arg.limits.duration
#         if duration <= 0:
#           timeout = -1  # wait forever if no deadline is specified
#         # otherwise, reset the timeout if it hasn't passed
#         elif timeout > 0:
#           # cache the current time
#           let rightNow = getMonoTime().ticks
#           block checktime:
#             # we may break the checktime block before setting timeout to -1
#             if rightNow < duration:
#               # the number of ms remaining until the deadline
#               timeout = int( 1000 * (duration - rightNow) )
#               # if there is time left, we're done here
#               if timeout > 0:
#                 break checktime
#               # otherwise, we'll fall through, setting the timeout to -1
#               # which will cause us to kill the process...
#             timeout = -1
#         # if there's a deadline in place, see if we've passed it
#         if duration > 0 and timeout < 0:
#           # the deadline has passed; kill the process
#           if arg.limits.onLimit != nil:
#             arg.limits.onLimit(Duration)
#           else:
#             arg.invoc.process.terminate
#             arg.invoc.process.kill
#           # wait for it to exit so that we pass through the loop below only one
#           # additional time.
#           #
#           # if the process is wedged somehow, we will not continue to spawn more
#           # invocations that will DoS the machine.
#             return arg.invoc.process.waitForExit
#           # make sure we catch any remaining output and
#           # perform the expected measurements
#           # timeout = 0
#         let events = watcher.select(timeout)
#         foreach ready in events.items of ReadyKey:
#           var kind = watcher.getData(ready.fd)
#           case kind:
#           of StdOut:
#             if Read in ready.events:
#               stdout.onEvent()
#             if Error in ready.events:
#               if stdout.onError(ready.errorCode) == Unregister:
#                 watcher.unregister(ready.fd)
#           of StdErr:
#             if Read in ready.events:
#               stderr.onEvent()
#             if Error in ready.events:
#               if stderr.onError(ready.errorCode) == Unregister:
#                 watcher.unregister(ready.fd)
#           of Quit:
#             process.onEvent()
#             break running
#           of StdIn: discard
#         when not useProcessSignal:
#           if arg.process.peekExitCode != -1:
#             process.onEvent()
#             break
#         if duration >= 0:
#           assert timeout > 0, "terminating process failed measurements"
#     except IOSelectorsException as e:
#       stdmsg().writeLine "error talkin' to process: " & e.msg

# when windows in platform.os.parents:
#   include "."/procs_windows
# elif linux in platform.os.parents:
#   include "."/procs_linux
# elif darwin in platform.os.parents:
#   include "."/procs_darwin
# else:
#   {.error: "platform not supported".}

# proc exec*(name: string, args: openArray[string], env: openArray[(string, string)], handlers: Handlers): Future[Proc] {.async.} =
#   let path =
#     if name.fileExists:
#       name
#     else:
#       name.findExe
#   result = Proc()
#   result.procImpl = path.startProcess(
#     args = args,
#     env = env.newStringTable,
#     options = {}
#   )
#   result.stdin = result.procImpl.inputStream
#   # result.stdout = result.procImpl.outputHandle
#   # result.stderr = result.procImpl.errorHandle


# proc exec*(cmd: string): Proc


# proc exec*(name: string, args: openArray[string]): Proc


# proc exec*(name: string, env: openArray[(string, string)]): Proc


proc defaultPipes*(): owned seq[Pipe] =
  ## Returns a seq of default pipes.
  ## The defaults are a pipe for stdin, stdout and stderr.
  backend.defaultPipes()


proc inheritParentStreams*(): owned seq[Pipe] =
  ## Connects the child's stdin, stdout and stderr streams to its parents streams.
  backend.defaultPipes()


proc exec*[T: FD | File](
    path: FilePath,
    args: openArray[string] = [],
    env: openArray[(string, string)] = [],
    workDir = none FilePath,
    pipes: openArray[Pipe] = defaultPipes(),
    stdin: Option[T] = none T,
    stdout: Option[T] = none T,
    stderr: Option[T] = none T
  ): owned Proc {.raises: [Defect, OSError].} =
  when T is FD:
    backend.exec(path, args, env, workDir, pipes, stdin, stdout, stderr)
  else:
    backend.exec(path, args, env, workDir, pipes, toFD stdin, toFD stdout, toFD stderr)


proc wait*(process: Proc, events: set[ProcessEventKind]): set[ProcessEventKind] {.raises: [Defect, OSError].} =
  backend.wait(process, events)


proc waitForExit*(process: Proc): int {.raises: [Defect, OSError].} =
  backend.waitForExit(process)


# proc exec*(invoc: Invocation, handlers: Handlers): Proc


# proc wait*(p: Proc): int


# proc wait*(p: Proc, timeout: int): int


when isMainModule:
  when defined test:
    import std/[unittest, os]

    template testProg(name): FilePath =
      FilePath(getCurrentDir() / "test_programs" / name)

    suite "procs":
      test "(sync) filled child pipe buffers":
        # Test the situation where the parent tries waiting for a child to exit, but
        # the child is blocked writing to a full pipe.
        skip() # TODO

      test "(sync) waiting on child from within signal handler":
        # Test the situation where the parent is inside a signal handler and then tries
        # waiting for a child to exit.
        skip() # TODO

      test "(sync) shell command invocation":
        skip() # TODO

      test "(async) shell command invocation":
        skip() # TODO

      test "inherit parent stdio":
        skip() # TODO

      test "close stdio":
        # Test the situation where all of the child's stdio handles are closed.
        skip() # TODO

      test "(sync) kill a blocked child":
        skip() # TODO

      test "(async) kill a blocked child":
        skip() # TODO

      test "(sync) terminate a child":
        skip() # TODO

      test "(async) terminate a child":
        skip() # TODO

      test "(sync) kill child after termination grace period":
        skip() # TODO

      test "(async) kill child after termination grace period":
        skip() # TODO

      test "(sync) stop/resume a child":
        skip() # TODO

      test "(async) stop/resume a child":
        skip() # TODO

      test "resolve non-existing executable path":
        skip() # TODO

      test "resolve existing executable path":
        skip() # TODO

      test "calling procs that take `FilePath` type":
        skip() # TODO

      test "(async) child's max CPU duration reached":
        skip() # TODO

      test "(sync) wait for exit when child exited before call to wait":
        let p = exec(testProg "false", pipes = [])
        check waitForExit(p) == 1

      test "(sync) wait for exit when child exited after call to wait":
        skip() # TODO

      test "expected inherited file descriptors":
        # Test if child inherits expected file descriptors.
        skip() # TODO

      test "create process group":
        skip() # TODO

      test "create process group with uid/gid":
        skip() # TODO

      test "create process group with limits":
        skip() # TODO

      test "(sync) wait for process group exit":
        skip() # TODO

      test "(sync) terminate process group":
        skip() # TODO

      test "(sync) kill process group":
        skip() # TODO

      test "(async) wait for process group exit":
        skip() # TODO

      test "(async) terminate process group":
        skip() # TODO

      test "(async) kill process group":
        skip() # TODO

      test "(sync) stop/resume process group":
        skip() # TODO

      test "(async) stop/resume process group":
        skip() # TODO

      test "include process in existing process group":
        skip() # TODO

      test "don't redirect stdio":
        let p = exec(testProg "write_to_stdout_stderr", pipes = [])

      test "redirect stdout and stderr to files":
        var outFile = open("write_to_stdout_stderr.out", fmWrite)
        var errFile = open("write_to_stdout_stderr.err", fmWrite)
        let p = exec(
          testProg "write_to_stdout_stderr",
          pipes = [],
          stdout = some outFile,
          stderr = some errFile)
        check waitForExit(p) == 0
        close outFile
        close errFile
        check readFile("write_to_stdout_stderr.out") == "stdout\n"
        check readFile("write_to_stdout_stderr.err") == "stderr\n"


#       test "exec execname":
#         let p = exec("nim")
#         check:
#           p.wait == 0
#       test "exec execname args":
#         let p = exec("nim", ["--version"])
#         check:
#           p.wait == 0
#       test "exec execname env":
#         let p = exec("nim", [("JELLO", "")])
#         check:
#           p.wait == 0
#       test "exec execname args env":
#         let p = exec("nim", ["--version"], [("JELLO", "")])
#         check:
#           p.wait == 0
#       test "exec execname args env handlers":
#         proc onExit {.closure.} =
#           echo "exit"
#         proc onData(data: string) {.closure.} =
#           echo data
#         proc onError(code: OSErrorCode): HandlerResp {.closure.} =
#           echo $code
#         let handlers = Handlers(
#           process: (onExit, onError),
#           stdout: (onData, onError),
#           stderr: (onData, onError)
#         )
#         let p = exec("nim", ["secret"], [], handlers) # blocks until process is started

#         check:
#           p.wait == 0
