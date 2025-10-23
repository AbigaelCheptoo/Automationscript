# Automated Docker Deployment Script

This repository contains a Bash script (`deploy.sh`) that automates the deployment of a Dockerized application on a remote Linux server. It is designed for production-grade deployments and includes proper logging, error handling and Nginx reverse proxy configuration.

---

## Features

- Clones any given GitHub repository using a Personal Access Token (PAT)
- Builds and runs Docker containers from `Dockerfile` or `docker-compose.yml`
- Automatically installs Docker, Docker Compose, and Nginx on the remote server
- Configures Nginx as a reverse proxy to the application
- Validates deployment and prints endpoint URL
- Supports safe redeployment and cleanup

---

##  Usage Instructions

1. Make the script executable (if not already):

```bash
chmod +x deploy.sh
2.Run the deployment script:

./deploy.sh


3.Follow the prompts:

Git repository URL: URL of the repository to deploy (e.g., the application repo)

Personal Access Token (PAT): GitHub PAT for authentication

Branch name: Optional (defaults to main)

Remote server SSH details: Username, IP, SSH key path

Application container port: Internal port your app exposes (e.g., 80)

After completion, visit your deployed app:

http://<server-ip>


