#! /usr/bin/env bash

##################################################
#
#  Script to Install Xervmon Client
#  Name				: client.sh
#  Author			: Ashish Melanta
#  Copyright	: Xervmon Inc 2013-2014
#  Usage			: ./install.sh -h
#
##################################################

#### Script settings, do not change
SCRIPTLOC=`pwd`
PYTHONCOMM=`which python`
PIPCOMM=`which pip`
PECLCOMM=`which pecl`
USER_ANS="n"

##################################################
#### DEPENDENT VARIABLES

## FILES AND DIRECTORY LOCATIONS
LOGDIR="${SCRIPTLOC}/logs"
LOGFILE="${LOGDIR}/xinstall.log"
RESOURCESDIR="${SCRIPTLOC}/resources"
CONFDIR="${SCRIPTLOC}/conf"
JSONC_DIR="${RESOURCESDIR}/json-c-0.10"
XERVCOLLECTD_DIR="${RESOURCESDIR}/collectd"
LIBMICROHTTPD_DIR="${RESOURCESDIR}/libmicrohttpd-0.9.22"

##################################################
#### FUNCTIONS

## Cleanup mechanism on getting a trap signal
function CleanUp {
	echo "Clean up catching a trap signal"
}

## Usage
function usage {
	echo "Usage: ./install.sh"
}

function doerror {
	echo "ERROR when performing installation. Refer to log ${LOGFILE}"
	exit 1
}

## Will trigger cleanup if it gets the signals mentioned
trap "CleanUp" SIGQUIT SIGKILL SIGTERM

## Add/Remove Build Tools
function InstallDependencies {
	# All dependencies for a server. Assuming an ubuntu server
	sudo apt-get update >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	sudo apt-get -y install git build-essential autoconf libtool >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	# We install collectd from source, but we can just use the dependencies that exist in apt
	sudo apt-get -y build-dep collectd >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
}


## Compile and Install json-c
function InstallJSONC {
	if (cd ${JSONC_DIR} && ./configure --prefix=/usr >> ${LOGFILE} 2>&1 && make >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
		echo "MESSAGE: JSON C installation succeeded"
	else
		echo "ERROR: JSON C installation FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		cd ${JSONC_DIR} && make clean
		exit 1
	fi
}

## Compile and Install libmicrohttpd
function InstallLibmicroHTTPD {
	if (cd ${LIBMICROHTTPD_DIR} && ./configure --prefix=/usr >> ${LOGFILE} 2>&1 && make >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
		echo "MESSAGE: libmicrohttpd installation succeeded"
	else
		echo "ERROR: libmicrohttpd installation FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		cd ${LIBMICROHTTPD_DIR} && make clean
		exit 1
	fi
}

## Compile and Install xervmon-collectd-pw.
function InstallXervmonCollectd {
	cd ${RESOURCESDIR}
	git clone https://github.com/sseshachala/collectd.git
	# 1. Run the compile related tasks in unison
	if (cd ${XERVCOLLECTD_DIR} && ./build.sh >> ${LOGFILE} 2>&1 && CFLAGS="-Wno-error" ./configure --enable-top --enable-cpu --enable-rrdtool --enable-notify_file --enable-basic_aggregator >> ${LOGFILE} 2>&1 && make >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
		echo "MESSAGE: Xervmon Collectd PW installation succeeded"
	else
		echo "ERROR: Xervmon Collectd PW installation FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		exit 1
	fi
}

function ConfigureCollectd {
	cd ${XERVCOLLECTD_DIR}
	sudo cp $CONFDIR/init.d-collectd-debian /etc/init.d/collectd
	sudo chmod a+x /etc/init.d/collectd
	sudo update-rc.d collectd defaults

	sudo cp ${CONFDIR}/collectd-client.conf /opt/collectd/etc/collectd.conf
	sudo cp ${CONFDIR}/system_details.sh /opt/collectd/bin
	sudo chmod +x /opt/collectd/bin/system_details.sh

	sudo service collectd restart
}

#################### MAIN ########################
##################################################

#### SANITY CHECKS

if [ ! -d ${LOGDIR} ]; then
	mkdir ${LOGDIR}
fi
# If log file is unwritable, exit.
if [ ! -w ${LOGDIR} ]; then
	echo "${LOGDIR} is unwritable. Please correct." && exit 1
fi

## Uncompress all the required resources for the installation
## These are stored in resources folder
function ExtractResources {
	for lib in ${JSONC_DIR}.tar.gz ${LIBMICROHTTPD_DIR}.tar.gz
	do
		if [ ! -r ${lib} ]; then
			echo "ERROR: Library, ${lib} is unreadable in ${RESOURCESDIR} folder"
			echo "ERROR: Please download the required lib and then proceed"
		else
			echo "Extracting ${lib}"
			tar xzf ${lib} -C ${RESOURCESDIR}/.
		fi
	done
}

/usr/bin/clear
echo "   We will now begin installation of the Xervmon client."
echo ""
echo "   MESSAGE: If the installation fails at any point, please refer to the"
echo "   MESSAGE: ${LOGFILE} and make amends and continue with the installation"
echo ""

echo "Press [return] to continue"
read

echo "Extracting resources..."
ExtractResources
echo "Done"

echo "MESSAGE: Installing additional dependencies"
InstallDependencies

echo "MESSAGE: Installing collectd"
InstallXervmonCollectd

echo "MESSAGE: Configuring Collectd"
ConfigureCollectd

## Bring us back to the original folder location
cd ${SCRIPTLOC}

