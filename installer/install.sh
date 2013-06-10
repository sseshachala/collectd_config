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

##################################################
#### DEPENDENT VARIABLES

## FILES AND DIRECTORY LOCATIONS
LOGDIR="${SCRIPTLOC}/logs"
LOGFILE="${LOGDIR}/xinstall.log"
RESOURCESDIR="${SCRIPTLOC}/resources"
CONFDIR="${SCRIPTLOC}/conf"
JSONC_DIR="${RESOURCESDIR}/json-c-0.10"
LIBMICROHTTPD_DIR="${RESOURCESDIR}/libmicrohttpd-0.9.22"
XERVCOLLECTD_DIR="${RESOURCESDIR}/collectd"

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
	# build tools
	sudo apt-get -y install git build-essential autoconf libtool scons >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	# Python
	sudo apt-get -y install python-pip python-dev python-cairo >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi

	sudo apt-get -y install mongodb python-pymongo >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	# Apache, php, mysql
	sudo debconf-set-selections <<< 'mysql-server-5.5 mysql-server/root_password password strangehat' >> ${LOGFILE} 2>&1
	sudo debconf-set-selections <<< 'mysql-server-5.5 mysql-server/root_password_again password strangehat' >> ${LOGFILE} 2>&1
	sudo apt-get -y install apache2 php5 php5-dev php5-cli php-pear mysql-server mysql-client >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	sudo apt-get -y install libapache2-mod-php5 php5-mysqlnd libapache2-mod-wsgi php5-curl >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	sudo apt-get -y install python-django python-mysqldb python-django-tagging python-cairo >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	# We install collectd from source, but we can just use the dependencies that exist in apt
	sudo apt-get -y build-dep collectd >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi

	# perfwatch/rrdtool
	sudo apt-get -y install rrdtool >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	echo "MESSAGE: Set MySQL Server password to strangehat"
}

function MongoPHP {
	sudo pecl install -f mongo >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	PHPINI=/etc/php5/conf.d/mongo.ini
	echo "MESSAGE: Adding mongo.so to the ${PHPINI} file"
	echo -e "; added by xervmon installer\nextension=mongo.so" | sudo tee ${PHPINI}
}

## Compile and Install Mongo Client
function InstallMongoC {
	cd $RESOURCESDIR
	git clone https://github.com/mongodb/mongo-c-driver.git
	cd mongo-c-driver
	git fetch --tags
	git checkout v0.7.1
	scons >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	sudo ldconfig
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
	cd $RESOURCESDIR
	git clone https://github.com/sseshachala/collectd.git
	# 1. Run the compile related tasks in unison
	if (cd ${XERVCOLLECTD_DIR} && ./build.sh >> ${LOGFILE} 2>&1 && CFLAGS="-Wno-error" ./configure --enable-top --enable-cpu --enable-rrdtool --enable-write_mongodb  --enable-notify_file --enable-basic_aggregator >> ${LOGFILE} 2>&1 && make >> ${LOGFILE} 2>&1 && sudo make install >> ${LOGFILE} 2>&1) ; then
		echo "MESSAGE: Xervmon Collectd installation succeeded"
	else
		echo "ERROR: Xervmon Collectd installation FAILED"
		echo "ERROR: Please refer to log, ${LOGFILE}, for more details"
		exit 1
	fi
}

function ConfigureCollectd {
	cd ${XERVCOLLECTD_DIR}
	# sudo cp -i src/types-perfwatcher.db /etc
	sudo cp $CONFDIR/init.d-collectd-debian /etc/init.d/collectd
	sudo chmod a+x /etc/init.d/collectd
        sudo update-rc.d collectd defaults

	sudo cp ${CONFDIR}/collectd-server.conf /opt/collectd/etc/collectd.conf

	echo "xervmon:xervmon" | sudo tee /opt/collectd/etc/collectd.passwd
	sudo mkdir -p /opt/collectd/share/collectd/python
	sudo cp ${CONFDIR}/writesys.py /opt/collectd/share/collectd/python

	sudo a2enmod php5
	sudo a2enmod proxy
	sudo a2enmod proxy_http
	sudo service apache2 restart
	sudo service collectd restart
}

function ConfigureMongo {
	if [ ! -d $CONFIG_MONGO_DIR ]; then
		echo "Creating mongo configuration directory $CONFIG_MONGO_DIR"
		sudo mkdir -p $CONFIG_MONGO_DIR
		sudo chown mongodb:mongodb $CONFIG_MONGO_DIR
		OLDPATH=`awk 'BEGIN{FS="="} /^dbpath/ {print $2}' /etc/mongodb.conf`
		sudo rm -rf $OLDPATH
	fi
	sudo sed -i "s:^dbpath=.*$:dbpath=$CONFIG_MONGO_DIR:" /etc/mongodb.conf
	sudo service mongodb restart
}

## Install Graphite/Carbon/Whisper
function ConfigureCarbon {
	sudo pip install carbon whisper >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi
	sudo pip install graphite-web >> ${LOGFILE} 2>&1
	if [ $? -ne 0 ]; then doerror; fi

	if [ ! -d $CONFIG_GRAPHITE_DIR ]; then
		echo "Creating graphite configuration directory $CONFIG_GRAPHITE_DIR"
		sudo mkdir -p $CONFIG_GRAPHITE_DIR
	fi
	cd /opt/graphite/conf

	sudo cp $CONFDIR/init.d-carbon-cache /etc/init.d/carbon-cache
	sudo chmod a+x /etc/init.d/carbon-cache
        sudo update-rc.d carbon-cache defaults
	sudo service carbon-cache start

	sudo cp $CONFDIR/carbon.conf.example carbon.conf
	sudo cp graphite.wsgi.example graphite.wsgi
	sudo chgrp www-data graphite.wsgi
	sudo cp $CONFDIR/storage-schemas.conf .

	sudo sed -i "s:#LOCAL_DATA_DIR#:$CONFIG_GRAPHITE_DIR/whisper/:" /opt/graphite/conf/carbon.conf
	sudo sed -i "s:#STORAGE_DIR#:$CONFIG_GRAPHITE_DIR:" /opt/graphite/conf/carbon.conf
	sudo cp /opt/graphite/webapp/graphite/local_settings.py.example /opt/graphite/webapp/graphite/local_settings.py
	sudo sed -i "s:^#WHISPER_DIR.*$:WHISPER_DIR='$CONFIG_GRAPHITE_DIR/whisper':" /opt/graphite/webapp/graphite/local_settings.py

	# apache
	sudo cp $CONFDIR/graphite-vhost.conf /etc/apache2/sites-available/graphite
	sudo cp $CONFDIR/xervmon.passwd /etc/apache2/
	sudo a2dissite default
	sudo a2ensite graphite
	sudo /etc/init.d/apache2 reload

	# This makes the wsgi webapp work
	sudo mkdir -p /etc/apache2/run
	sudo chown -R www-data /opt/graphite/storage/log
	sudo chgrp www-data /opt/graphite/storage
	sudo chmod 775 /opt/graphite/storage

	# manage.py syncdb, etc
	cd /opt/graphite/webapp/graphite
	sudo -u www-data python manage.py syncdb --noinput
}

#################### MAIN ########################
##################################################

#### SANITY CHECKS
if [ ! -d ${LOGDIR} ]; then
	mkdir -p ${LOGDIR}
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
echo "   We will now begin installation of various components of Xervmon server"
echo "   If you only want to install some of the packages add them as arguments:"
echo "   - mongodb"
echo "   - graphite"
echo "   - collectd"
echo "   e.g. ./install.sh mongodb graphite"
echo "   add no arguments to install all packages"
echo ""
echo "   MESSAGE: If the installation fails at any point, please refer to the"
echo "   MESSAGE: ${LOGFILE} and make amends and continue with the installation"
echo ""
echo "    Will store Graphite files in $CONFIG_GRAPHITE_DIR (\$CONFIG_GRAPHITE_DIR)"
echo "    and mongodb files in $CONFIG_MONGO_DIR (\$CONFIG_MONGO_DIR)"
echo "    If you want these in a different place, exit now (^C) and change the"
echo "    configuration at the top of this file."


echo "Press [return] to continue"
read


# Check for arguments. If no arguments, we install everything, otherwise
# we only install the args that have been provided
if [ $# -eq 0 ]; then
    args="graphite mongodb collectd"
else
    args="$@"
fi

echo "Extracting resources..."
ExtractResources
echo "Done"

echo "MESSAGE: Installing additional dependencies"
InstallDependencies

for a in $args; do
    if [ $a == "mongodb" ]; then
        echo "MESSAGE: Installing Mongo php drivers"
        MongoPHP

        echo "MESSAGE: Installing Mongo drivers"
        InstallMongoC

        echo "MESSAGE: Installing Mongodb"
        ConfigureMongo
    fi

    if [ $a == "graphite" ]; then
        echo "MESSAGE: Installing carbon"
        ConfigureCarbon
    fi

    if [ $a == "collectd" ]; then
        echo "MESSAGE: Installing perfmon dependencies"
        InstallJSONC
        InstallLibmicroHTTPD

        echo "MESSAGE: Installing collectd"
        InstallXervmonCollectd

        echo "MESSAGE: Configuring Collectd"
        ConfigureCollectd
    fi

done

## Bring us back to the original folder location
cd ${SCRIPTLOC}

