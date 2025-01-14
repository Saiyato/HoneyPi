#!/bin/bash

#check root
if [ $UID -ne 0 ]
then
 echo "Please run this script as root: sudo honeyPI.sh"
 exit 1
fi

####Disclaimer!###
if whiptail --yesno "Hey Hey! You're about to install honeyPi to turn this Raspberry Pi into an IDS/honeypot. Congratulations on being so clever. This install process will change some things on your Pi. Most notably, it will flush your iptables and turn up logging. Select 'Yes' if you're cool with all that or 'No' to stop now." 20 60
then
  echo "continue"
else
  exit 1
fi

####Change password if you haven't yet###
if [ $SUDO_USER == 'pi' ]
then
 if whiptail --yesno "You're currently logged in as default pi user. If you haven't changed the default password 'raspberry' would you like to do it now?" 20 60
 then
  passwd
 fi
fi

####Install Debian updates ###
if whiptail --yesno "Let's install some updates. Answer 'no' if you are just experimenting and want to save some time (updates might take 15 minutes or more). Otherwise, shall we update now?" 20 60
then
 apt-get update
 apt-get dist-upgrade -y
fi


####Name the host something enticing ###
sneakyname=$(whiptail --inputbox "Let's name your honeyPi something enticing like 'SuperSensitiveServer'. Well maybe not that obvious, but you get the idea. Remember, hostnames cannot contain spaces or most special chars. Best to keep it to just alphanumeric and less thaann 24 characters." 20 60 3>&1 1>&2 2>&3)
echo $sneakyname > /etc/hostname
echo "127.0.0.1 $sneakyname" >> /etc/hosts

####Install PSAD ###
whiptail --infobox "Installing a bunch of software like the log monitoring service and other dependencies...\n" 20 60
#apt-get -y install psad msmtp s-nail msmtp-mta python-twisted iptables-persistent libnotify-bin fwsnort raspberrypi-kernel-headers -y

###Choose Notification Option###
OPTION=$(whiptail --menu "Choose how you want to get notified:" 20 60 5 "email" "Send me an email" "script" "Execute a script" "gpio" "Switch GPIO to high on Raspberry Pi" 3>&2 2>&1 1>&3)
enablescript=N
externalscript=/bin/true
alertingmethod=ALL
# Set check interval in seconds for iptables changes
check=1

case $OPTION in
	email)
		if whiptail --yesno "MSMTP is used for email notifications, setup gmail account using the wizard? 'Yes' to continue or 'No' to exit email setup (you need to set this up manually later)." 20 60
 		then
			cp msmtprc /etc/msmtprc
			emailaddress=$(whiptail --inputbox "This wizard only supports gmails accounts (input is not validated). What's your email address?" 20 60 3>&1 1>&2 2>&3)
			sed -i "s/xusernamex/$emailaddress/g" /etc/msmtprc
			sed -i "s/xfromx/$emailaddress/g" /etc/msmtprc
			
			whiptail --msgbox "Now, create an 'App Password' for your gmail account (google it if you don't know how). Because we don't want to assign your password to any variables, you have to manually edit the smtp configuration file on the next screen. 'AuthUser' is the first part of your email address before the @. Save and exit the editor and I'll see you back here." 20 60			
			pico /etc/msmtprc
			
			whiptail --msgbox "Welcome back! Trying to send a test email, this shouldn't take long..." 20 60			
			echo "Test email from your honeypot." | msmtp -a default $emailaddress
			
			whiptail --msgbox "If you've received the mail, great, if not you should check /etc/msmtprc and fiddle around with the settings to make it work." 20 60
		else
			emailaddress=root@localhost.com
		fi
	;;
	script)
		externalscript=$(whiptail --inputbox "Enter the full path and name of the script you would like to execute when an alert is triggered:" 20 60 3>&1 1>&2 2>&3)
		enablescript=Y
		alertingmethod=noemail
	;;
	gpio)
		enablescript=Y
		alertingmethod=noemail
		externalscript="/usr/bin/python /root/honeyPi/gpio_once.py"
	;;
esac

# Setup PSAD
whiptail --msgbox "Setting up PSAD with notification preferences." 20 60
cp psad.conf /etc/psad/psad.conf
sed -i "s/xhostnamex/$sneakyname/g" /etc/psad/psad.conf
sed -i "s/xemailaddressx/$emailaddress/g" /etc/psad/psad.conf
sed -i "s/xenablescriptx/$enablescript/g" /etc/psad/psad.conf
sed -i "s/xalertingmethodx/$alertingmethod/g" /etc/psad/psad.conf
sed -i "s=xexternalscriptx=$externalscript=g" /etc/psad/psad.conf
sed -i "s/xcheckx/$check/g" /etc/psad/psad.conf


# Finalise installation
whiptail --msgbox "Placing scripts in the right directories." 20 60
mkdir /root/honeyPi
cp gpio*.* /root/honeyPi

# Setting up iptables
iptables --flush
# Disable IGMP flooding
iptables -A INPUT -p igmp -j DROP
iptables -A INPUT -j LOG
iptables -A FORWARD -j LOG

ip6tables -A INPUT -j LOG
ip6tables -A FORWARD -j LOG

# Configuring netfilter
service netfilter-persistent save
service netfilter-persistent restart

# Starting necessary binaries
psad --sig-update
service psad restart
cp mattshoneypot.py /root/honeyPi
(crontab -l 2>/dev/null; echo "@reboot python /root/honeyPi/mattshoneypot.py &") | crontab -
python /root/honeyPi/mattshoneypot.py &
ifconfig
printf "\n \n ok, now reboot and you should be good to go. Then, go portscan this honeyPi and see if you get an alert!\n"

