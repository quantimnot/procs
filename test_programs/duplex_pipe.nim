import std/syncio

var file: File
doAssert open(file, FileHandle(3), fmReadWrite)

var req: string
let numCharsRead = readChars(file, req)
doAssert numCharsRead > 0
doAssert writeChars(file, req, 0, req.len) == numCharsRead
