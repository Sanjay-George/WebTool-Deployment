# WebTool-Deployment
Code and infra design for the deployment of a web app on GCP. The cloud infra will be improved over different stages as listed below. 

The web app is in a private repo and can't be made public. It is built with the **MERN** stack 📚. 

## Infra #1: Basic deployment using Compute Engine VMs
Create a simple deployment model with 
* Cloud Secret Manager to access private GitHub repo (deploy keys)
* Single `Build / CI` server to build the code in production mode (React, Node)
* Cloud File store / Cloud Storage to store the built files. 
* Instance groups to create multiple webservers which will get the built files and serve them
* External HTTP (layer 7) Load Balancer 
* ~~Project metadata for service discovery (of CI and database)~~

![infra-1](https://user-images.githubusercontent.com/10389062/198868714-d73e1975-c0ad-457b-b686-cc0bdd3e6cb1.png)



## Next steps 🪜
* Infra #2: Add self-managed MongoDB and make necessary code changes to point to appropriate DB server on local and prod
* Infra #3: Add CI / CD pipeline instead of build server
* Infra #4: Optimize static assets delivery using CDN Caching and `google_compute_url_map`
