Steps for Ubuntu Linux:

1.- Exec Commands

`mkdir -p /opt/prj/`

`cd /opt/prj/`

`git clone git@github.com:nasatome/docker-network-utils.git`

`cd docker-network-utils`

`cp .env.example .env`

`cp .cloudflare-api.key.example .cloudflare-api.key`

`cp .htpasswd.example .htpasswd`

`cp stable_traefik.toml.example stable_traefik.toml`

2.- Check DNS KEY (cloudflare-api.key For Cloudflare Example)

3.- Change Password in .htpasswd file
`docker run --rm httpd:2.4-alpine htpasswd -nbB CHANGE_USER CHANGE_PASSWORD; history -d $(history | tail -1 | awk '{print $1}') ; printf "\n\n"`

4.- Set variables in .env file

Notes: 

For Help: 
`docker run --rm traefik:1.7-alpine --help | less`

>ESC + : + q (for exit) 

Providers
`https://docs.traefik.io/v1.7/configuration/acme/#provider`

Other providers example: 
in .env 
TRAEFIK_DNS_PROVIDER=digitalocean

the file .digitalocean-api.key

contains: DO_AUTH_TOKEN=<token_value>


5.- Up the docker compose

`docker-compose pull && docker-compose down -v && docker-compose up -d`
