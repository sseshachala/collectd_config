#! /usr/bin/env bash

##################################################
#
#  Script to Install Xervmon Server
#  Name				: install.sh
#  Author			: Ashish Melanta
#  Copyright	: Xervmon Inc 2013-2014
#  Usage			: ./install.sh -h
#
##################################################

#### User configuration
CONFIG_MONGO_DIR=/vol/mongodb
CONFIG_GRAPHITE_DIR=/vol/graphite

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
CARBON_DIR="${RESOURCESDIR}/carbon-0.9.10"
GRAPHITE_DIR="${RESOURCESDIR}/graphite-web-0.9.10"
JSONC_DIR="${RESOURCESDIR}/json-c-0.10"
LIBMICROHTTPD_DIR="${RESOURCESDIR}/libmicrohttpd-0.9.22"
MONGOCDRIVER_DIR="${RESOURCESDIR}/mongo-c-driver"
WHISPER_DIR="${RESOURCESDIR}/whisper-0.9.10"
XERVCOLLECTD_DIR="${RESOURCESDIR}/collectd-pw"

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

## Will trigger cleanup if it gets the signals mentioned
trap "CleanUp" SIGQUIT SIGKILL SIGTERM

## Add/Remove Build Tools
function InstallDependencies {
	# All dependencies for a server. Assuming an ubuntu server
	sudo apt-get update
	# build tools
	sudo apt-get -y install git build-essential autoconf libtool scons
	# Python
	sudo apt-get -y install python-pip python-dev python-cairo

	sudo apt-get -y install mongodb python-pymongo
	sudo apt-get -y install python-whisper
	# Apache, php, mysql
	# XXX: Pre-configure mysql root password
	sudo apt-get -y install apache2 php5 php5-dev php5-cli php-pear php5-mysql mysql-server mysql-client
	sudo apt-get -y install libapache2-mod-php5 php5-mysqlnd libapache2-mod-wsgi php5-curl
	sudo apt-get -y install python-django python-mysqldb python-django-tagging python-cairo
	# We install collectd from source, but we can just use the dependencies that exist in apt
	sudo apt-get -y build-dep collectd

	# perfwatch/rrdtool
	sudo apt-get -y install rrdtool
}

function MongoPHP {
	# In 12.04 LTS, there is no php5-mongo package, so use the driver from
	# the mongo client archive
	. /etc/lsb-release
	if `echo "$DISTRIB_RELEASE > 12.04" | bc`; then 
		sudo apt-get -y install php5-mongo
	else
		sudo ${PECLCOMM} install -f mongo
	fi
	PHPINI=/etc/php5/conf.d/mongo.ini
	echo "MESSAGE: Adding mongo.so to the ${PHPINI} file"
	echo -e "; added by xervmon installer\nextension=mongo.so" > sudo tee ${PHPINI}
}

## Compile and Install Mongo Client
function InstallMongoC {
	if (cd ${MONGOCDRIVER_DIR} && scons >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
		echo "MESSAGE: Mongo Client installation succeeded"
	else
		echo "ERROR: Mongo Client install FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		exit 1
	fi
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
xstatus="true"
	# 1. Run the compile related tasks in unison
	if (cd ${XERVCOLLECTD_DIR} && ./build.sh >> ${LOGFILE} 2>&1 && ./configure --enable-top --enable-cpu --enable-rrdtool --enable-write_mongodb --enable-jsonrpc --enable-notify_file --enable-basic_aggregator >> ${LOGFILE} 2>&1 && make >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
	# 2. Run the configuration related tasks
		if (cd ${XERVCOLLECTD_DIR} && cp -i src/types-perfwatcher.db /etc && sudo cp $CONFDIR/init.d-collectd-debian /etc/init.d/collectd && chmod a+x /etc/init.d/collectd && mkdir /etc/collectd/ && cp -i ${CONFDIR}/collectd.conf /etc/collectd); then
			xstatus="true"
		else
			xstatus="false"
		fi
	else
		xstatus="false"
	fi
	if [ ${xstatus} = "false" ]; then
		echo "ERROR: Xervmon Collectd PW installation FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		cd ${XERVCOLLECTD_DIR}/core && make clean
		exit 1
	else
		echo "MESSAGE: Xervmon Collectd PW installation succeeded"
	fi
}

function ConfigureCollectd {
	true
	# TODO: Move writesys into the right place
	# Copy the server configuration file in
	# Create the initial password file

	# 3. Finally, apache related tasks
			if (a2enmod php5 && a2enmod proxy && a2enmod proxy_http && service apache2 restart); then
				echo "MESSAGE: Xervmon Collectd PW installation succeeded"
			else
				xstatus="false"
			fi
}

function ConfigureMongo {
	if [ ! -d $CONFIG_MONGO_DIR ]; then
		echo "Creating mongo configuration directory $CONFIG_MONGO_DIR"
		sudo mkdir -p $CONFIG_MONGO_DIR
		sudo chown mongodb:mongodb $CONFIG_MONGO_DIR
		# TODO: If we change the mongo path, we should delete the old one
	fi
	sudo sed -i "s:^dbpath=.*$:dbpath=$CONFIG_MONGO_DIR:" /etc/mongodb.conf	
	sudo /etc/init.d/mongodb restart
}

## Install Graphite/Carbon/Whisper
function ConfigureCarbon {
	sudo pip install carbon
	sudo pip install graphite-web

	if [ ! -d $CONFIG_GRAPHITE_DIR ]; then
		echo "Creating graphite configuration directory $CONFIG_GRAPHITE_DIR"
		sudo mkdir -p $CONFIG_GRAPHITE_DIR
		#sudo chown _graphite:_graphite $CONFIG_GRAPHITE_DIR
	fi
	cd /opt/graphite/conf
	# TODO: Option carbon configuration file
        # If carbon from apt, config file is elsewhere and there's a
        # init script (change /etc/default), otherwise we need to launch it ourselves
	sudo cp carbon.conf.example carbon.conf
	sudo cp graphite.wsgi.example graphite.wsgi
	sudo chgrp www-data graphite.wsgi
	sudo cp $CONFDIR/storage-schemas.conf .
	
	# apache
	sudo cp $CONFDIR/graphite-vhost.conf /etc/apache2/sites-available/graphite
	sudo a2dissite default
	sudo a2ensite graphite
	sudo /etc/init.d/apache2 reload

	# This makes the wsgi webapp work
	sudo mkdir /etc/apache2/run
	sudo chown -R www-data /opt/graphite/storage/log
	sudo chgrp www-data /opt/graphite/storage
	sudo chmod 775 /opt/graphite/storage

	# manage.py syncdb, etc
	cd /opt/graphite/webapp/graphite
	sudo cp local_settings.py.example local_settings.py
	sudo -u www-data python manage.py syncdb --noinput
}

#################### MAIN ########################
##################################################

#### SANITY CHECKS
# If log file is unwritable, exit.
if [ ! -w ${LOGDIR} ]; then
	echo "${LOGDIR} is unwritable. Please correct." && exit 1
fi

## Uncompress all the required resources for the installation
## These are stored in resources folder
function ExtractResources {
	for lib in ${CARBON_DIR}.tar.gz ${GRAPHITE_DIR}.tar.gz ${JSONC_DIR}.tar.gz ${LIBMICROHTTPD_DIR}.tar.gz ${MONGOCDRIVER_DIR}.tar.gz ${WHISPER_DIR}.tar.gz ${XERVCOLLECTD_DIR}.tar.gz
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

## Check with the user for each component to be installed.
#/usr/bin/clear
echo "   We will now begin installation of various components of Xervmon server"
echo ""
echo "   Order of Installation is as follows:"
echo "     0. Extract Resources"
echo "     1. Install dependencies"
echo "     2. Install and configure mongodb"
echo "     3. Install and configure graphite"
echo "     4. Perfwatcher Libraries"
echo "     5. Xervmon Collectd Server"
echo ""
echo "   MESSAGE: User will be prompted at each stage for approval to proceed"
echo "   MESSAGE: If the installation fails at any point, please refer to the"
echo "   MESSAGE: ${LOGFILE} and make amends and continue with the installation"
echo ""
echo "    Will store Graphite files in $CONFIG_GRAPHITE_DIR (\$CONFIG_GRAPHITE_DIR)"
echo "    and mongodb files in $CONFIG_MONGO_DIR (\$CONFIG_MONGO_DIR)"
echo "    If you want these in a different place, exit now (^C) and change the"
echo "    configuration at the top of this file."

echo "Extracting resources..."
ExtractResources
echo "Done"

echo -n "Proceed to install Mongo Client Driver [y/n]: "
read USER_ANS
if [ ${USER_ANS}X = "yX" ]; then
	InstallMongoC
	USER_ANS="n"
fi

echo -n "Proceed to install Perfwatcher Libraries [y/n]: "
read USER_ANS
if [ ${USER_ANS}X = "yX" ]; then
	InstallJSONC
	InstallLibmicroHTTPD
	USER_ANS="n"
fi

echo -n "Proceed to install Xervmon Collectd Server [y/n]: "
read USER_ANS
if [ ${USER_ANS}X = "yX" ]; then
	InstallXervmonCollectd
	USER_ANS="n"
fi

# Configure MongoDB
# Configure Carbon
# Configure Xervmon Collectd

## Bring us back to the original folder location
cd ${SCRIPTLOC}

