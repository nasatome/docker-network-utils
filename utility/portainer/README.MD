1.-

`cp .env.example .env`

> Change .env values

Generate Password and paste in .env (sometimes the $ symbol requires that it be placed escaped with double symbol ($$))

`docker run --rm httpd:2.4-alpine htpasswd -nbB admin CHANGE_PASSWORD | cut -d ":" -f 2 ; history -d $(history | tail -1 | awk '{print $1}') ; printf "\n\n"`


2.- Up the docker compose

`docker-compose pull && docker-compose down -v && docker-compose up -d`

(You must already have the balancer running.)


