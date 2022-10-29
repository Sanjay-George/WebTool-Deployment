# WebTool-Deployment
Code and infra design for the deployment of the web tool project on GCP. The cloud infra will be improved over different stages as listed below. 

The web tool is in a private repo and can't be made public. It is built with **MERN** stack. 

## Plan #1: Basic deployment using Compute Engine VMs
Create a simple deployment model with 
* One Build / CI server responsible to build the code in production mode (React, Node)
* Instance groups: multiple webservers which will get the built files and serve them
* Load Balancer in front
* Use Project metadata for service discovery (of CI and database)

![infra-1](https://user-images.githubusercontent.com/10389062/197405949-00b6c5f5-6ac2-4ea1-b29c-e04aff9d72e1.png)

## Next steps:
* Plan #2: Self-managed MongoDB
* Plan #3: CI / CD pipeline instead of build server
