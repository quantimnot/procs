# This program is a test and debug utility.
# It is helpful to list the open file descriptors and resources that are inherited.

import pkg/osstat/process

writeFile("openfds.out", genOpenFilesSummary(getpid()))
