Steps for Ubuntu Linux:

1.- Exec Commands

`mkdir -p /opt/prj/`

`cd /opt/prj/`

`git clone git@github.com:nasatome/docker-network-utils.git`

`cp .env.example .env` 

`cp .cloudflare-api.key.example .cloudflare-api.key`

`cp .htpasswd.example .htpasswd`

`cp traefik.toml.example traefik.toml`

2.- Check DNS KEY (For Cloudflare Example)

3.- Change Password in .htpasswd file
`docker run --rm httpd:2.4-alpine htpasswd -nbB CHANGE_USER CHANGE_PASSWORD; history -d $(history | tail -1 | awk '{print $1}') ; printf "\n\n"`

4.- Set variables in .env file
