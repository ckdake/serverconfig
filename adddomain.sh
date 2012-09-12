#!/bin/bash
#
# hosting site addition tool
#
# 2008.03.07 - first draft (Chris Kelly)
#

echo "About to add a new website, ctrl-c now to abort!"

echo -n "site name: "
read SITENAME

echo -n "user name: "
read USERNAME

echo -n "use php?  1 for yes: "
read USEPHP

echo -n "use mysql? db name for yes, blank for no: "
read MYSQLDB

echo -n "alias? name for yes, blank for no: "
read VHOSTALIAS

echo "-----------------"

WEBDIR="/var/www/${SITENAME}"

cut -d: -f1 /etc/passwd | grep "${USERNAME} > /dev/null"
OUT=$?
if [ $OUT -eq 1 ]; then
	# the user doesn't exist yet, so add them
	useradd --key UID_MIN=2000 --create-home ${USERNAME}
	mkdir ${WEBDIR}
	chown -R ${USERNAME}:${USERNAME} ${WEBDIR}
	chmod 770 ${WEBDIR}
fi
ln -s ${WEBDIR} /home/${USERNAME}/

# add apache to the users group
usermod --append -G ${USERNAME} apache

# create directorires and files and do permissions right
mkdir ${WEBDIR}/htdocs
chmod 770 ${WEBDIR}/htdocs
echo "coming soon" > ${WEBDIR}/htdocs/index.html
chmod 660 ${WEBDIR}/htdocs/index.html
chown -R ${USERNAME}:${USERNAME} ${WEBDIR}

# do everything related to php suexec and fastcgi
if [ ${USEPHP} -eq 1 ]; then
	mkdir ${WEBDIR}/tmp
	chmod 770 ${WEBDIR}/tmp
	chown ${USERNAME}:${USERNAME} ${WEBDIR}/tmp
	mkdir ${WEBDIR}/htdocs/cgi-bin/

	# do the php.ini
	cp /etc/php/cgi-php5/php.ini ${WEBDIR}/htdocs/cgi-bin/php.ini
	echo "session.save_path = \"${WEBDIR}/tmp\";" >> ${WEBDIR}/htdocs/cgi-bin/php.ini

	# set up the PHP wrapper script
	WRAPPER=${WEBDIR}/htdocs/cgi-bin/fphp
	echo "#!/bin/sh
umask 027
PHPRC=${WEBDIR}/htdocs/cgi-bin/
export PHPRC
PHP_FCGI_CHILDREN=1
export PHP_FCGI_CHILDREN
PHP_FCGI_MAX_REQUESTS=5000
export PHP_FCGI_MAX_REQUESTS
exec /usr/bin/php-cgi" > ${WRAPPER}
	chmod 750 ${WRAPPER}
	
	chmod 750 ${WEBDIR}/htdocs/cgi-bin/
	chown -R ${USERNAME}:${USERNAME} ${WEBDIR}/htdocs/cgi-bin/
	chattr -R +i ${WEBDIR}/htdocs/cgi-bin/
fi

# do everything related to mysql
if [ ${MYSQLDB} ]; then
	MYSQLPASS= $ENV['mysqlpass']
	USERPASS=`</dev/urandom /usr/bin/tr -dc A-Za-z0-9_ | /usr/bin/head -c20`
	/usr/bin/mysqladmin -uroot -p${MYSQLPASS} create ${MYSQLDB};
	echo "GRANT ALL PRIVILEGES ON ${MYSQLDB}.* TO '${MYSQLDB}'@'localhost' IDENTIFIED BY '${USERPASS}'" | /usr/bin/mysql -uroot -p${MYSQLPASS} ${MYSQLDB}
fi


# create vhost file with host and redirect:
echo "<VirtualHost *:80>
	DocumentRoot ${WEBDIR}/htdocs/
	ServerName ${SITENAME}
	ServerAdmin hosting@ithought.org" > /etc/apache2/vhosts.d/${SITENAME}.conf
if [ ${USEPHP} -eq 1 ]; then
	echo "	SuexecUserGroup ${USERNAME} ${USERNAME}" >> /etc/apache2/vhosts.d/${SITENAME}.conf
fi
echo "	<Directory ${WEBDIR}/htdocs/>
		Options +SymLinksIfOwnerMatch
		AllowOverride All
		Order allow,deny
	        Allow from all" >> /etc/apache2/vhosts.d/${SITENAME}.conf
if [ ${USEPHP} -eq 1 ]; then
	echo "		DirectoryIndex index.html index.php
		AddType application/x-httpd-fastphp .php
		Action application/x-httpd-fastphp /cgi-bin/fphp" >> /etc/apache2/vhosts.d/${SITENAME}.conf
fi
echo "	</Directory>
	" >> /etc/apache2/vhosts.d/${SITENAME}.conf
if [ ${USEPHP} -eq 1 ]; then
	echo "	<Directory ${WEBDIR}/htdocs/cgi-bin/>
		SetHandler fcgid-script
		FCGIWrapper ${WEBDIR}/htdocs/cgi-bin/fphp .php
		Options +ExecCGI -Includes
		allow from all
	</Directory>
	" >> /etc/apache2/vhosts.d/${SITENAME}.conf
fi
echo "</VirtualHost>" >> /etc/apache2/vhosts.d/${SITENAME}.conf 

if [ ${VHOSTALIAS} ]; then
	echo "
<VirtualHost *:80>
	ServerName ${VHOSTALIAS}
	Redirect Permanent / http://${SITENAME}/
</VirtualHost>" >> /etc/apache2/vhosts.d/${SITENAME}.conf
fi

echo "------------------------"
echo "SITE CONFIGURED "
echo "site: ${SITENAME}"
echo "server: pongo.ithought.org"
echo "protocols: SSH, SCP, SFTP"
echo "username: ${USERNAME}"
if [ ${USEPHP} ]; then
	echo "PHP is on"
fi
if [ ${MYSQLDB} ]; then
	echo "mysqldb: ${MYSQLDB}"
	echo "mysqluser: ${MYSQLDB}"
	echo "mysqlpass: ${USERPASS}"
fi
echo "------------------------"

/usr/sbin/apache2ctl configtest > /dev/null
OUT=$?

if [ ${OUT} -eq 0 ]; then
	echo "apache looks good, go ahead and restart"
else
	echo "something is wrong with the config. please take a look"
fi
