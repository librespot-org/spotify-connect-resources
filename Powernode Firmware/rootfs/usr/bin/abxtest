#! /bin/sh
#
# abxtest - simple ABX double-blind testing script
# Copyright (C) 2000-2004 Robert Leslie
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# $Id: abxtest,v 1.18 2004/02/23 21:34:53 rob Exp $
#

min=10
max=20
goal=.05

version="0.15.2 (beta)"
publishyear="2000-2004"
author="Robert Leslie"

usage() {
    echo >&2 "Usage: $0 [-n min] [-m max] [-g goal] A-cmd B-cmd"
    exit $1
}

banner() {
    echo >&2  \
	"ABX Double-Blind Test $version - Copyright (C) $publishyear $author"
}

while [ $# -gt 0 ]
do
    case "$1" in
	--help)
	    usage 0
	    ;;

	--version)
	    banner
	    exit 0
	    ;;

	-n)
	    test $# -gt 1 || usage 1
	    min="$2"
	    shift 2
	    ;;

	-m)
	    test $# -gt 1 || usage 1
	    max="$2"
	    shift 2
	    ;;

	-g)
	    test $# -gt 1 || usage 1
	    goal="$2"
	    shift 2
	    ;;

	--)
	    shift
	    break
	    ;;

	-*)
	    usage 1
	    ;;

	*)
	    break
	    ;;
    esac
done

test $# -eq 2 || usage 1

banner
echo "minimum $min, maximum $max trials"
echo "statistical goal to disprove null hypothesis is p <= $goal"

A="$1"
B="$2"

echo "randomizing ..."

tmp="/tmp/abx.$$"
trap "rm -f $tmp" 0

rand="${RANDOM_FILE:-/dev/random}"

od -t o1 -N "$max" "$rand" >$tmp || exit 2
exec 3<$tmp

actual=""

trial=1
while read <&3 line
do
    set -- $line
    shift

    while [ $# -gt 0 ]
    do
	case $1 in
	    *[0246]) x="A" ;;
	    *[1357]) x="B" ;;

	    *)
		echo >&2 "bad output from od"
		exit 3
		;;
	esac
	shift

	eval x$trial=$x
	actual="$actual$x"

	trial=`expr $trial + 1`
    done
done

exec 3<&-
rm -f $tmp

probability() {
    bc <<EOF

    define f(x) {
	auto i;

	if (x == 0) return (1);

	i = x;
	while (--i > 1) x *= i;

	return (x);
    }

    define c(n, r) {
	return (f(n) / (f(n - r) * f(r)));
    }

    define p(r, n, p) {
	return (c(n, r) * (p ^ r) * ((1 - p) ^ (n - r)));
    }

    define g(r, n) {
	auto p;

	while (r <= n) p += p(r++, n, 0.5);

	return (p);
    }

    scale = 7;
    g($1, $2)
EOF
}

notdisproved() {
    return `bc <<EOF
    if ($1 <= $2) 1
    if ($1 >  $2) 0
EOF`
}

if (echo "testing\c"; echo 1,2,3) | grep c >/dev/null
then
    if (echo -n testing; echo 1,2,3) | sed s/-n/xn/ | grep xn >/dev/null
    then
	n="" c='
'
    else
	n="-n" c=""
    fi
else
    n="" c='\c'
fi

input=""
votes=""
trials=0
correct=0
prob=1

echo

trial=1
while [ $trial -le "$min" ] || {
      [ $trial -le "$max" ] && notdisproved $prob $goal
}
do
    echo $n "trial $trial: $c"
    X=`eval eval echo \\\\\$\\\$x$trial`

    if [ -z "$input" ]
    then
	echo "play [a] / play [b] / play [x] / vote [A] / vote [B] / [stop]"
	echo $n "> $c"
	if read input
	then
	    continue
	else
	    break
	fi
    fi

    case "$input" in
	a|b|x)
	    input=`echo $input | tr abx ABX`
	    echo "playing $input ..."
	    cmd=`eval echo \\\$$input`
	    trap "" 2
	    sh -c "$cmd" 1>/dev/null 2>$tmp
	    status=$?
	    if [ $status -eq 0 -o $status -ge 128 ]
	    then
		rm -f $tmp
		trap - 2
	    else
		cat >&2 $tmp
		exit $status
	    fi
	    input=""
	    ;;

	A|B)
	    echo "voting for $input"
	    eval vote$trial="$input"
	    votes="$votes$input"
	    if [ $input = "`eval echo \\\$x$trial`" ]
	    then
		correct=`expr $correct + 1`
	    fi
	    trials=$trial
	    prob=`probability $correct $trials`
	    trial=`expr $trial + 1`
	    input="x"
	    ;;

	stop)
	    echo "stopping"
	    break
	    ;;

	*)
	    echo "invalid input"
	    input=""
	    ;;
    esac
done

echo
echo "$trials trials completed"
echo "A = $A"
echo "B = $B"

echo
echo "  votes: $votes"
echo " actual: $actual"
echo $n "correct: $correct/$trials$c"

if [ $trials -gt 0 ]
then
    echo $n " (`expr \( $correct \* 1000 / $trials + 5 \) / 10`%)$c"
fi

echo

echo
echo "probability (p) of result being the same as random guesses = $prob"

if notdisproved $prob $goal
then
    echo "failed to disprove null hypothesis (p > $goal)"
    exit 9
else
    echo "null hypothesis disproved (p <= $goal)"
    exit 0
fi
