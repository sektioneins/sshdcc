## Security Checker Framework (scframework)
## - common functions used for cli security checker tools
## - to be embedded in the tool's library in order to avoid incompatibilty
##   issues between versions
##
## Copyright 2023 SektionEins GmbH
## 
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
## 
## http://www.apache.org/licenses/LICENSE-2.0
## 
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##

if {[catch {package require Tcl 8.6} err]} { puts stderr "$err\nPlease install Tcl 8.6 or newer"; exit 1 }
if {[catch {
	package require cmdline
	package require fileutil
	package require textutil
} err]} { puts stderr "$err\nPlease install tcllib."; exit 1 }

namespace eval scframework {
namespace export *

## on change, increase version to current date
variable scframework_version "20230216"

proc init_scframework {{source_files {}}} {
	detect_tty
	foreach fn $source_files {
		uplevel #0 source \{[file join $::tool_libdir $fn]\}
	}
}

proc print_banner {} {
	global tcl_platform tool_banner isatty tcl_version
	puts "------------------------------------------------------------------------------"
	puts $tool_banner
	puts "running on $tcl_platform(os) $tcl_platform(osVersion) $tcl_platform(machine) with Tcl $tcl_version [expr {$isatty ? "with" : "without"}] TTY"
	puts "started at [timestamp]"
	puts "------------------------------------------------------------------------------"

}

## wrappers for lsearch
proc in_list {list pattern args} {
	return [expr {[lsearch {*}$args $list $pattern] >= 0}]
}
proc in_list_any {list patternlist args} {
	foreach pattern patternlist {
		if {[lsearch {*}$args $list $pattern] >= 0} {
			return 1
		}
	}
}

## split by word
proc wsplit {str} {
	return [regexp -inline -all -- {[^\s]+} $str]
}

## read file or exit
proc read_file {fn} {
	if {![file readable $fn]} {
		puts stderr "file $fn does not exist or is not readable"
		exit 1
	}
	return [::fileutil::cat $fn]
}

## read data from command or exit
proc read_cmd {cmd} {
	try {
		set f [open "|$cmd"]
	}
	set data [read $f]
	catch {close $f}
	return $data
}

## restrict line length for easier readability and email-compatible copy/paste
proc putx {str {indent 0}} {
	set width 79
	set str [::textutil::adjust $str -justify left -length [expr {$width - $indent}]]
	if {$indent} {
		set str [::textutil::indent $str [string repeat " " $indent]]
	}
	puts $str
}

## return current date and time
proc timestamp {} {
	return [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
}

## parse /etc/group or /etc/passwd and return list of groups/usernames
proc get_groups {fn} {
	return [lmap u [regexp -all -inline -line -- {^.*?:} [fileutil::cat $fn]] {
		string trimright $u {:}
	}]
}

proc detect_tty {} {
	set ::isatty [dict exists [fconfigure stdout] -mode]
}

proc init_color_output {} {
	if {$::params(nc) || !$::isatty} { return "" }
	package require term::ansi::code
	package require term::ansi::code::ctrl
}

proc c {name} {
	if {$::params(nc) || !$::isatty} { return "" }
	switch -exact $name {
		error { set name "cyan" }
		critical { set name "magenta" }
		warning { set name "red" }
		notice { set name "yellow" }
		info { set name "green" }
	}
	foreach prefix {"::term::ansi::code::ctrl::sda_fg" "::term::ansi::code::ctrl::sda_" "::term::ansi::code::ctrl::"} {
		set cmd "$prefix$name"
		if {[info commands $cmd] ne ""} { return [$cmd] }
	}
	return ""
}

proc file_mode {fn} {
	file stat $fn stat
	return $stat(mode)
}

proc check_parent_dir_mode {path mode} {
	set path [file normalize $path]
	set path_components [file split $path]
	for {set i [expr {[llength $path_components]-2}]} {$i >= 0} {incr i -1} {
		set dir [file join {*}[lrange $path_components 0 $i]]
		set ret [expr {[file_mode $dir] & $mode}]
		if  {$ret} { return $ret }
	}
	return 0
}

## CSV output
proc csv_output {csv_file result} {
	if {$csv_file eq ""} { return }
	package require csv

	if {[file exists $csv_file]} {
		puts stderr "CSV file '$csv_file' already exists."
		exit 1
	}
	if {![file writable [file dirname $csv_file]]} {
		puts stderr "Directory not writable: $csv_file"
		exit 1
	}

	puts "writing results to $csv_file"
	set csv [open $csv_file wb]
	puts $csv [csv::join {"No." "Short description" "Description" "Option" "Value" "Filename" "Line no." "Line"}]

	set resultno 0
	foreach severity {error critical warning notice info} {
		foreach entry [lsearch -all -inline -index 1 -exact $result $severity] {
			incr resultno
			puts $csv [csv::join [list $resultno {*}[lmap k {msg desc key value cfgfn lineno line} {dict get $entry $k}]]]
		}
	}
	close $csv
}

##
}
##