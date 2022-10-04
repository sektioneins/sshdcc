OpenSSHd Security Config Checker
================================

About
-----
SSHDCC can check your OpenSSH server configuration file for security improvements. This can be done either on a live system or remotely.

Requirements
------------

* OpenSSH server configuration file
* Tcl version 8.6 (or later)
* tcllib

Example usage
-------------

Simple first check:
```
$ ./sshdcc
------------------------------------------------------------------------------
This is OpenSSHd Security Config Checker 0.1
  - (c) 2018 SektionEins GmbH / Ben Fuhrmannek - https://sektioneins.de/
  - download -> https://github.com/sektioneins/sshdcc
running on Darwin 17.6.0 x86_64 with Tcl 8.6 with TTY
started at 2018-07-03 13:52:12
------------------------------------------------------------------------------
additional live system checks are enabled
NOTE: No defaults were loaded. For better results, please specify either -d or
-dc. See -h for more help.
scanning file /etc/ssh/sshd_config

## RESULTS ##

(1) [NOTICE] extra environment variable accepted by pattern: LANG
    #> LINE 108: AcceptEnv LANG LC_*
    The default is not to accept any environment variables. Please make sure,
    that this variable pattern is actually required.

(2) [NOTICE] extra environment variable accepted by pattern: LC_*
    #> LINE 108: AcceptEnv LANG LC_*
    The default is not to accept any environment variables. Please make sure,
    that this variable pattern is actually required.

done.
```

Check current system, using ssh defaults as reference. Defaults vary for different SSH versions, so they are not included in the tool. The command 'sshd -f /dev/null -T' prints out the running version's default configuration.

```
./sshdcc -dc0
------------------------------------------------------------------------------
This is OpenSSHd Security Config Checker 0.1
  - (c) 2018 SektionEins GmbH / Ben Fuhrmannek - https://sektioneins.de/
  - download -> https://github.com/sektioneins/sshdcc
running on Darwin 17.6.0 x86_64 with Tcl 8.6 with TTY
started at 2018-07-03 13:54:50
------------------------------------------------------------------------------
additional live system checks are enabled
loading defaults from command sudo sshd -f /dev/null -T
Password: <enter your password for sudo here>
scanning file /etc/ssh/sshd_config

## RESULTS ##

(1) [WARNING] login via any authentication method is allowed
    #> SYSTEM DEFAULT: authenticationmethods any
    It is usually a good idea to restrict authentication methods to those
    actually required, e.g. 'publickey'. Please change this setting.

(2) [NOTICE] using default cipher list
    #> SYSTEM DEFAULT: ciphers
    chacha20-poly1305@openssh.com,aes128-ctr,aes192-ctr,aes256-ctr,aes128-gcm@openssh.com,aes256-gcm@openssh.com
    Depending on the version, SSH's default cipher list may contain really old
    ciphers, likely for compatibility with older versions. Try 'ssh -Q cipher'
    and choose current and secure ciphers as suitable.

(3) [NOTICE] login via password is allowed
    #> SYSTEM DEFAULT: passwordauthentication yes
    Public key based authentication methods are considered much more secure.
    Unless your configuration contains some kind of one-time-password, e.g. via
    PAM, this setting should be changed to 'no'.

(4) [NOTICE] extra environment variable accepted by pattern: LANG
    #> LINE 108: AcceptEnv LANG LC_*
    The default is not to accept any environment variables. Please make sure,
    that this variable pattern is actually required.

(5) [NOTICE] extra environment variable accepted by pattern: LC_*
    #> LINE 108: AcceptEnv LANG LC_*
    The default is not to accept any environment variables. Please make sure,
    that this variable pattern is actually required.

(6) [INFO] using default list of algorithms
    #> SYSTEM DEFAULT: pubkeyacceptedkeytypes
    ecdsa-sha2-nistp256-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519,rsa-sha2-512,rsa-sha2-256,ssh-rsa
    The default is most likely suitable. Otherwise, please check 'ssh -Q key'
    for a list of available algorithms.

(7) [INFO] using default list of algorithms
    #> SYSTEM DEFAULT: hostkeyalgorithms
    ecdsa-sha2-nistp256-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519,rsa-sha2-512,rsa-sha2-256,ssh-rsa
    The default is most likely suitable. Otherwise, please check 'ssh -Q key'
    for a list of available algorithms.

(8) [INFO] using default list of algorithms
    #> SYSTEM DEFAULT: hostbasedacceptedkeytypes
    ecdsa-sha2-nistp256-cert-v01@openssh.com,ecdsa-sha2-nistp384-cert-v01@openssh.com,ecdsa-sha2-nistp521-cert-v01@openssh.com,ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519,rsa-sha2-512,rsa-sha2-256,ssh-rsa
    The default is most likely suitable. Otherwise, please check 'ssh -Q key'
    for a list of available algorithms.

(9) [INFO] using default list of key exchange algorithms
    #> SYSTEM DEFAULT: kexalgorithms
    curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256,diffie-hellman-group14-sha1
    The default may be perfectly fine for you. Otherwise, please check 'ssh -Q
    kex' for a list of available algorithms.

(10) [INFO] using default list of MAC algorithms
    #> SYSTEM DEFAULT: macs
    umac-64-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com,hmac-sha1-etm@openssh.com,umac-64@openssh.com,umac-128@openssh.com,hmac-sha2-256,hmac-sha2-512,hmac-sha1
    This is most likely ok. Check out 'ssh -Q mac' for a list of available
    algorithms to choose from.

done.
```

Now, let's check a remote system, and save the results as CSV file:
```
$ ssh remote
remote$ sudo sshd -f /dev/null -T >defaults.conf
remote$ exit
$ scp remote:defaults.conf .
...
$ scp remote:/etc/ssh/sshd_config .
$ ./sshdcc -f sshd_config -d defaults.conf -ns -csv results.csv
```
