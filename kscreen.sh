#!/bin/bash
# vim: tabstop=4 shiftwidth=4 softtabstop=4
# kate: tabstop=4 shiftwidth=4 softtabstop=4

# A small script that will spawn several expect sessions on konsole tabs
# Author: Francois Eleouet

usage () {
cat << EOF
This script automates the launch of various tasks in konsole tabs.

Its uses definitions files which defines several tabs following the latter pattern:

TAB some title                                start session definition and tab title
SSH host user password                        connects to remote host with ssh
TELNET host user password [enable password]   connects to remote host with telnet
CMD shell command                             sends commands to the destination shell
END or EXIT                                   end session definition,
   drops to interacative shell after command are issued (END) or close session (EXIT)

By default, it lets the user choose ".session" files in the folder where it's located,
alternatively, these files may be chosen using the following options:
   
Options:
  [-h ]           Print this help and exit
  [-d directory]  Use directory to search for session files rather than script directory
  [-f file]       Use specific session file rather than prompting
  [-e args]       Interpret command list with expect
  (Do not use as is, intended to be recusively called within newly opened tabs)
EOF
exit 1
}

#Expect script that will execute the command list in the new tab
#- after << to ignore tabs, quoted EOF to avoid shell expansions & substitutions
exp_script=$(cat <<- "EOF" 

	#Individual commands are executed here,
	#global avriables are used to check 
	#if expect has already spawned
	#(as spawned process may be either bash, ssh or telnet...)

	proc con_ssh {host user password {enable_pwd ""}} {
		global spawn_id expect_out prompt timeout
		set timeout 5
		if { $spawn_id == ""} {
#			spawn -noecho ssh $user@$host
			spawn -noecho ssh -oStrictHostKeyChecking=no -oCheckHostIP=no $user@$host
		} else {
			expect -re $prompt
			send "ssh $user@$host\r"
		}
		expect {
			"assword: " { send "$password\r" }
			"yes/no)? " { send "yes\r"; exp_continue }
			timeout {	exit }
			eof {	exit }
		}
		if { ${enable_pwd} != ""} {
			send "enable\r"
			expect -re $prompt
			send "enable_pwd\r"
		}
	}

	proc con_telnet {host {user ""} {password ""} {enable_pwd ""}} {
		global spawn_id expect_out prompt timeout
		set timeout 5
		if { $spawn_id == ""} {
			spawn -noecho telnet $host
		} else {
			expect -re $prompt
			send "telnet $host\r"
		}
		expect {
			"sername:" { send "$user\r"; exp_continue }
			"assword: " { send "$password\r" }
			timeout {	exit }
			eof {	exit }
		}
		if { ${enable_pwd} != ""} {
			send "enable\r"
			expect "assword: " { send "$enable_pwd\r" }
		}
	}

	proc exec_cmd {cmdline} {
		global spawn_id expect_out prompt timeout
		if { $spawn_id == ""} {
			spawn -noecho bash
		}
		expect -re $prompt
		send "$cmdline\r"
	}

	set spawn_id ""
	set timeout 10
	set prompt "(%|#|>|\\\$) $"
	#log_user 0

	if { $::argc > 0 } {
		set pos 0
		set prev_cmd 0
		foreach arg $::argv {
			if {[regexp {(^SSH$|^TELNET$|^CMD$|^END$|^EXIT$)} $arg] && [expr $pos > 0]} {
				set arg_count [expr $pos - $prev_cmd - 1]
				switch [lindex $argv $prev_cmd] {
					SSH {
						if [expr {$arg_count >= 3} && {$arg_count <= 4} ] {
							#use {*} to split list as individual strings
							con_ssh {*}[lrange $argv [expr $prev_cmd + 1] [expr $pos - 1]]
						} else { puts "Error: Wrong syntax, use SSH host username password \[enable password\]" }
					}
					TELNET {
						if [expr {$arg_count >= 1} && {$arg_count <= 4}] {
							con_telnet {*}[lrange $argv [expr $prev_cmd + 1] [expr $pos - 1]]
						} else { puts "Error: Wrong syntax, use TELNET host \[username\] \[password\] \[enable password\]" }
					}
					CMD {
						if {$arg_count == 1} {
							exec_cmd [lindex $argv $pos-1]
						} else { puts "Error: Wrong syntax, use CMD \[command\]" }
						#use this if quotes aren't added to command
						#exec_cmd [lrange $argv [expr $prev_cmd + 1] [expr $pos - 1]]
					}
				}
				if {$pos == [expr $argc - 1]} {
					switch [lindex $argv $pos] {
						END {
							if { $spawn_id != ""} {
								interact
							}
						}
						EXIT {
							if { $spawn_id != ""} {
								#in this case, interact and suicide as soon as promt output is matched
								interact -o -re $prompt {
									exec kill [pid]
									exit
								}
							}
						}
						default {
							puts "Error command must finish by END or EXIT"
							exit
						}
					}
				}
				set prev_cmd $pos
			}
			incr pos
		}
	}
	exit 
	EOF
)

#Recursiveley executes commands in the new tab
expect_cmds () {

	#'expect <<- "EOF" "$@"' doesn't works, that's why we use a variable
	expect <(echo "$exp_script") "$@"
	
	#Expect has returned, it's time to close the tab
	cur_tab=$(qdbus org.kde.konsole | awk -v FS="/" '/Sessions/{if($3)print $3}' | while read tab; do
		[ $PPID  -eq  $(qdbus org.kde.konsole /Sessions/$tab processId) ] && echo $tab && break
	done)
	[ $cur_tab -gt 0 ] && qdbus org.kde.konsole /Sessions/$cur_tab sendText exit$'\n'
}

# Sanity check of session file using awk 
# TAB & (END | EXIT) act as delimiters, setting p variable
# which is checked to know if delimiters are consistents
#
# TAB definitions are put in single line, prior to be sent to
# the expect script that will execute them in the new TAB
#
# Syntax errors are printed in stderr fd, which is printed in kdialog
#	(stderr has to be processed before stdout, as it is redirected to stdout by default)
#
# Note1: bash is required for $'\n' concatenation and stderr redirection (doesn't work with sh)
#
# Note2: CMD lines are reformatted, including commands between quotes
# and escaping quotes contained in the command. Thus any special characters
# won't be interpreted when they'll be sent to the new tab
# (anyway, sed "s/'/'\\\''/g" would have been more convenient...)
#
# Note3: sed 's/\(TAB \)\(.*\)\( CMD.*\| SSH.*\)/\3/' could have been used to retrive tab name
# (rather than using an array)
#
# Note4: /\S+.*'$keywords'/ also works to check if there are invalid uses of keywords

parse_file () {
	if [ -f $1 ]; then
		keywords='(\<TAB\>|\<SSH\>|\<TELNET\>|\<CMD\>|\<END\>|\<EXIT\>)'
		#check session file syntax
		awk -v ORS=" " '\
			$1!~/^#/{for(i=2; i<=NF; i++){if($i~/'$keywords'/){
				sub($0,"",$0); print "Line " NR": Invalid use of reserved keyword\n" > "/dev/stderr"}}}
			$1~/^TAB$/{if(p==1){
				print "Line " NR ": Starting session definition without closing the previous one\n" > "/dev/stderr";p=0}
				else {ORS=" "; p=1; print}}
			NF && p && $1!~/^#|'$keywords'/ {
				print "Line " NR": Invalid command, use SSH, TELNET or CMD\n" > "/dev/stderr"}
			$1~/^CMD$/ && p {t=$0; gsub("\047","\047\134\047\047",t); sub("CMD ","",t); print "CMD \047"t"\047"}
			$1~/^SSH$/ && p {if(NF != 4){
				print "Line " NR": SSH takes 3 arguments (hosts, user, password)\n" > "/dev/stderr"}
				else {print}}
			$1~/^TELNET$/ && p {if(NF < 1 || NF > 5){
				print "Line " NR": TELNET takes 1 to 4 arguments (hosts, [user], [password], [enable password])\n" > "/dev/stderr"}
				else {print}}
			$1~/^END$|^EXIT$/{if(p==0){
				print "Line " NR": Closing session definition without opening it\n" > "/dev/stderr"}
				else {ORS="\n"; p=0; print $1}}' $1 \
		2> >(while read err_line; do
			[ -n "$err_line" ] && errors=$errors$'\n'$err_line
		done; [ -n "$errors" ] && kdialog --error "Errors found in file $1:$errors") \
		1> >(while read -r -a cmd_line; do
			#retrive tab name
			for (( i=1; i<=${#cmd_line[@]}; i++ )); do
				[[ "${cmd_line[i]}" =~ $keywords ]] && break
			done
			tab_name="${cmd_line[@]:1:$i-1}"
			#check if tab is not already opened
			if [ $(qdbus org.kde.konsole | awk -v FS="/" '/Sessions/{if($3)print $3}' | \
				xargs -I number qdbus org.kde.konsole /Sessions/number title 1 | grep -c "^$tab_name$") -eq 0 ]; then
				#open new tab and rename it
				tab_num=$(qdbus org.kde.konsole /Konsole newSession)
				sleep 0.1
				qdbus org.kde.konsole /Sessions/$tab_num setTitle 1 "$tab_name" > /dev/null
				tab_args="$script_abs_path -e ${cmd_line[@]:$i}"
				#don t understand why we _have_ to store tab_args in variable prior to execute command...
				#   ^ neither why we can not put quotes within process substitution
				qdbus org.kde.konsole /Sessions/$tab_num sendText "$tab_args"$'\n' >/dev/null
			fi
		done)
	fi
}

				#escape some characters that can't be sent "as is" (especially command redirections)
				#tab_args=$(echo "$script_abs_path -e ${cmd_line[@]:$i}" | sed 's/|/\\|/g')


open_files () {
	kdialog --multiple --separate-output --getopenfilename $1 .session | while read file; do
		parse_file $file
	done
}

# retrieve script absolute path
script_dir=$(cd $(dirname "$0"); pwd)
script_abs_path=$script_dir/$(basename $0)
#script_abs_path=$script_dir/$(echo $0 | sed 's|.*/||')
#or: script_abs_path=$script_dir/$(echo $0 | awk -v FS="/" '{print $NF}')

#check if required programs are installed
if [[ ! -x $(which expect) ]]; then
	echo "expect must be installed"
	exit 1
elif [[ ! -x $(which qdbus) ]]; then
	echo "qdbus must be installed"
	exit 1
fi

#check if konsole is running and start it if needed
$(qdbus org.kde.konsole > /dev/null 2>&1)
if [ $? -ne 0 ]; then
  qdbus org.kde.klauncher /KLauncher exec_blind konsole ""
	while true; do
		[ $(pidof konsole) -ne 0 ] && break
		sleep 0.1
	done
fi

getopts ":d:ef:h" opt
case $opt in
	e)
		shift
		expect_cmds "$@"
		;;
	d)
		[ $# -eq 2 ] && [ -d $2 ] && open_files $2 || usage
		;;
	f)
		[ $# -eq 2 ] && [ -f $2 ] && parse_file $2 || usage
		;;
	h)
		usage
		;;
	\?)
		[ $# -eq 0 ] && [ -d $sessions_dir ] && (open_files $script_dir || true) || usage
		;;
	:)
		echo "Option -$OPTARG requires an argument." >&2
		usage
		;;
esac
