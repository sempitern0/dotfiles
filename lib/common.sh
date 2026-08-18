#!/usr/bin/env bash

# ANSI ESCAPE CODE COLOURS
greenColour='\033[0;32m'
redColour='\033[0;31m'
blueColour='\033[0;34m'
yellowColour='\033[1;33m'
purpleColour='\033[0;35m'
cyanColour='\033[0;36m'
grayColour='\033[0;37m'
endColour='\033[0m'

### DISPLAY INFORMATION FUNCTIONS ###
msg_info() { echo -e "${cyanColour}[INFO]${endColour} $1"; }
msg_success() { echo -e "${greenColour}[OK]${endColour} $1"; }
msg_warn() { echo -e "${yellowColour}[WARN]${endColour} $1"; }
msg_error() { echo -e "${redColour}[ERROR]${endColour} $1" >&2; }
print_separator() { echo -e "${grayColour}--------------------------------------------------${endColour}"; }