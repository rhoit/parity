#!/usr/bin/bash

__PKG_NAME__="parity-puzzle"
__VERSION__="1.0"

function Usage {
    echo -e "Usage: $__PKG_NAME__ [OPTIONS] [LEVEL]";
    echo -e "\t-d | --debug\tdebug file"
    echo -e "\t-h | --help\tDisplay this message"
    echo -e "\t-v | --version\tversion information"
}

TEMP=$(getopt -o d:hv\
              -l debug:,help,version\
              -n "$__PKG_NAME__"\
              -- "$@")

if [ $? != "0" ]; then exit 1; fi

eval set -- "$TEMP"

BOARD_SIZE=3
LEVEL=1
exec 3>/tmp/parity
while true; do
    case $1 in
        -d|--debug)   exec 3>$2; shift 2;;
        -h|--help)    Usage; exit;;
        -v|--version) echo $__VERSION__; exit;;
        --)           shift; break
    esac
done

# extra argument
for arg do
    LEVEL=$arg
    break
done

#----------------------------------------------------------------------
# game LOGIC

header="$__PKG_NAME__ (https://github.com/rhoit/parity)"

export WD="$(dirname $(readlink $0 || echo $0))"
export WD_BOARD=$WD/ASCII-board
source $WD_BOARD/board.sh
declare ESC=$'\e' # escape byte

function cursor_move { # $1: direction
    local direction=$1

    cursor2_x=$cursor1_x
    cursor2_y=$cursor1_y

    case $direction in
        u) let cursor2_y--;;
        d) let cursor2_y++;;
        l) let cursor2_x--;;
        r) let cursor2_x++;;
    esac

    (( cursor2_x < 0 )) && let cursor2_x=0
    (( cursor2_y < 0 )) && let cursor2_y=0
    (( cursor2_x >= $BOARD_SIZE )) && let cursor2_x=BOARD_SIZE-1
    (( cursor2_y >= $BOARD_SIZE )) && let cursor2_y=BOARD_SIZE-1

    if [[ $cursor1_x != $cursor2_x ]] || [[ $cursor1_y != $cursor2_y ]]; then
        >&3 echo "cursor: ($cursor1_x, $cursor1_y) → ($cursor2_x, $cursor2_y) index:$index2"
        change=1
    fi
}


function key_react {
    read -d '' -sn 1
    test "$REPLY" = "$ESC" && {
        read -d '' -sn 1 -t1
        test "$REPLY" = "[" && {
            read -d '' -sn 1 -t1
            case $REPLY in
                A) cursor_move u;;
                B) cursor_move d;;
                C) cursor_move r;;
                D) cursor_move l;;
            esac
        }
    }
}


function figlet_wrap {
    > /dev/null which figlet && {
        /usr/bin/figlet $@
        return
    }

    shift 3
    echo $*
    echo "install 'figlet' to display large characters."
}


function check_endgame { # $1: end game
    let "$1" && {
        tput cup $offset_figlet_y 0; figlet_wrap -c -w $COLUMNS $status
        board_terminate
        exit
    }

    for ((i=N-1; i > 0; i--)); do
        [ "${board[0]}" != "${board[$i]}" ] && return
    done

    tput cup 9 0; figlet -c -w $COLUMNS "COMPLETED"
    return 1
}

function status {
	printf "level: %-9s" "$level/150"
	printf "score: %-9d" "$score"
	printf "moves: %-9d" "$moves"
	echo
}


function play_level { # $1:cursor_x $2:cursor:y $* board
    ## get-game-specs
    cursor2_x=$1; shift
    cursor2_y=$1; shift

    local index=0
    for arg in $@; do # getting the tile colors
        local num=${arg/[a-z]/}
        declare board[$index]=$num
        case ${arg/$num/} in
            b) declare colors[$index]="\e[1m" diff[$index]=-1;;
            w) declare colors[$index]="\e[1;30;47m" diff[$index]=1;;
            *) declare diff[$index]=1;;
        esac
        let index++
    done

    ## create board
    status # TODO FIX status print
    board_print $BOARD_SIZE
    board_update

    test -z $NOPLAY || {
        echo
        echo "PRESS ENTER TO SEE NEXT LEVEL"
        board_vt100_tile=${colors[index2]}
        board_select_tile_ij $cursor2_y $cursor2_x
        read
        return 1
    }

    ## set-loop variables
    let index2=$((cursor2_y*BOARD_SIZE+cursor2_x))
    let board[$index2]--
    cursor1_x=0 cursor1_y=0
    change=1

    ## game-loop
    while true; do
        let change && {
            board_select_tile_ij $cursor1_y $cursor1_x True

            let moves++
            tput cup 1 0; status

            let index2=$((cursor2_y*BOARD_SIZE+cursor2_x))
            let board[index2]+=diff[index2]
            board_vt100_tile=${colors[index2]}
            board_select_tile_ij $cursor2_y $cursor2_x
            board_tile_update_ij $cursor2_y $cursor2_x ${board[$index2]}

            cursor1_x=$cursor2_x
            cursor1_y=$cursor2_y
            change=0
        } #<&-
        check_endgame || return
        key_react
    done
}

declare score=0

trap "check_endgame 1; exit" INT #handle INT signal
let N="BOARD_SIZE * BOARD_SIZE"
board_init $BOARD_SIZE

for ((level=LEVEL; level<150; level++)); do
    clear # remove after status logic fix
    specs=$(sed -n "${level}p" $WD/levels)
    test -z "$specs" && exit
    unset board_old
    declare moves=0
    >&3 echo level:$level "($specs)"
    echo -e $header
    play_level ${specs[@]}
done
