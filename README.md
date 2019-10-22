# Docker Utilities and Basic Network

Basic structure to deploy Docker through a load balancer or reverse proxy

## Getting Started

Here are instructions for obtaining a copy of the project up and running on your local machine for development and testing purposes. 

### Prerequisites

1. a Linux Server (VPS) 

2. Hardening of Linux Server [Ubuntu Example](https://github.com/nasatome/First-Steps-and-Hardening-in-Ubuntu-Server-And-Docker)

3. Open Ports `80` an `443`

4. Don't forget to leave the SSH port open in case you use it.

5. Install Docker (You can use this command:)

   `curl -fsSL get.docker.com -o get-docker.sh && sh get-docker.sh`

   

### Installing Ecosystem

This is not software that is installed as such, but rather a series of "modules" that will help you build your own infrastructure.

First of all, you need to install a load balancer, the one I recommend is Traefik, for its ease of configuration.

[Link to Mount Initial Traefik Container](/reverse-proxy/traefik)

You can use the following modules that can be added to this load balancer

`https://github.com/nasatome/dockapress`  It's a project to run WordPress with docker

`https://github.com/nasatome/dockpy` is a project to run Docker Projects with Python, (Django, Flask)

`https://github.com/nasatome/doockla` Docker + (PHP) Joomla

`https://github.com/nasatome/dockavel` Docker + (PHP) Laravel



## Deployment

Future additional notes about how to deploy this on a live system



## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct, and the process for submitting pull requests to us.

## <!--Versioning-->

<!--We use [SemVer](http://semver.org/) for versioning. For the versions available, see the [tags on this repository](https://github.com/nasatome/docker-network-utils/tags).--> 

## Authors

* **[nasatome](https://github.com/nasatome)** - *Initial work* 

See also the list of [contributors](https://github.com/nasatome/docker-network-utils/contributors) who participated in this project.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* Suppose there are 4 types of deployment strategies

  1. Service per instance
  2. Multiple services per instance
  3. Service per container
  4. Serverless Service

  This Project is perfect in union with the other modules, for the second case, where in an economic way you can mount multiple microservices in the same host, making your projects very economic and future scalable.

* Inspiration: For people who have little knowledge to use micro services with docker, this can be an excellent getting started guide.

  

