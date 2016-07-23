#!/usr/bin/bash

__PKG_NAME__="parity"

function Usage {
    echo -e "Usage: $__PKG_NAME__ [OPTIONS] [LEVEL]";
    echo -e "\t-b | --board\tboard size"
    echo -e "\t-l | --level\tjump to game level"
    echo -e "\t-d | --debug\tdebug file"
    echo -e "\t-h | --help\tDisplay this message"
    echo -e "\t-v | --version\tversion information"
}

TEMP=$(getopt -o b:l:dhv\
              -l board:,level:,debug,help,version\
              -n "$__PKG_NAME__"\
              -- "$@")

if [ $? != "0" ]; then exit 1; fi

eval set -- "$TEMP"

BOARD_SIZE=3
LEVEL=1
exec 3>/tmp/parity
while true; do
    case $1 in
        -b|--board)   BOARD_SIZE=$2; shift 2;;
        -l|--level)   LEVEL=$2; shift 2;;
        -d|--debug)   exec 3>$2; shift 2;;
        -h|--help)    Usage; exit;;
        -v|--version) cat $WD/version; exit;;
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
declare vt100_normal="\e[m"
declare vt100_select="\e[1;33;48;5;24m"


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
        box_board_terminate
        exit
    }

    for ((i=N-1; i > 0; i--)); do
        [ "${board[0]}" != "${board[$i]}" ] && return
    done

    tput cup 9 0; figlet -c -w $COLUMNS "COMPLETED"
    return 1
}

function status {
    tput cup 1 0;
	printf "level: %-9s" "$level/150"
	printf "score: %-9d" "$score"
	printf "moves: %-9d" "$moves"
	echo
}


function play_level { # $1: board
    declare board=( $@ )

    status # TODO FIX status print
    box_board_print $BOARD_SIZE
    box_board_update

    ## game-initials
    index1=0 cursor1_x=0 cursor1_y=0
    index2=0 cursor2_x=0 cursor2_y=0
    let board[index0]--
    level=1
    change=1

    ## game-loop
    while true; do
        let change && {
            board_vt100_colors=$vt100_normal
            let index1=$((cursor1_y*BOARD_SIZE+cursor1_x))
            block_update_ij $cursor1_y $cursor1_x ${board[$index1]}

            let moves++
            status

            board_vt100_colors=$vt100_select
            let index2=$((cursor2_y*BOARD_SIZE+cursor2_x))
            let board[index2]++
            block_update_ij $cursor2_y $cursor2_x ${board[$index2]}

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
echo -e $header
box_board_init $BOARD_SIZE
board_vt100_normal=$vt100_normal

declare moves=0
clear # remove after status logic fix
play_level 1 0 0 1 1 0 1 1 0
