## * Microsoft Windows® Process Launch
##
## See Also
## 
## []()

import
  std/[strtabs, tables, winlean],
  ./common


# NOTE: Limiting some resources like memory, can only be done when a process
# is part of a JobObject.
# https://docs.microsoft.com/en-us/windows/win32/procthread/job-objects?redirectedfrom=MSDN

proc exec*(
    path: FilePath,
    args: openArray[string] = [],
    env: openArray[(string, string)] = [],
    workDir = none FilePath,
    pipes: openArray[Pipe] = defaultPipes(),
  ): owned Proc {.raises: [Defect, OSError].} =
  new(result)