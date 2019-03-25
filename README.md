# gen-env

The script auto-deploy applications; Nginx generation of configs; Create and manage Docker containers; Delivery of application files to workdir

## Requirements

- bash
- nginx
- docker
- rsync
- netstat

## Install

1. Go to `/opt` directory and clone repo

``` bash
cd /opt && git clone git@github.com:artroot/autodeploy.git 
```

2. Go to cloned directory and run `install.sh` for create link in `/bin` directory

``` bash
cd autodeploy && sudo install.sh
``` 


## Getting Started

Run `gen-env -h` or `gen-env --help` for information about usage

> For usage gen-env script you need to run it with root privileges (sudo)

## Help

```
Usage:    /bin/gen-env COMMAND [OPTIONS]
- Generation and set Nginx config; Creating Workdir and reload nginx;
- Management of Docker containers; Delivery application
Examples:
  /bin/gen-env build -u 5 -g example-com -p frontend
  /bin/gen-env build -u 5 -g example-com -p frontend -D
  /bin/gen-env rebuild -u 5 -g example-com -p frontend
  /bin/gen-env destroy -u 5 -g example-com -p frontend
  /bin/gen-env delivery -u 5 -g example-com -p frontend -e 'src/* file.md' -i 'src/config'

Commands:
  build               Generation Nginx config by template; Creating Workdir; Create Docker container (optional)
  rebuild             Regenerate nginx configuration
  destroy             Delete Nginx config and Docker container
  delivery            Delivery application to workdir

Options:
  -u [User ID]        Gitlab User ID (Must be integer)
  -g [Group Name]     Gitlab Projects Group Name
  -p [Project Name]   Gitlab Project Name
  -P [Port]           Internal port in container (default 4000); Set your own port number if your application works on different port
  -D                  Create Docker container (optional) Only for build command
  -t [Path]           Path to custom Nginx config template (optional) Only for build and rebuild
  -I [Image]          Docker Image (default in config); Set different Image URL
  -e [PATTERNS]       Exclude files or directories list (via space separator) of delivery (optional) Only for delivery command
  -i [PATTERNS]       Don't exclude files or directories list (via space separator) of delivery (optional) Only for delivery command
```

### Usage in `.gitlab-ci.yml`

#### Example: 

```yaml

stages:
 - deploy-to-dev

# Deploying any features branches to <User_id>-<Group_name>-<Project_name>.dev.example.com
deploy-to-dev:
 variables: 
    GROUP_NAME: "example-com"
    PROJECT_NAME: "frontend"
    CONTAINER_NAME: "$GITLAB_USER_ID-$GROUP_NAME-$PROJECT_NAME"
 stage: deploy-to-dev
 before_script:
    # Creating config and container if it`s not yet created
  - gen-env build -u $GITLAB_USER_ID -g $GROUP_NAME -p $PROJECT_NAME -D -t 'nginx.conf.template'
 script:
    # Delivery to workdir
  - gen-env delivery -u $GITLAB_USER_ID -g $GROUP_NAME -p $PROJECT_NAME -e '*' -i 'dist**'
    # Restarting container
  - docker restart $CONTAINER_NAME
 environment:
    name: $GITLAB_USER_LOGIN/$CI_COMMIT_REF_NAME
    url: http://$GITLAB_USER_ID-$GROUP_NAME-$PROJECT_NAME.dev.example.com
 tags:
  - integration
 only: 
  - branches
 except:
  - /^release.*$/
  - master
  - develop

```

`-i 'dist**'` means that directory dist and all it childs will be copy

`-e '*'` means that all files and directories (except those listed in `-i`) won't be copied

`-t 'nginx.conf.template'` is nginx config template in repo.

#### Nginx config template example: 

```

server {
	
	listen 80;

	listen 443 ssl;
	
	server_name  ${server_name};

	error_log ${work_dir}/error.log;

	client_max_body_size 12m;

	location /sitemap {

		root /var/www/static/cmtools/sitemaps/;

		if (!-f $request_filename) {
			rewrite .* /;
        	}
	}

	location / {
		proxy_pass http://127.0.0.1:${proxy_pass_port}/;
        	proxy_http_version 1.1;
        	proxy_set_header Upgrade $http_upgrade;
        	proxy_set_header Connection 'upgrade';
        	proxy_set_header Host $host;
        	proxy_cache_bypass $http_upgrade;
       }
}


```

## Script configuration

Path to config file `/opt/autodeploy/config/gen-env.conf`

Default configuration example: 

```

# Path to nginx configuration
nginx_conf_dir=/etc/nginx/conf.d

# Reload Nginx configuration command
nginx_reload_command='systemctl reload nginx'

# Path to nginx configuration templates
nginx_conf_templates_dir=/opt/autodeploy/templates

# List of reserved ocker Containers external ports
reserved_port_list=/opt/autodeploy/port_list

# Env domain
review_domain=.dev.example.com

# Work Dirs path
work_dirs_path=/var/www/html/develop

# Reserved Docker Containers external port range
start_port_pool=30000

end_port_pool=39999

# Default docker image for run containers
#default_docker_image=''


```


## Specifics

### Docker 

- docker external ports range: from `30000` to `39999`
- reserved ports saving to `port_list` file
- port choose logic is: brute force the port pool until a port is found that is not used or is not contained in the `port_list` file

### Nginx 

- nginx config dir set as default: `/etc/nginx/cond.d`. If you need to change this path, redefine it in `nginx_conf_dir` variable `config/gen-env.conf` configuration
- directory `templates` contain the default nginx config template, if you have your own config file template set it to `templates` directory (file name must end on `.template`) or add template to your repo and set the link to it in `-t`

### WorkDir

- Workdir startpoint path set default as: `/var/www/html/develop`. You can change this path in `work_dirs_path` variable in `config/gen-env.conf` configuration
 
### DNS configuration

You should to have next records in your develop domain zone: 

```
wildcard.<Your Develop Domain>     Host (A)    Default     <Your Develop Env. Server>
```

```
*.<Your Develop Domain>.   IN CNAME wildcard.<Your Develop Domain>.
```
> The dots at the end of the domain names must be.
