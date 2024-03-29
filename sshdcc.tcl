##

## Only a subset of keywords may be used on the lines following a Match keyword. Available keywords are ...
## (... copied from sshd_config manpage)
set match_keywords {AcceptEnv, AllowAgentForwarding, AllowGroups, AllowStreamLocalForwarding, AllowTcpForwarding, AllowUsers, AuthenticationMethods, AuthorizedKeysCommand, AuthorizedKeysCommandUser, AuthorizedKeysFile, AuthorizedPrincipalsCommand, AuthorizedPrincipalsCommandUser, AuthorizedPrincipalsFile, Banner, CASignatureAlgorithms, ChrootDirectory, ClientAliveCountMax, ClientAliveInterval, DenyGroups, DenyUsers, DisableForwarding, ExposeAuthInfo, ForceCommand, GatewayPorts, GSSAPIAuthentication, HostbasedAcceptedAlgorithms, HostbasedAuthentication, HostbasedUsesNameFromPacketOnly, IgnoreRhosts, Include, IPQoS, KbdInteractiveAuthentication, KerberosAuthentication, LogLevel, MaxAuthTries, MaxSessions, PasswordAuthentication, PermitEmptyPasswords, PermitListen, PermitOpen, PermitRootLogin, PermitTTY, PermitTunnel, PermitUserRC, PubkeyAcceptedAlgorithms, PubkeyAuthentication, PubkeyAuthOptions, RekeyLimit, RevokedKeys, RDomain, SetEnv, StreamLocalBindMask, StreamLocalBindUnlink, TrustedUserCAKeys, X11DisplayOffset, X11Forwarding, X11UseLocalhost}
set match_keywords [lmap x [split $match_keywords {,}] {string trim $x}]

## keywords allowed multiple times by design
set multi_keywords {AcceptEnv HostCertificate HostKey ListenAddress PermitListen PermitOpen Port Subsystem}

## global default values to be loaded by -d or -dc cli options
set defaults {}

##

## read file and parse config
proc load_config {fn} {
	return [parse_config [read_file $fn] $fn]
}

## parse config from data and return a list of dicts for each relevant line
proc parse_config {data {cfgfn ""}} {
	set result {}
	set lines [split $data "\n"]
	set lineno 0
	foreach line $lines {
		incr lineno
		set line [string trim $line]

		## empty lines and comments
		if {$line eq ""} { continue }
		if {[regexp -- {^#} $line]} { continue }

		if {![regexp -- {^(.*?)\s+(.*)$} $line -> key value]} {
			puts stderr "WARNING: unknown syntax on line $lineno: $line"
			set ::check_errors 1
			continue
		}

		if {!$::params(ni) && [string equal -nocase $key "Include"]} {
			foreach globpattern [::textutil::splitx $value] {
				foreach inc_fn [lsort [glob -type f -- $globpattern]] {
					lappend result {*}[load_config $inc_fn]
				}
			}
			continue
		}

		lappend result [list key $key value $value line $line lineno $lineno cfgfn $cfgfn]
	}
	return $result
}

## add to result list - internal function to be used within check_file
proc addresult {severity msg desc} {
	upvar entry entry
	upvar result result
	lappend result [list severity $severity msg $msg desc $desc {*}$entry]
}


## map alias options to their counterpart by changing the 'key'
proc map_aliases {cfgdata} {
	set result {}
	foreach entry $cfgdata {
		set key [dict get $entry key]
		switch -nocase -- $key {
			authorizedkeysfile2 { set key "AuthorizedKeysFile" }
			hostdsakey { set key "HostKeyFile" }
			dsaauthentication { set key "PubkeyAuthentication" }
			skeyauthentication { set key "ChallengeResponseAuthentication" }
			keepalive { set key "TCPKeepAlive" }
			verifyreversemapping -
			reversemappingcheck { set key "UseDNS" }
		}
		dict set entry key $key
		lappend result $entry
	}
	return $result
}

## perform security check on file
proc check_file {fn} {
	set result {}
	set ::check_errors 0
	set section "global"

	set cfgdata [load_config $fn]
	set cfgdata [map_aliases $cfgdata]

	## merge with defaults
	set defaults [map_aliases $::defaults]
	set cfgkeys [lmap entry $cfgdata {dict get $entry key}]
	foreach entry $defaults {
		set key [dict get $entry key]
		if {[in_list $cfgkeys $key -exact -nocase]} { continue }
		dict set entry lineno 0
		set cfgdata [linsert $cfgdata 0 $entry]
	}

	## the cfg array will collect the entire configuration for extra tests
	array set cfg {global {}}

	foreach entry $cfgdata {
		## set variables from dict: key, value, line, lineno
		foreach {k v} $entry { set $k $v }

		switch -nocase -- $key {
			AcceptEnv {
				set bad_vars {"LD_LIBRARY_PATH" "DYLD_LIBRARY_PATH" "PATH"}
				foreach env_pattern [wsplit $value] {
					if {[in_list $bad_vars $env_pattern -glob]} {
						addresult critical "dangerous environment variable accepted by pattern: $env_pattern" {From the manual: "Be warned that some environment variables could be used to bypass restricted user environments. For this reason, care should be taken in the use of this directive."}
					} else {
						addresult notice "extra environment variable accepted by pattern: $env_pattern" {The default is not to accept any environment variables. Please make sure, that this variable pattern is actually required.}
					}
				}
			}

			AllowGroups -
			DenyGroups -
			AllowUsers -
			DenyUsers {
				if {!$::params(ns)} {
					switch -nocase -glob -- $key {
						*Groups {
							set groupfile "/etc/group"
							set groupname "group"
						}
						*Users {
							set groupfile "/etc/passwd"
							set groupname "user"
						}
					}
					set patterns [regexp -all -inline -nocase -- {[^,\s]+} $value]
					set all [get_groups $groupfile]
					foreach pattern $patterns {
						if {![in_list $all $pattern -glob]} {
							addresult notice "$groupname pattern does not match any $groupname found in $groupfile: $pattern" {This may or may not be a mistake.}
						}
					}
				}
			}

			AuthenticationMethods {
				set authlists [lmap x [wsplit $value] {split $x {,}}]
				if {[in_list $authlists {any} -exact]} {
					addresult warning "login via any authentication method is allowed" {It is usually a good idea to restrict authentication methods to those actually required, e.g. 'publickey'. Please change this setting.}
				} elseif {[in_list_any $authlists {{keyboard-interactive} {password}} -exact]} {
					addresult notice "login via password is allowed" {Public key based authentication methods are considered much more secure. Unless your configuration contains some kind of one-time-password, e.g. via PAM, this setting should include 'publickey'.}
				}
				if {[in_list $authlists {none} -exact]} {
					addresult notice "passwordless authentication is enabled" {Anonymous access is rarely needed. Please recheck this setting manually.}
				}
			}

			AuthorizedKeysCommand -
			AuthorizedPrincipalsCommand {
				if {$value ne "" && $value ne "none"} {
					addresult info "$key is set to $value" {FYI.}
				}
				if {$value ne "" && $value ne "none" && !$::params(ns)} {
					if {![file exists $value]} {
						addresult notice "$key does not exist" {This will never work.}
					} elseif {![file executable $value]} {
						addresult notice "$key is not executable" {This will never work.}
					} else {
						if {[file_mode $value] & 0022} {
							addresult warning "$key is writable by group or others" {Please change file permissions immediately.}
						}
						if {[check_parent_dir_mode $value 0022]} {
							addresult warning "parent directory is writable by group or others" {Please change file permissions if necessary.}
						}
					}
				}
			}

			AuthorizedKeysCommandUser -
			AuthorizedPrincipalsCommandUser {
				if {$value eq "root"} {
					addresult warning "authorized keys command user is root" {Executing this command as root is most likely not necessary. Please change this user to an unpriviliged user account dedicated to the authorized keys command.}
				}
			}

			CheckMail {
				addresult critical "old SSH version" "$key has been deprecated for a very long time. Please upgrade your SSH installation."
			}

			Ciphers {
				if {$lineno == 0} {
					## default value
					addresult notice "using default cipher list" {Depending on the version, SSH's default cipher list may contain really old ciphers, likely for compatibility with older versions. Try 'ssh -Q cipher' and choose current and secure ciphers as suitable.}
				}
			}

			DebianBanner {
				if {$value eq "yes"} {
					addresult notice "information disclosure / extra version" {With the principle of least privilege in mind, it is a good idea to divulge as little information as possible. Please set this to 'no'.}
				}
			}

			GatewayPorts {
				if {$value eq "yes"} {
					addresult notice "$key is set to $value" {This is usually a bad idea, unless you know what you are doing. Please consider setting this option at least to 'clientspecified' or better yet to 'no'.}
				} elseif {$value eq "clientspecified"} {
					addresult info "$key is net to $value" {Be aware that remote hosts may connect to local ports via port forwarding.}
				}
			}

			GSSAPICleanupCredentials -
			KerberosTicketCleanup {
				if {$value eq "no"} {
					addresult notice "credentials are stored past logout" {Unless there is a specific reason for retaining these credentials, please turn this setting to 'yes'.}
				}
			}

			KexAlgorithms {
				if {$lineno == 0} {
					addresult info "using default list of key exchange algorithms" {The default may be perfectly fine for you. Otherwise, please check 'ssh -Q kex' for a list of available algorithms.}
				}
			}

			KeyRegenerationInterval {
				if {[string is integer $value] && $value > 3600} {
					addresult warning "protocol 1 ephemeral server key regeneration disabled or very long" {This key may be used to decrypt stored sessions. Please do not use protocol 1 in the first place, but if you do anyway, please set this value to at most 3600 (1 hour).}
				}
			}

			HostbasedAcceptedKeyTypes -
			HostKeyAlgorithms -
			PubkeyAcceptedKeyTypes {
				if {$lineno == 0} {
					addresult info "using default list of algorithms" {The default is most likely suitable. Otherwise, please check 'ssh -Q key' for a list of available algorithms.}
				}
			}

			HostbasedAuthentication {
				if {$value eq "yes"} {
					addresult info "host based authentication is enabled" {This authentication method should only be used in trusted environments with similar access levels, e.g. a university ZIP pool or hosts of a cluster computing group.}
				}
			}

			HostbasedUsesNameFromPacketOnly {
				if {$value eq "yes"} {
					addresult notice "host based hostname spoofing may be possible" {This option should only be set if IP to name resolution is not possible for some reason.}
				}
			}

			LoginGraceTime {
				if {[string is integer $value] && ($value > 120 || $value == 0)} {
					addresult warning "login timeout is set rather high: $value" {Not dropping the unauthenticated connection after a short while enables Denial-of-Service attacks.}
				}
			}

			LogLevel {
				switch -glob -- $value {
					QUIET -
					FATAL -
					ERROR {
						addresult info "$key is set to $value" {Silent log levels are ok for production, but they might make debugging just a bit harder in case of problems. The default would be INFO.}
					}
					INFO -
					VERBOSE {}
					DEBUG* {
						addresult warning "$key is set to $value" {The manpage states: "Logging with a DEBUG level violates the privacy of users and is not recommended."}
					}
					default {
						addresult info "unknown log level: $value" {This log level may be invalid.}
					}
				}
			}

			MACs {
				if {$lineno == 0} {
					addresult info "using default list of MAC algorithms" {This is most likely ok. Check out 'ssh -Q mac' for a list of available algorithms to choose from.}
				}
			}

			Match {
				set section "match_$lineno"
			}

			MaxAuthTries {
				if {[string is integer $value] && $value > 20} {
					addresult notice "$key is rather high" {A lot of auth retries make login bruteforcing easier and may lead to Denial-of-Service attacks.}
				}
			}
			
			MaxSessions {
				if {[string is integer $value] && $value > 50} {
					addresult notice "$key is set to $value" {A high number of concurrent sessions may lead to ressource exhaustion and thus to DoS.}
				}
			}

			PasswordAuthentication {
				if {$value eq "yes"} {
					addresult notice "login via password is allowed" {Public key based authentication methods are considered much more secure. Unless your configuration contains some kind of one-time-password, e.g. via PAM, this setting should be changed to 'no'.}
				}
			}

			PermitEmptyPasswords {
				if {$section eq "global" && $value eq "yes"} {
					addresult warning "empty passwords are allowed globally" {Please use Match blocks to allow password-less logins for specific accounts only rather than globally.}
				}
			}

			PermitRootLogin {
				if {$value eq "yes"} {
					addresult warning "root login with password is enabled" {Why?}
				}
			}

			PubkeyAuthentication {
				if {$section eq "global" && $value eq "no"} {
					addresult notice "public key authentication is disabled globally" {Why?}
				}
			}

			Protocol {
				set protocols [split $value {,}]
				if {[in_list $protocols "1"]} {
					addresult warning "protocol 1 enabled" {From the manual: "Protocol 1 suffers from a number of cryptographic weaknesses and should not be used.  It is only offered to support legacy devices."}
				}
			}

			ServerKeyBits {
				if {[string is integer $value] && $value < 2048} {
					addresult warning "protocol 1 server key is rather weak" {Anything below 2048 bits is considered weak. Please don't use protocol 1 anymore, but if you absolutely have to, then set this value to at least 2048, please.}
				}
			}

			StrictModes {
				if {$value eq "no"} {
					addresult warning "ssh does not check file modes" {The manual states: "This is normally desirable because novices sometimes accidentally leave their directory or files world-writable."}
				}
			}

			UsePrivilegeSeparation {
				if {$value eq "no"} {
					addresult critical "sandboxing and privilege separation disabled" {Privilege separation and sandboxing has been the default for years. This protection must remain enabled!}
				} elseif {$value ne "sandbox"} {
					addresult warning "sandboxing disabled" {Sandboxing has been the default for years. This options should be set to 'sandbox'.}
				}
			}

			VersionAddendum {
				if {$value ne "none"} {
					addresult notice "You have a version addendum: $value" {Nice.}
				}
			}

			X11UseLocalhost {
				if {$value eq "no"} {
					addresult notice "X11 is bound to the wildcard address" {This is usually not desired without additional access restrictions.}
				}
			}

			AddressFamily -
			AllowAgentForwarding -
			AllowStreamLocalForwarding -
			AllowTcpForwarding -
			AuthorizedKeysFile -
			AuthorizedPrincipalsFile -
			Banner -
			ChallengeResponseAuthentication -
			ChrootDirectory -
			ClientAliveCountMax -
			ClientAliveInterval -
			Compression -
			DisableForwarding -
			ExposeAuthInfo -
			FingerprintHash -
			ForceCommand -
			GSSAPIAuthentication -
			GSSAPIKeyExchange -
			GSSAPIStrictAcceptorCheck -
			GSSAPIStoreCredentialsOnRekey -
			HostCertificate -
			HostKey -
			HostKeyAgent -
			IgnoreRhosts -
			IgnoreUserKnownHosts -
			IPQoS -
			KbdInteractiveAuthentication -
			KerberosAuthentication -
			KerberosGetAFSToken -
			KerberosOrLocalPasswd -
			ListenAddress -
			MaxStartups -
			PermitListen -
			PermitOpen -
			PermitTTY -
			PermitTunnel -
			PermitUserEnvironment -
			PermitUserRC -
			PidFile -
			Port -
			PrintLastLog -
			PrintMotd -
			RekeyLimit -
			RevokedKeys -
			RDomain -
			RhostsRSAAuthentication -
			RSAAuthentication -
			SetEnv -
			StreamLocalBindMask -
			StreamLocalBindUnlink -
			Subsystem -
			SyslogFacility -
			TCPKeepAlive -
			TrustedUserCAKeys -
			UseDNS -
			UseLogin -
			UsePAM -
			X11DisplayOffset -
			X11Forwarding -
			XAuthLocation {
				## nothing to see here.
			}

			default {
				addresult warning "unknown option '$key'" "Unknown options can be a typo in the configuration or it may be an unsupported feature of a new or custom SSH version"
			}
		}

		## collect configuration
		set hkey [string tolower $key]

		if {[in_list $::multi_keywords $key -exact -nocase]} {
			dict lappend cfg($section) $key $value
		} else {
			if {[info exists cfg($section)] && [dict exists $cfg($section) $hkey]} {
				addresult warning "multiple occurrences of '$key'" {This setting overwrites a previous setting.}
			}
			dict set cfg($section) $hkey $value
		}


		## extra per-line checks
		if {$section ne "global"} {
			## we are in a Match section
			if {$hkey ne "match" && ![in_list $::match_keywords $key -exact -nocase]} {
				addresult warning "option is not allowed within a Match section" {This will not work.}
			}
		}
	}

	## extra checks

	## Match sections (or the global section) with restrictions, e.g. SFTP and ForceCommand
	## This test assumes distinct match blocks containing all relevant options.
	## Configurations with multiple combined match blocks will likely produce false positives here.
	foreach {section entries} [array get cfg] {
		## set $line and $lineno for result output
		if {[regexp -- {^match_(\d+)$} $section -> lineno]} {
			foreach entry $cfgdata {
				if {[dict get $entry lineno] == $lineno} {
					set line [dict get $entry line]
					break
				}
			}
		} else {
			set lineno 1
			set line "(global section)"
		}

		## ForceCommand set? -> restricted block.
		set forcecommand ""
		if {[dict exists $entries forcecommand]} {
			set forcecommand [dict get $entries forcecommand]
		}
		if {$forcecommand ne "" && $forcecommand ne "none"} {
			## check for chroot in SFTP environment
			set chrootdirectory "none"
			if {[dict exists $entries chrootdirectory]} { set chrootdirectory [dict get $entries chrootdirectory] }

			set note_false_positive {Note: This test only checks for restrictions within each Match block, not applying several blocks at once, so this issue may be a false positive.}
			if {[string match -nocase "*sftp*" $forcecommand] && $chrootdirectory eq "none"} {
				addresult warning "SFTP without chroot" "Using chroot as additional safeguard for SFTP servers is highly recommended. $note_false_positive"
			}

			## check for common restrictions
			set restricting_keywords {AllowAgentForwarding AllowStreamLocalForwarding AllowTcpForwarding PermitTTY PermitTunnel PermitUserEnvironment PermitUserRC X11Forwarding}
			set restrictcheck_results {}
			foreach seckey $restricting_keywords {
				set hseckey [string tolower $seckey]
				## looking for value to current keyword...
				if {[dict exists $entries $hseckey]} {
					## get value from Match block
					set secvalue [dict get $entries $hseckey]
				} elseif {$section ne "global" && [info exists cfg($section)] && [dict exists $cfg($section) $hseckey]} {
					## get value from global section or default
					set secvalue [dict get $cfg($section) $hseckey]
				} else {
					## assume the insecure value
					set secvalue yes
				}
				if {$secvalue eq "yes"} {
					lappend restrictcheck_results $seckey
				}
			}
			if {$restrictcheck_results ne {}} {
				addresult warning "restricted block with insufficient restrictions" "The following settings were found to be enabled within a restricted environment: [join $restrictcheck_results ", "]. $note_false_positive Also, restrictions may be set using authorized_keys options, e.g. by putting 'restrict' in front of all relevant keys."
			}
		}
	}

	if {!$::params(ns)} {
		## check /etc/ssh/sshd_config owner/permissions
		if {[file_mode $::params(f)] & 0022} {
			addresult warning "$::params(f) is writable by group or others" {Please change file permissions immediately.}
		}
	}


	return $result
}


## CLI

print_banner
# puts "------------------------------------------------------------------------------"
# puts "This is the OpenSSHd Security Config Checker v$sshdcc_version"
# puts "  (c) 2018-2023 SektionEins GmbH / Ben Fuhrmannek - https://sektioneins.de/"
# puts "  https://github.com/sektioneins/sshdcc"
# puts "running on $tcl_platform(os) $tcl_platform(osVersion) $tcl_platform(machine) with Tcl $tcl_version [expr {$isatty ? "with" : "without"}] TTY"
# puts "started at [timestamp]"
# puts "------------------------------------------------------------------------------"

set options {
	{f.arg "/etc/ssh/sshd_config" "scan file"}
	{ns "do not check this system's live configuration (disables additional checks)"}
	{ni "do not resolve Include directives"}
	{d.arg "" "load SSH default config valuas from file"}
	{dc.arg "" "load SSH default config from command"}
	{dc0 "load SSH default config from command 'sudo sshd -f /dev/null -T'"}
	{csv.arg "" "save results to CSV file"}
	{noout "do not print results"}
	{nc "no color output on tty"}
}

set usage ": $argv0 \[options]\noptions:"
try {
	array set params [::cmdline::getoptions argv $options $usage]
} on error {result} {
	puts $result
	puts "## EXAMPLES"
	puts "\nCheck current system:"
	puts "  HERE->$ $argv0 -dc 'sudo sshd -f /dev/null -T'"
	puts "\nCheck configuration copied from other system:"
	puts "  REMOTE$ sudo sshd -f /dev/null -T >defaults.conf"
	puts "  ... now copy sshd_config and defaults.conf to some other machine ..."
	puts "  OTHER-$ $argv0 -f sshd_config -d defaults.conf -ns"
	exit 1
}

init_color_output

## info

puts "additional live system checks are [expr {$params(ns) ? {disabled} : {enabled}}]"

## defaults

if {$params(dc0)} {
	set params(dc) {sudo sshd -f /dev/null -T}
}
if {$params(d) ne ""} {
	puts "loading defaults from $params(d)"
	set defaults [load_config $params(d)]
} elseif {$params(dc) ne ""} {
	puts "loading defaults from command '$params(dc)'"
	set defaults [parse_config [read_cmd $params(dc)]]
} else {
	putx "NOTE: No defaults were loaded. For better results, please specify either -d or -dc. See -h for more help."
}

## SCAN

puts "scanning file $params(f)"
set result [check_file $params(f)]

## OUTPUT

if {$check_errors} {
	putx "NOTE: There were errors during processing. Please check your configuration file for syntax errors."
}

if {!$params(noout)} {
	puts "\n## RESULTS ##\n"
	if {[llength $result] == 0} {
		putx "There are no findings regarding your configuration file, not even comments. This is highly unusual."
	} else {
		set resultno 0
		foreach severity {critical warning notice info} {
			foreach entry [lsearch -all -inline -index 1 -exact $result $severity] {
				foreach k {msg desc key value cfgfn line lineno} {
					set $k [dict get $entry $k]
				}
				#
				incr resultno
				puts "[c bold]($resultno)[c reset] \[[c $severity][string toupper $severity][c default]\] [c bold]$msg[c reset]"
				if {$lineno > 0} {
					putx "[c italic]#> $cfgfn LINE $lineno: $line[c reset]" 4
				} else {
					putx "[c italic]#> SYSTEM DEFAULT: $line[c reset]" 4
				}
				putx $desc 4
				puts ""
			}
		}
	}
}

## CSV output
csv_output $params(csv) $result

puts "done."
if {$check_errors} { exit 1 }
