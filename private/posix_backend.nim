## Compile-time Defines
## 
## `procsUsePosixFork`: Use POSIX `fork` instead of `spawn`. This is automatically
## set for some platforms.
## 
## `posixUseExecvp`: Use POSIX `execvp` instead of `execve`. This only applies
## when define `procsUsePosixFork` is also set. This is automatically set for
## some platforms.
##

import
  std/[strtabs, tables]

include ./common

from std/posix import nil
from std/os import envPairs, setCurrentDir, getCurrentDir


template checkReturn(call; expect = 0'i32): untyped =
  if call != expect: raiseOSError(osLastError())


proc envToCStringArray(env: openArray[(string, string)]): cstringArray =
  result = cast[cstringArray](alloc0((env.len + 1) * sizeof(cstring)))
  var i = 0
  for (key, val) in env:
    var x = key & "=" & val
    result[i] = cast[cstring](alloc(x.len+1))
    copyMem(result[i], addr(x[0]), x.len+1)
    inc(i)


proc newAnonPipeFDs(): FDPair =
  checkReturn posix.pipe(array[2, cint](result))


proc newSocketPairFDs(): FDPair =
  checkReturn posix.socketpair(posix.AF_UNIX, posix.SOCK_STREAM, 0, array[2, cint](result))


proc close(pipe: var PipeObj) =
  checkReturn posix.close(cint(pipe.fds[0]))
  checkReturn posix.close(cint(pipe.fds[1]))
  pipe.fds[0] = FD(-1)
  pipe.fds[1] = FD(-1)


proc defaultPipes*(): owned seq[Pipe] =
  @[
    Pipe(fds: newAnonPipeFDs(), dir: {ParentToChild}, childFD: some FD(posix.STDIN_FILENO)),
    Pipe(fds: newAnonPipeFDs(), dir: {ChildToParent}, childFD: some FD(posix.STDOUT_FILENO)),
    Pipe(fds: newAnonPipeFDs(), dir: {ChildToParent}, childFD: some FD(posix.STDERR_FILENO)),
  ]


proc exec*(
    path: FilePath,
    args: openArray[string] = [],
    env: openArray[(string, string)] = [],
    workDir = none FilePath,
    pipes: openArray[Pipe] = defaultPipes(),
    stdin = none FD,
    stdout = none FD,
    stderr = none FD
  ): owned Proc {.raises: [Defect, OSError].} =
  new(result)

  # prepare arguments for the syscalls
  var sysArgs = if args.len > 0: allocCStringArray(args) else: nil
  if sysArgs != nil:
    defer: deallocCStringArray(sysArgs)
  var sysEnv = if args.len > 0: envToCStringArray(env) else: nil
  if sysEnv != nil:
    defer: deallocCStringArray(sysEnv)

  when declared(posix.posix_spawn) and not defined(procsUsePosixFork): # use posix.spawn
    log "using posix spawn"
    var
      attr: posix.Tposix_spawnattr
      fops: posix.Tposix_spawn_file_actions
      mask: posix.Sigset
      flags = posix.POSIX_SPAWN_USEVFORK or posix.POSIX_SPAWN_SETSIGMASK

    checkReturn posix.posix_spawn_file_actions_init(fops)
    checkReturn posix.posix_spawnattr_init(attr)
    checkReturn posix.sigemptyset(mask)
    checkReturn posix.posix_spawnattr_setsigmask(attr, mask)
    # if poDaemon in data.options:   TODO
    #   posix.posix_spawnattr_setpgroup(attr, 0'i32)
    #   flags = flags or posix.POSIX_SPAWN_SETPGROUP
    checkReturn posix.posix_spawnattr_setflags(attr, flags)

    template dup(fd0, fd1): untyped =
      if posix.posix_spawn_file_actions_adddup2(fops, fd0.cint, fd1.cint) != 0:
        raiseOSError(osLastError())

    template close(fd): untyped =
      if posix.posix_spawn_file_actions_addclose(fops, fd.cint) != 0:
        raiseOSError(osLastError())

    for pipe in pipes:
      log "mapping pipes"
      if ParentToChild notin pipe.dir:
        close(pipe.fds[pipeReadIdx])
        if pipe.childFD.isSome:
          dup(pipe.fds[pipeWriteIdx], pipe.childFD.get.cint)
      if ChildToParent notin pipe.dir:
        close(pipe.fds[pipeWriteIdx])
        if pipe.childFD.isSome:
          dup(pipe.fds[pipeReadIdx], pipe.childFD.get.cint)

    # map stdio
    if stdin.isSome:
      log "mapping stdin to " & $stdin.get
      dup(stdin.get, posix.STDIN_FILENO.cint)
    if stdout.isSome:
      log "mapping stdout to " & $stdout.get
      dup(stdout.get, posix.STDOUT_FILENO.cint)
    if stderr.isSome:
      log "mapping stderr to " & $stderr.get
      dup(stderr.get, posix.STDERR_FILENO.cint)

    let currentDir = block:
      if workDir.isSome:
        let currentDir = getCurrentDir()
        setCurrentDir(workDir.get.string)
        currentDir
      else: ""

    # TODO: set limits

    var res = posix.posix_spawn(result.pid.cint, path.cstring, fops, attr, sysArgs, sysEnv)

    checkReturn posix.posix_spawn_file_actions_destroy(fops)
    checkReturn posix.posix_spawnattr_destroy(attr)

    if res != 0'i32: raiseOSError(OSErrorCode(res), path.string)

    if workDir.isSome:
      setCurrentDir(currentDir)

  else: # use posix.fork
    log "using posix fork"

    # a pipe is created so that errors after fork can be propagated back to the parent process
    var errorPipeHandles: array[2, cint]
    checkReturn posix.pipe(errorPipeHandles)
    defer: checkReturn posix.close(errorPipeHandles[pipeReadIdx])

    # fork this process
    # https://pubs.opengroup.org/onlinepubs/9699919799/functions/fork.html
    result.pid.cint = posix.fork()

    if result.impl.pid == 0:
      # this is the new child context
      log "forked child context"
      block NOGC:
        {.push stacktrace: off, profiler: off.}
        # WARNING: NO GC in this section
        # WARNING: All procs called from here MUST be annotated with `stackTrace:off`.

        # Close pipe ends that aren't needed and create duplicate file descriptors.
        # https://pubs.opengroup.org/onlinepubs/9699919799/functions/dup2.html

        template pipeBackErrorAndExit: untyped =
          discard posix.write(errorPipeHandles[pipeWriteIdx], addr posix.errno, sizeof(posix.errno))
          posix.exitnow(1)

        template dup(fd0, fd1): untyped =
          if posix.dup2(fd0.cint, fd1.cint) < 0:
            pipeBackErrorAndExit()

        template close(fd): untyped =
          if posix.close(fd.cint) != 0:
            pipeBackErrorAndExit()

        for pipe in pipes:
          if ParentToChild notin pipe.dir:
            close(pipe.fds[pipeReadIdx])
            if pipe.childFD.isSome:
              dup(pipe.fds[pipeWriteIdx], pipe.childFD.get.cint)
          if ChildToParent notin pipe.dir:
            close(pipe.fds[pipeWriteIdx])
            if pipe.childFD.isSome:
              dup(pipe.fds[pipeReadIdx], pipe.childFD.get.cint)

        close(errorPipeHandles[pipeReadIdx])
        # set the error pipe to close if the `exec*` call succeeds
        if posix.fcntl(errorPipeHandles[pipeWriteIdx], posix.F_SETFD, posix.FD_CLOEXEC) < 0:
          pipeBackErrorAndExit()

        if workDir.isSome:
          if posix.chdir(workDir.get.cstring) < 0:
            pipeBackErrorAndExit()

        # TODO: set limits

        # Replace this process image with another.
        when defined posixUseExecvp:
          var environ {.importc.}: cstringArray
          environ = sysEnv
          if posix.execvp(path.cstring, sysArgs) < 0:
            pipeBackErrorAndExit()
        else:
          if posix.execve(path.cstring, sysArgs, sysEnv) < 0:
            pipeBackErrorAndExit()
        {.pop.}

    # from here onward is the parent context

    checkReturn posix.close(errorPipeHandles[pipeWriteIdx])

    if result.impl.pid < 0:
      # there was an error forking
      raiseOSError(osLastError())

    # Check if the forked process incurred an error after fork.
    # A system's `errno` value will have been written to the error pipe.
    var error: cint
    if posix.read(errorPipeHandles[pipeReadIdx], addr error, sizeof(error)) == sizeof(error):
      raiseOSError(OSErrorCode(error))


proc wait*(process: Proc, events: set[ProcessEventKind]): set[ProcessEventKind] {.raises: [Defect, OSError].} =
  template opts: untyped = 0
  var value: cint
  checkReturn(posix.waitpid(process.pid, value, opts), process.pid)


proc waitForExit*(process: Proc): int {.raises: [Defect, OSError].} =
  var state: cint
  checkReturn(posix.waitpid(process.pid, state, 0), process.pid)
  if posix.WIFEXITED(state) or posix.WIFSIGNALED(state):
    return posix.WEXITSTATUS(state)
