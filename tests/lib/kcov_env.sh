# shellcheck shell=bash
# What tests/test_lib.sh sources under kcov's PS4 method (tests/coverage.sh's
# only one): a PS4 of hi's own, through a $BASH_ENV that does what kcov's does
# for every bash child - turns xtrace on with it.
#
# kcov's own, `kcov@${BASH_SOURCE}@${LINENO}@`, loses lines two ways. A bare
# ${BASH_SOURCE} is unset at a `bash -c`'s top level, so a child there under
# `set -u` died of its own trace, and a case passed or failed on the tracer
# (a suite that dodged it with `BASH_ENV=''` dropped the child's lines out of
# the report instead). And kcov 43 reads a trace line's quotes to follow a
# string across lines: a command whose trace holds an odd count of them - an
# array literal with an apostrophe in an element, `A=("a's")`, which xtrace
# prints unescaped - leaves it "inside a string", and every record after it in
# that process is swallowed. scripts/configure.sh's presets did that to every
# install.sh run, which read 33% under kcov and 98 under bashcov. Under bash
# 5.3 a traced value holding a quote and a newline does the same
# (tests/coverage.sh's header has the probe).
#
# So the record ends at the line number, and the command it traces goes on a
# line of its own after `hi-xtrace: `: kcov counts quotes only on a line naming
# kcov@, so no command text can move it, and tests/coverage.sh drops those
# lines from what kcov passes through. xtrace stays off while PS4 is set: a
# traced command naming `kcov@` and a non-numeric line is read as a record.
{ set +x; } 2>/dev/null
_hi_kcov_env="$_HI_TEST_ROOT/kcov-env.sh"
PS4=$'kcov@${BASH_SOURCE-}@${LINENO}@\nhi-xtrace: '
printf 'PS4=%q\nset -x\n' "$PS4" >"$_hi_kcov_env"
export BASH_ENV="$_hi_kcov_env"
unset _hi_kcov_env
set -x
