#!/bin/bash
set -e # -x
source config.sh

required_vars=(
	TOP_DOMAIN
	NGINX_CONF_DIR
)
for v in "${required_vars[@]}" ; do
#	echo "$v => ${!v}"
	if [[ -z "${!v}" ]] ; then
		echo "Set the $v variable in config.sh before running $0"
		exit
	fi
done

usage() { 
	>&2 echo "usage: $0 -c add -s subdomain -l +443:127.0.0.1:5000 [-a]"
	>&2 echo "usage: $0 -c <edit|rm> -s subdomain"
	>&2 echo "usage: $0 -c list"
	>&2 echo 
	>&2 echo -e "\t-c\tThe command \"add\", \"edit\", \"rm\" or \"list\". In case of \"add\" the parameter -l is required.\n\
		in the case of \"list\" the subdomain argument is not needed."
	>&2 echo -e "\t-a\tAppend the proxy entry to the config rather than overwriting the config."
	>&2 echo -e "\t-s\tThe subdomain for which you want to either add a configuration, remove a\n\
		configuration or open an editor for. Respects EDITOR env variable - defaults to vim."
	>&2 echo -e "\t-l\tThe binding and redirect for the domain. Is in the\n\
		format listen_port:backend_addr:backend_port. Example: 80:192.168.0.12:8080 where nginx\n\
		listens on port 80 and forwards requests to the backend 192.168.0.12 on port 8080.\n\
		prefix the listen port with + to listen on TLS. Example: +443:192.168.0.10:443"
	exit 1 
}

listeners=()
while getopts "c:s:l:a" flag ; do
	#echo "$flag: $NAME => $OPTARG"
	case "$flag" in
		c) # add, rm, edit
			cmd=$OPTARG
			;;
		s) # yarr, birdnet
			subdomain=$OPTARG
			;;
		l) # 80:192.168.10.12:8080, +443:168.10.12:9090
			listeners+=("$OPTARG")
			;;
		a) # append to existing config
			append="-a"
			;;
		\?) # invalid/unknown option 
			usage
			;;
		:) # missing required option
			usage
			;;
	esac
done

if [[ -z "$cmd" ]]
then
	usage
fi

if [[ -z "$subdomain" && "$cmd" != "list" ]] # required params
then
	usage
fi

domain=$subdomain.$TOP_DOMAIN
conf_file="$NGINX_CONF_DIR$domain"

case "$cmd" in
	add) 
		appnd="$append"
		echo "Generating nginx config for $domain."
		for listen_line in "${listeners[@]}"
		do
			lp="$(echo "$listen_line" | cut -d':' -f 1)"
			if [[ "$lp" = "+"* ]]
			then
				lp="$(echo "$lp" | tr -d '+') http2"
			fi
			be="$(echo "$listen_line" | cut -d':' -f 2-)"
			cat nginx.conf.template \
				| sed "s/SERV_NAME/$domain/" \
				| sed "s/LISTEN_PORTS/$lp/" \
				| sed "s/BACKEND/$be/" \
				| sed "s/LISTEN_LINE/$listen_line/" \
				| tee $appnd "$conf_file"
			appnd="-a"
		done
		sudo nginx -t
		if [[ -z $append ]]
		then
			echo "Reloading nginx after appending to config $conf_file"
		else
			echo "Reloading nginx after writing config to $conf_file"
		fi
		sudo systemctl reload nginx
		;;
	edit)
		
		if [[ ! -f "$conf_file" ]]
		then
			echo "Could not find file to edit at $conf_file"
			echo "Did you mistype the subdomain or not yet create the config?"
			exit 2
		fi

		echo "Editing config for $domain"
		${EDITOR:-vim} "$conf_file"
		echo "Testing if all configs are still valid"

		sudo nginx -t
		echo -e "\nIf the config test was successful reload nginx to apply the config\n\n\tsudo systemctl reload nginx\n"
		;;
	rm) 
		if [[ ! -f "$conf_file" ]]
		then
			echo "Could not find file to remove at $conf_file"
			echo "Did you mistype the subdomain or not yet create the config?"
			exit 2
		fi

		echo "Removing config for $domain"
		read -p "Enter the subdomain to verify your action: " vsub
		if [[ "$subdomain" = "$vsub" ]]
		then
			echo "Removing $conf_file"
			rm "$conf_file"
			sudo systemctl reload nginx
		else
			echo "Input did not match subdomain - nothing was deleted"
			exit
		fi
		;;
	list)
		for f in "$NGINX_CONF_DIR"*
		do
			bn="$(basename "$f")"
			echo "Domain: $bn"
			awk '/# ld: / { print "\t" $3 }' "$f"
			
		done
		;;

	*) 
		echo "Unknown command $cmd"
		exit 
		;;
esac


