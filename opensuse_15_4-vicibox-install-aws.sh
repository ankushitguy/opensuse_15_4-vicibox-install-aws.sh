#!/bin/bash

##### 1) goto AWS and subscribe to this https://aws.amazon.com/marketplace/server/procurement?productId=5535c495-72d4-4355-b169-54ffa874f849
##### 2) select your region and install use instance type as c5a.2xlarge which is 16GB RAM and 8 Core AMD EPYC CPU


### Global node configuration, applicable to any server role

# Export a usable path so things work right
PATH="/sbin:/usr/sbin:/usr/local/sbin:/root/bin:/usr/local/bin:/usr/bin:/bin"
export PATH
cd /tmp # Go somewhere safe

# If we are in debug, then give useful wget and CLI output, otherwise be quiet about it
WGET="wget -nv"
ZYPPER='zypper'
if [ "${0}" == "debug" ]; then
	WGET="wget"
	ZYPPER='zypper'
fi

# Simple check for directory, make if doesn't exist subversion
function checkdir {
	if [ ! -d $1 ]; then
		echo -n " Creating dir $1..."
		mkdir -p $1
		echo "done."
	fi
}

# Checks to see if the file exists in the current directory unless directory is supplied, and then downloads it
function checkget {
	# Check to see if we are supplied a target directory, otherwise assume current directory
	if [ -z "$2" ]; then
		LOCALDIR="$PWD"
	else
		LOCALDIR="$2"
	fi
	
	# Make sure directory exists
	checkdir "$LOCALDIR"
	cd $LOCALDIR
	
	# And now check for our file and download if it's not there
	FILE="${1##*/}"
	if [ ! -f $FILE ]; then
		echo -n " Downloading $1..."
		$WGET $1 -O $PWD/$FILE
		echo "done."
	fi
	
	# If we were provided a file mask, apply it
	if [ ! -z "$3" ]; then
		chmod $3 $PWD/$FILE
	fi
}

# Sometimes the CD gets left in as a repo, so check and remove it
CDTEST=`zypper lr --url | grep cd: | awk '{split($0,a,"|"); print a[1]}'`
if [ ! -z "$CDTEST" ]; then
        echo "Removing CD-Rom repository"
		$ZYPPER rr $CDTEST
fi

# Add repositories
$ZYPPER ar https://download.opensuse.org/repositories/home:/vicidial:/vicibox/openSUSE_Leap_15.4/home:vicidial:vicibox.repo
$ZYPPER ar https://download.opensuse.org/repositories/home:/vicidial:/asterisk-16/openSUSE_Leap_15.4/home:vicidial:asterisk-16.repo
$ZYPPER ar https://download.opensuse.org/repositories/devel:languages:perl/15.4/devel:languages:perl.repo
$ZYPPER refresh
$ZYPPER update
$ZYPPER --gpg-auto-import-keys refresh
$ZYPPER --non-interactive install perl-Module-Install-Repository
$ZYPPER --non-interactive in -t pattern lamp_server
$ZYPPER --non-interactive in home_vicidial:libjansson4
$ZYPPER --non-interactive install asterisk
$ZYPPER --non-interactive in adaptec-firmware aggregate apache2-mod_cband asterisk-dahdi bmon ddclient digitemp extundelete fonts-config git gnu_ddrescue htop iftop iotop iprelay  iptraf-ng jeos-firstboot lame lshw memtest86+ mlocate mpt-firmware mtop mtr mydumper mytop ncftp net-tools-deprecated ngrep-sip nmap numad ntp openr2 OpenIPMI patch pcapsipdump perl-MySQL-Diff perl-Term-ANSIColor phpMyAdmin php7-opcache pico ploticus python-eyeD3 recode sensord sensors sipp shim sngrep sshfs stress-ng sysstat vicibox-dynportal vicibox-firewall vicibox-install vicibox-ssl vsftpd
$ZYPPER --non-interactive up

# Create directories
checkdir /usr/src/astguiclient
checkdir /usr/src/tars
checkdir /srv/mysql/data

# Load SVN
cd /usr/src/astguiclient
svn checkout svn://svn.eflo.net:3690/agc_2-X/trunk

# Populdate locate database since we're in a somewhat sane state
updatedb

# Configure asterisk stuff
checkdir /usr/share/asterisk/sounds
checkdir /usr/share/asterisk/moh
checkdir /var/lib/asterisk
checkdir /usr/share/asterisk/agi-bin
checkdir /etc/asterisk/keys
checkdir /var/spool/asterisk/monitorDONE
chown -R wwwrun /var/spool/asterisk/monitorDONE
ln -s /usr/share/asterisk/agi-bin/ /var/lib/asterisk/agi-bin
ln -s /usr/share/asterisk/sounds/ /var/lib/asterisk/sounds
ln -s /usr/share/asterisk/moh/ /var/lib/asterisk/moh
ln -s /usr/share/asterisk/moh/ /var/lib/asterisk/mohmp3
ln -s /usr/share/asterisk/images /var/lib/asterisk/images
ln -s /usr/share/asterisk/firmware /var/lib/asterisk/firmware
ln -s /usr/share/asterisk/static-http/ /var/lib/asterisk/static-http
sed -i 's+/usr/share/asterisk+/var/lib/asterisk+g' /etc/asterisk/asterisk.conf
sed -i 's/;timestamp/timestamp/' /etc/asterisk/asterisk.conf
sed -i 's/;execincludes = yes/execincludes = no/' /etc/asterisk/asterisk.conf
sed -i 's/;verbose = 3/verbose = 21/' /etc/asterisk/asterisk.conf
sed -i 's/;live_dangerously/live_dangerously/' /etc/asterisk/asterisk.conf
sed -i 's/;enabled=yes/enabled=yes/g' /etc/asterisk/http.conf
sed -i 's/bindaddr=127.0.0.1/bindaddr=0.0.0.0/g' /etc/asterisk/http.conf
sed -i 's/;bindport=8088/bindport=8088/g' /etc/asterisk/http.conf
sed -i 's/;tlsenable=yes/tlsenable=yes/g' /etc/asterisk/http.conf
sed -i 's/;tlsbindaddr=0.0.0.0:8089/tlsbindaddr=0.0.0.0:8089/g' /etc/asterisk/http.conf
sed -i 's+;tlscertfile=</path/to/certificate.pem>+tlscertfile=/etc/apache2/ssl.crt/vicibox.crt+g' /etc/asterisk/http.conf
sed -i 's+;tlsprivatekey=</path/to/private.pem>+tlsprivatekey=/etc/apache2/ssl.key/vicibox.key+g' /etc/asterisk/http.conf
codec-install
modprobe dahdi
/usr/sbin/dahdi_genconf

# Make an entry for ramdrive if it's not already there
if ! [[ `cat /etc/fstab | grep monitor` ]]; then
        /bin/echo "tmpfs   /var/spool/asterisk/monitor       tmpfs      rw,size=6G              0 0" >> /etc/fstab
fi

# Take care of sounds for Asterisk
cd /usr/src/tars
checkget https://downloads.asterisk.org/pub/telephony/sounds/asterisk-core-sounds-en-wav-current.tar.gz /usr/src/tars/
checkget https://downloads.asterisk.org/pub/telephony/sounds/asterisk-extra-sounds-en-wav-current.tar.gz /usr/src/tars
checkget https://downloads.asterisk.org/pub/telephony/sounds/asterisk-moh-opsound-wav-current.tar.gz /usr/src/tars/
cd /usr/share/asterisk/sounds
rm -rf *
/bin/tar -xf /usr/src/tars/asterisk-core-sounds-en-wav-current.tar.gz
/bin/tar -xf /usr/src/tars/asterisk-extra-sounds-en-wav-current.tar.gz
cp /usr/share/vicibox/conf.gsm ./
cp conf.gsm park.gsm
cd /usr/share/asterisk/moh
rm -rf *
/bin/tar -xzf /usr/src/tars/asterisk-moh-opsound-wav-current.tar.gz
/bin/rm CHANGES*
/bin/rm LICENSE*
/bin/rm CREDITS*
/bin/rm .asterisk*
/bin/mkdir /var/lib/asterisk/quiet-mp3
cd /var/lib/asterisk/moh
for each_file in ./*.wav; do
        /usr/bin/sox $each_file /var/lib/asterisk/quiet-mp3/$each_file vol 0.25
done

# Some asterisk fixups
cd /etc/asterisk
echo '' > extensions.ael
rm modules.conf
cp /usr/share/vicibox/modules.conf /etc/asterisk/

# Configure Apache2 and PHP specific stuff
/usr/sbin/a2enmod rewrite
/usr/sbin/a2enmod php7
/usr/sbin/a2enmod status
/usr/sbin/a2enmod mod_socache_shmcb
#/usr/sbin/a2enflag SSL 
cp /usr/share/vicibox/server-tuning.conf /etc/apache2/
cp /usr/share/vicibox/mod_deflate.conf /etc/apache2/conf.d/
cd /etc/apache2/conf.d
if [ -d /etc/apache2/conf.d/manual.conf ]; then
	rm manual.conf
fi
cd /etc/apache2/vhosts.d
#cp /usr/share/vicibox/1111-default*.conf ./
. /etc/sysconfig/clock
sed -i "s+date.timezone = 'UTC'+date.timezone = '$DEFAULT_TIMEZONE'+" /etc/php7/apache2/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 330/" /etc/php7/apache2/php.ini
sed -i "s/max_input_time = 60/max_input_time = 360/" /etc/php7/apache2/php.ini
sed -i "s/; max_input_vars = 1000/max_input_vars = 4000/" /etc/php7/apache2/php.ini
sed -i "s/error_reporting = E_ALL \& \~E_DEPRECATED/error_reporting = E_ALL \& \~E_NOTICE \& \~E_DEPRECATED/" /etc/php7/apache2/php.ini
sed -i "s/short_open_tag = Off/short_open_tag = On/" /etc/php7/apache2/php.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 50M/" /etc/php7/apache2/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 48M/" /etc/php7/apache2/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 256M/" /etc/php7/apache2/php.ini
sed -i "s+date.timezone = 'UTC'+date.timezone = $DEFAULT_TIMEZONE+" /etc/php7/cli/php.ini
sed -i "s/max_execution_time = 30/max_execution_time = 330/" /etc/php7/cli/php.ini
sed -i "s/max_input_time = 60/max_input_time = 360/" /etc/php7/cli/php.ini
sed -i "s/; max_input_vars = 1000/max_input_vars = 4000/" /etc/php7/cli/php.ini
sed -i "s/error_reporting = E_ALL \& \~E_DEPRECATED/error_reporting = E_ALL \& \~E_NOTICE \& \~E_DEPRECATED/" /etc/php7/cli/php.ini
sed -i "s/short_open_tag = Off/short_open_tag = On/" /etc/php7/cli/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 256M/" /etc/php7/cli/php.ini
sed -i 's/;opcache.enable=1/opcache.enable=1/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.memory_consumption=128/opcache.memory_consumption=128/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=16/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=20000/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.max_wasted_percentage=5/opcache.max_wasted_percentage=5/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=1/g' /etc/php7/apache2/php.ini
sed -i 's/;opcache.revalidate_freq=2/opcache.revalidate_freq=10/g' /etc/php7/apache2/php.ini

# Generate self-signed SSL to keep the config from breaking, but a real SSL should be installed here for production
openssl req -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes -out /etc/apache2/ssl.crt/vicibox.crt -keyout /etc/apache2/ssl.key/vicibox.key -subj "/C=US/ST=FL/L=Tampa/O=ViciBox/CN=vicibox.local"

# MySQL stuff
cd /etc
if [ ! -f /etc/my.cnf.orig ]; then
	mv /etc/my.cnf /etc/my.cnf.orig
fi
if [ -f /etc/my.cnf ]; then
	rm /etc/my.cnf
fi
cp /usr/share/vicibox/my.cnf /etc/
checkdir /var/lib/mysql
checkdir /srv/mysql/data
mysql_install_db
chown -R mysql:mysql /var/lib/mysql
chown -R mysql:mysql /srv/mysql
