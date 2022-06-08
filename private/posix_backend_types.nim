from std/posix import nil

type
  ImplPID* = posix.Pid
  ImplProcessGroupID* = distinct ImplPID
  ImplFD* = distinct cint

  ProcImpl* = object
