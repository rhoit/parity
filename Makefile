PKG_NAME = parity

pop:
	gnome-terminal -e "./main.sh" --working-directory=${shell pwd}

check-levels:
	NOPLAY=1 gnome-terminal -e "./main.sh" --working-directory=${shell pwd}

check-color:
	gnome-terminal -e "./main.sh 51" --working-directory=${shell pwd}
