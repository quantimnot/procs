# Microsoft Windows®

import std/winlean
export Handle

type
  ImplPID* = DWORD
  ImplFD* = Handle

type
  ProcImpl* = object
    procHandle*: Handle
    mainThreadHandle*: Handle
    pid*: PID
