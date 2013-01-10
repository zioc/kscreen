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