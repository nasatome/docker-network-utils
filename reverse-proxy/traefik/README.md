### Steps for Linux:

1. Exec Commands

*Change the PROJECT_DIR variable to your address, where you normally store projects.*

`export PROJECT_DIR="/opt/prj";`

`mkdir -p $PROJECT_DIR`

`cd $PROJECT_DIR`

`git clone git@github.com:nasatome/docker-network-utils.git`

```
cd docker-network-utils && \
cd reverse-proxy && \
cd traefik
```

```
cp .env.example .env && \
cp .cloudflare-api.key.example .cloudflare-api.key
```
2. Set variables in .env file

3. Change Password in .htpasswd file; You can use this command:

`docker run --rm httpd:2.4-alpine htpasswd -nbB CHANGE_USER CHANGE_PASSWORD; history -d $(history | tail -1 | awk '{print $1}') ; printf "\n\n"`

4. Check DNS KEY (cloudflare-api.key For Cloudflare Example)

Notes: 

For Traefik Help: 
`docker run --rm traefik:2.4 --help | less` 

Providers for Traefik 2.4
`https://doc.traefik.io/traefik/https/acme/#providers`

#### Other providers example: 
In the .env file change the TRAEFIK_DNS_PROVIDER variable: 
For digital ocean

``` 
TRAEFIK_DNS_PROVIDER=digitalocean
```

Create a file with the same name of TRAEFIK_DNS_PROVIDER, example:
`vi .TRAEFIK_DNS_PROVIDER-api.key`

now the file name looks like this `.digitalocean-api.key`

contains: 

```
DO_AUTH_TOKEN=<token_value>
```

5. Finally: Up the docker compose

`docker-compose pull && docker-compose down -v && docker-compose up -d`
