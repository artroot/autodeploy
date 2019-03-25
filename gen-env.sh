#!/usr/bin/bash
#
# By Artem Semenishch <a.semenishch@gmail.com>
# Created: 2019-02-13

## Shell colors
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

DOCKER=0

CONFIG='/opt/autodeploy/config/gen-env.conf'

# Load and Check configuration file
if [[ -a $CONFIG ]]
    then

        # Load configurations
        source $CONFIG

        if [[ -z "$nginx_conf_dir" || -z "$nginx_conf_templates_dir" || -z "$review_domain" || -z "$start_port_pool" || -z "$end_port_pool" || -z "$nginx_reload_command" || -z "$reserved_port_list" || -z "$work_dirs_path" || -z "$default_docker_image" ]]
            then
                echo -e "${RED}Bad configuration.${NC} Please check file $CONFIG"
                exit 1
        fi

    else
        echo -e "${RED}Configuration file not exist.${NC} Looking for in: $CONFIG"
        exit 1
fi

print_help () {

    echo "Usage:    $0 COMMAND [OPTIONS]"
    echo "- Generation and set Nginx config; Creating Workdir and reload nginx;"
    echo "- Management of Docker containers; Delivery application"
    echo "Examples:"
    echo "  $0 build -u 5 -g example-com -p frontend"
    echo "  $0 build -u 5 -g example-com -p frontend -D"
    echo "  $0 rebuild -u 5 -g example-com -p frontend"
    echo "  $0 destroy -u 5 -g example-com -p frontend"
    echo "  $0 delivery -u 5 -g example-com -p frontend -e 'src/* file.md' -i 'src/config'"
    echo ""
    echo "Commands:"
    echo "  build               Generation Nginx config by template; Creating Workdir; Create Docker container (optional)"
    echo "  rebuild             Regenerate nginx configuration"
    echo "  destroy             Delete Nginx config and Docker container"
    echo "  delivery            Delivery application to workdir"
    echo ""
    echo "Options:"
    echo "  -u [User ID]        Gitlab User ID (Must be integer)"
    echo "  -g [Group Name]     Gitlab Projects Group Name"
    echo "  -p [Project Name]   Gitlab Project Name"
    echo "  -P [Port]           Internal port in container (default 4000); Set your own port number if your application works on different port"
    echo "  -D                  Create Docker container (optional) Only for build command"
    echo "  -t [Path]           Path to custom Nginx config template (optional) Only for build and rebuild"
    echo "  -I [Image]          Docker Image (default in config); Set different Image URL"
    echo "  -e [PATTERNS]       Exclude files or directories list (via space separator) of delivery (optional) Only for delivery command"
    echo "  -i [PATTERNS]       Don't exclude files or directories list (via space separator) of delivery (optional) Only for delivery command"

    exit 0
}

case "$1" in
    "build" )
        MODE='build'
        shift 1
    ;;

    "rebuild" )
        MODE='rebuild'
        shift 1
    ;;

    "delivery" )
        MODE='delivery'
        shift 1
    ;;

    "destroy" )
        MODE='destroy'
        shift 1
    ;;

    "--help" | "-h" )
        print_help
    ;;

    * )
        echo -e "${RED}Missed Command${NC}";
        echo -e "Run $0 -h or $0 --help for details"
        exit 1
    ;;
esac

## Flags definition
while getopts ":u:g:p:P:I:e:i:t:D" option
do
case "${option}"
in
u) repo_user_id=${OPTARG};;
g) repo_group_name=${OPTARG};;
p) repo_project_name=${OPTARG};;
P) app_port=${OPTARG};;
e) exclude_list=${OPTARG};;
i) include_list=${OPTARG};;
t) custom_template=${OPTARG};;
I) docker_image=${OPTARG};;
D) DOCKER=1;;
*) print_help;;
esac
done

check_user_id () {

    if [ ${repo_user_id+x} ]; then
        if [[ $repo_user_id != ?(-)+([0-9]) ]]; then
            echo -e "-u ${RED}<user_id>${NC} must be numeric";
            exit 1
        fi
    else 
        repo_user_id=0
    fi

}

check_group_name () {

    if [ -z ${repo_group_name+x} ]; then
        echo -e "-g ${RED}<group_name>${NC} is unset";
        exit 1
    fi

}

check_project_name () {

    if [ -z ${repo_project_name+x} ]; then
        echo -e "-p ${RED}<project_name>${NC} is unset";
        exit 1
    fi

}

check_app_port () {

    if [ ${app_port+x} ]; then
        if [[ $app_port != ?(-)+([0-9]) ]]; then
            echo -e "-P ${RED}<port>${NC} must be numeric";
            exit 1
        fi
    fi

}

check_exclude_list () {

    if [ ${exclude_list+x} ]; then
        if [ -z ${exclude_list+x} ]; then
            echo -e "-e ${RED}<exclude_list>${NC} is unset";
            exit 1
        fi
    fi

}

check_include_list () {

    if [ ${include_list+x} ]; then
        if [ -z ${include_list+x} ]; then
            echo -e "-i ${RED}<include_list>${NC} is unset";
            exit 1
        fi
    fi

}

check_custom_template () {

    if [ ${custom_template+x} ]; then
        if [ -z ${custom_template+x} ]; then
            echo -e "-i ${RED}<path to template>${NC} is unset";
            exit 1
        fi
    fi

}

case "$MODE" in
    "build" )
        check_user_id
        check_group_name
        check_project_name
        check_app_port
        check_custom_template
    ;;

    "rebuild" )
        check_user_id
        check_group_name
        check_project_name
        check_app_port
        check_custom_template
    ;;

    "delivery" )
        check_user_id
        check_group_name
        check_project_name
        check_exclude_list
        check_include_list
    ;;

    "destroy" )
        check_user_id
        check_group_name
        check_project_name
        check_app_port
    ;;
esac


project_slug_raw="$repo_group_name-$repo_project_name"
project_slug=`echo "$repo_group_name-$repo_project_name" | sed -e 's/\//\-/g; s/\./\-/g; s/[&$%#!@^*()]//g;'`

if [ "$repo_user_id" == '0' ]; then
    server_name_raw="$project_slug_raw$review_domain"
    server_name="$project_slug$review_domain"
else
    server_name_raw="$repo_user_id-$project_slug_raw$review_domain"
    server_name="$repo_user_id-$project_slug$review_domain"
fi

work_dir="$work_dirs_path/$project_slug/$repo_user_id"

work_dir_for_expression=`echo "$work_dir" | sed -e 's/\//\\\\\//g'`

if [ "$repo_user_id" == '0' ]; then
    CONTAINER_NAME=$project_slug_raw
else
    CONTAINER_NAME=$repo_user_id-$project_slug_raw
fi

drop_container () {

        echo -e "${ORANGE}Stop container $CONTAINER_NAME ${NC}"
        docker stop $CONTAINER_NAME

        echo -e "${ORANGE}Remove container $CONTAINER_NAME ${NC}"
        docker rm $CONTAINER_NAME

}

#### create workdir
create_workdir () {

    if [ ! -d "$work_dir" ]; then
        echo -e "${GREEN}Creating directory... $work_dir${NC}"
        mkdir -p "$work_dir"
    else
        echo -e "${ORANGE}Directory $work_dir already exist ${NC}"
    fi

}

#### Finding free port
find_free_port () {

    echo -e "Finding free port..."
    for (( port=$start_port_pool; port<$end_port_pool; port++ ))
    do
        if [ "`netstat -tulnp | grep :$port | wc -l`" == '0' ] && [ "`grep $port $reserved_port_list | wc -l`" == '0' ]; then
            echo "$port:$server_name_raw" >> $reserved_port_list
            proxy_pass_port=$port
            echo -e "${GREEN}Port $proxy_pass_port reserved...${NC}"
            break
        fi
    done

}

#### Create Docker container
create_docker_container () {

    LOCAL_WORK_DIR_PATH=$work_dir
    CONTAINER_WORK_DIR_PATH='/usr/src/app'
    EXT_PORT=$port

    ### Set internal port
    if [ ${app_port+x} ]; then
        INT_PORT=$app_port
    else
        INT_PORT=4000
    fi

    ### Set Docker image
    if [ ${docker_image+x} ]; then
        IMAGE=$docker_image
    else
        IMAGE="$default_docker_image"
    fi

    ### Check Container Exist
    if [ `docker ps -a | grep " $CONTAINER_NAME" | wc -l` -ne 0 ]; then

        echo -e "${ORANGE}Container $CONTAINER_NAME already exist ${NC}"

        ### Remove port from reserved port list
        sed -i '/'$proxy_pass_port:*'/d' $reserved_port_list

        proxy_pass_port=`grep ":$CONTAINER_NAME" $reserved_port_list | cut -f1 -d:`
        echo -e "${GREEN}Port $proxy_pass_port restored...${NC}"

    else

        ### Run container
        echo -e "${GREEN}Running new Docker Container... $CONTAINER_NAME ${NC}"
        docker run --name $CONTAINER_NAME -p $EXT_PORT:$INT_PORT --expose $INT_PORT -v $LOCAL_WORK_DIR_PATH:$CONTAINER_WORK_DIR_PATH -d $IMAGE
        echo -e `docker ps -a | grep $CONTAINER_NAME`

    fi

}


create_nginx_config () {

    #### Set expressions and chose template
    echo -e "${GREEN}Generating config... $nginx_conf_dir/$server_name.conf${NC}"
    expressions='s/${server_name}/'$server_name'/; '
    expressions+='s/${work_dir}/'$work_dir_for_expression'/; '
    expressions+='s/${proxy_pass_port}/'$proxy_pass_port'/'

    if [ ${custom_template+x} ]; then
    
        if [ ! -f "./$custom_template" ]; then
            echo -e "Custom template: ${RED}./$custom_template${NC} Not Found";

            drop_container

            ### Remove port from reserved port list
            sed -i '/'$proxy_pass_port:*'/d' $reserved_port_list

            exit 1
        fi

        template="./$custom_template"
        
    elif [ ! -f "$nginx_conf_templates_dir/$project_slug.template" ]; then

        if [ ! -f "$nginx_conf_templates_dir/default.template" ]; then
            echo -e "Default template: ${RED}$nginx_conf_templates_dir/default.template${NC} Not Found";

            drop_container

            ### Remove port from reserved port list
            sed -i '/'$proxy_pass_port:*'/d' $reserved_port_list

            exit 1
        fi

        template="$nginx_conf_templates_dir/default.template"

    else
        template="$nginx_conf_templates_dir/$project_slug.template"
    fi

    ### Generate config by template
    sed -e "$expressions" $template > "$nginx_conf_dir/$server_name.conf"

    nginx_test=`nginx -t 2>&1 | grep -v 'syntax is ok' | grep -v 'is successful' | wc -l`

    if [ $nginx_test -ne 0 ]; then
        echo `nginx -t`
        echo -e "${ORANGE}Removing config $nginx_conf_dir/$server_name.conf... ${NC}"
        rm -f "$nginx_conf_dir/$server_name.conf"
        drop_container

        ### Remove port from reserved port list
        sed -i '/'$proxy_pass_port:*'/d' $reserved_port_list

        exit 1
    fi

    ### Nginx service reload
    echo -e "${GREEN}Restarting nginx...${NC}"
    ### Run nginx reload command
    `$nginx_reload_command`

}

destroy () {

    echo -e "${GREEN}Start destroy $CONTAINER_NAME ${NC}"

    drop_container

    ### Remove port from reserved port list
    sed -i '/'.:$CONTAINER_NAME'/d' $reserved_port_list

    echo -e "${ORANGE}Removing config $nginx_conf_dir/$server_name.conf... ${NC}"
    rm -f "$nginx_conf_dir/$server_name.conf"

    echo -e "${GREEN}Restarting nginx...${NC}"
    ### Run nginx reload command
    `$nginx_reload_command`

    echo -e "${GREEN}$server_name destroyed successful ${NC}"

    exit 0
}

delivery () {

    CURRENT_PATH='.'
    WORK_DIR_PATH=$work_dir
    EXC=''
    INC=''

    echo -e "${GREEN}Copy files... ${NC}"
    rsync -rv $CURRENT_PATH/* $WORK_DIR_PATH $(printf "$include_list" | sed -e 's/ / --include=/g; s/^/--include=/; s/$//;') $(printf "$exclude_list" | sed -e 's/ / --exclude=/g; s/^/--exclude=/; s/$//;')

}

######### Modes realisation

case "$MODE" in
    "build" | "rebuild" )
        
        if [ ! -f "$nginx_conf_dir/$server_name.conf" ] || [ "$MODE" == 'rebuild' ]; then
            if [ $DOCKER == 1 ]; then
                find_free_port
                create_docker_container
            fi
            create_nginx_config
        else
            echo -e "${ORANGE}Configurate $nginx_conf_dir/$server_name.conf already exist ${NC}"
        fi

        echo -e "${GREEN}----------------------------------------------- ${NC}"
        echo -e "${GREEN}Domain $server_name ready to use ${NC}"
        exit 0
    ;;

    "delivery" )
       delivery
       echo -e "${GREEN}Delivery complete successful ${NC}"
       exit 0
    ;;

    "destroy" )
        destroy
    ;;
esac

exit 0
