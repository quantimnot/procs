import std/syncio

var file: File
doAssert open(file, FileHandle(3), fmWrite)
write(file, '$')