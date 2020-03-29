#!/bin/bash
set -x

install_mariadb(){
	. ./config.sh
	docker run \
		--name mariadb \
		-v /home/mroz/mysql:/etc/mysql \
		-v $MARIADB_DATA_PATH:/var/lib/mysql \
		-e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD \
		-e MYSQL_DATABASE=$MYSQL_DATABASE \
		-e MYSQL_USER=$MYSQL_USER \
		-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
		--detach \
		-d mariadb
	x=0
	while [ "$x" -lt "20" ] ; do
		count="$(docker exec -it mariadb mysql --password=kurwa166 -u root -s -r -e "select count(*) from mysql.user where user='nextcloud';" | grep -e "[0-9]" -o)"
		[[ "$count"=="1" ]] && return 0 ;
		sleep 1;
		x=$(($x+1));
	done ;

	return 1;

	
}

install_nextcloud(){
	. ./config.sh
	docker run -d \
		-p 80:80 \
		-e MYSQL_DATABASE=$MYSQL_DATABASE \
		-e MYSQL_USER=$MYSQL_USER \
		-e MYSQL_PASSWORD=$MYSQL_PASSWORD \
		-e MYSQL_HOST=$MYSQL_HOST:$MYSQL_PORT \
		--name nextcloud \
		--link mariadb:$MYSQL_HOST \
		nextcloud
	
	# zaczekaj az wszystkie pliki php sa juz na swoim miejscu
	x=0
	error=1
	while [ "$x" -lt "10" ] && [ "$error" -eq 1 ]; do
		sleep 3
		[ -z "$(docker exec --user www-data nextcloud php occ -V | egrep -o "Nextcloud[ \t]+[0-9]+\.[0-9]+\.[0-9]+")" ]	|| error=0 ;
		x=$(($x+1));
	done

	[[ "$error" == "1" ]] && return 1

	# zaczekaj az mozliwe bedzie zalogowanie sie do bazy danych
	x=0
	error=1
	while [ "$x" -lt 10 ] && [ "$error" -eq 1 ] ; do
		sleep 2;
		[[ "$(docker exec -it mariadb mysql --user=$MYSQL_USER --password=$MYSQL_PASSWORD -e select "logged" )" = *logged* ]] && error=0 
		x=$(($x+1))
	done;

	[[ "$error" == 1 ]] && return 1

	# zainstaluj nextclouda i skonfiguruj go
	docker exec \
		--user www-data \
		nextcloud \
		php occ  maintenance:install \
			--no-interaction \
			--database "mysql" \
			--database-host "$MYSQL_HOST:$MYSQL_PORT" \
			--database-name "$MYSQL_DATABASE" \
			--database-user "$MYSQL_USER" \
			--database-pass "$MYSQL_PASSWORD" \
			--admin-user "$NEXTCLOUD_ADMIN_USER" \
			--admin-pass "$NEXTCLOUD_ADMIN_PASSWORD"

	docker exec --user www-data -it nextcloud php occ config:system:set trusted_domains 2 --value=$NEXTCLOUD_TRUSTED_DOMAIN
}


case "$1" in
	"install")install_mariadb && install_nextcloud ;;
	"install_maria") install_mariadb ;;
	"install_nc") install_nextcloud ;; 
	"remove") . ./config.sh
		  sudo docker kill nextcloud;
		  sudo docker rm nextcloud;
		  sudo docker kill mariadb;
		  sudo docker rm mariadb;
		  sudo rm $MARIADB_DATA_PATH -Rf
		  ;;
	*)echo "polecenia: install, remove"
esac
