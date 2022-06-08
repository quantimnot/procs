.SUFFIXES:
.SUFFIXES: .nim

.nim:
	nim c $<

all: false \
	true \
	duplex_pipe \
	simplex_writeonly_pipe \
	echo_args \
	echo_stdin \
	handles_sigxcpu \
	ignores_sigxcpu \
	ignores_sigstop \
	long_sleep \
	openfds \
	singleton \
	write_to_stdout \
	write_to_stderr \
	write_to_stdout_stderr \
	blocked_on_full_pipe

.PHONEY: clean
clean:
