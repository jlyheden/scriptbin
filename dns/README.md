Amazon route53 scripts for dynamic dns updates

* nsupdate-route53.sh should be installed into /etc/dhcp3/dhclient-exit-hooks.d (assuming debuntu distro)
* dhcpc-event.sh applies to asuswrt-merlin setups, installs into /jffs/scripts/dhcpc-event

The scripts require valid route53 credentials and domain-config
