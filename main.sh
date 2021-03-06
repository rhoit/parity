#!/bin/bash

__PKG_NAME__="parity-puzzle"

function Usage {
    echo -e "Usage: $__PKG_NAME__ [OPTIONS] [LEVEL]";
    echo -e "\t-d | --debug [FILE]\tdebug info to file provided"
    echo -e "\t-h | --help\tDisplay this message"
    echo -e "\t-v | --version\tversion information"
}

GETOPT=$(getopt -o d:hv \
                -l debug:,help,version \
                -n "$__PKG_NAME__" \
                -- "$@")

[[ $? != "0" ]] && exit 1

eval set -- "$GETOPT"

export WD="$(dirname $(readlink $0 || echo $0))"
BOARD_SIZE=3
LEVEL=1
exec 3>/dev/null

while true; do
    case $1 in
        -d|--debug)   exec 3>$2; shift 2;;
        -h|--help)    Usage; exit;;
        -v|--version) cat $WD/.version; exit;;
        --)           shift; break
    esac
done

exec 2>&3 # redirecting errors

# extra argument
for arg do
    LEVEL=$arg
    break
done

#----------------------------------------------------------------------
# game LOGIC

header="\e[1m$__PKG_NAME__\e[m (https://github.com/rhoit/parity)"

export WD_BOARD=${WD_BOARD:-"$WD/ASCII-board"}
source $WD_BOARD/board.sh


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
    test "$REPLY" == $'\e' && {
        read -d '' -sn 1 -t1
        test "$REPLY" == "[" && {
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


function check_endgame {
    for ((i=1; i < N; i++)); do
        [[ "${board[0]}" != "${board[$i]}" ]] && return
    done

    board_banner "COMPLETED"
    return 1
}


function status {
	printf "level: %-9s" "$level/$LMAX"
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
    status
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
    let index2="cursor2_y * BOARD_SIZE + cursor2_x"
    let board[$index2]--
    cursor1_x=0 cursor1_y=0
    change=1

    ## game-loop
    while true; do
        let change && {
            board_select_tile_ij $cursor1_y $cursor1_x True
            board_tput_status; status

            let index2="cursor2_y * BOARD_SIZE + cursor2_x"
            let board[index2]+=diff[index2]
            board_vt100_tile=${colors[index2]}
            board_select_tile_ij $cursor2_y $cursor2_x
            board_tile_update_ij $cursor2_y $cursor2_x ${board[$index2]}

            cursor1_x=$cursor2_x
            cursor1_y=$cursor2_y
            let moves++
            change=0
        } #<&-
        check_endgame || return
        key_react
    done
}

declare score=0
trap "board_banner 'GAME OVER'; exit" INT #handle INTERRUPT
N=$((BOARD_SIZE*BOARD_SIZE))
board_init $BOARD_SIZE

LMAX=$(cat $WD/levels | wc -l)
for ((level=LEVEL; level<=$LMAX; level++)); do
    clear
    specs=$(sed -n "${level}p" $WD/levels)
    test -z "$specs" && exit
    unset board_old
    declare moves=0
    >&3 echo level:$level "($specs)"
    echo -e $header
    play_level ${specs[@]}
done
