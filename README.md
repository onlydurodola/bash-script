# Automated Deployment Script

A production-grade Bash script for automated deployment of Dockerized applications to remote Linux servers.

## 🚀 Features

- ✅ Automated Git repository cloning with PAT authentication
- ✅ Remote server environment setup (Docker, Docker Compose, Nginx)
- ✅ Docker container deployment and management
- ✅ Nginx reverse proxy configuration
- ✅ Comprehensive logging and error handling
- ✅ Idempotent deployment (safe for re-runs)
- ✅ Resource cleanup functionality
- ✅ Deployment validation and health checks
- ✅ Security headers and best practices

## 📋 Prerequisites

- **Bash 4.0+**
- **SSH access** to remote server with key-based authentication
- **Git Personal Access Token (PAT)** with repo access
- **Remote server**: Ubuntu 18.04+ or CentOS 7+ (tested on Ubuntu 20.04+)
- **Sudo privileges** on the remote server

## 🛠️ Installation

1. **Download the script:**
```bash
wget https://raw.githubusercontent.com/your-username/your-repo/main/deploy.sh
```

2. **Make it executable:**
```bash
chmod +x deploy.sh
```

## 📖 Usage

### Full Deployment
```bash
./deploy.sh
```

### Cleanup Deployment Resources
```bash
./deploy.sh --cleanup
```

### Show Help
```bash
./deploy.sh --help
```

### Show Version
```bash
./deploy.sh --version
```

## 🔧 Input Parameters

When you run the script, it will prompt for:

| Parameter | Description | Default |
|-----------|-------------|---------|
| **Git Repository URL** | HTTPS URL of your Git repository | *Required* |
| **Personal Access Token** | GitHub/GitLab token with repo access | *Required* |
| **Branch name** | Git branch to deploy | `main` |
| **SSH username** | Username for remote server | *Required* |
| **Server IP address** | IP of your deployment server | *Required* |
| **SSH key path** | Path to SSH private key | `~/.ssh/id_rsa` |
| **Application port** | Internal container port | `3000` |

## 🔄 What the Script Does

### Local Operations
1. **Validates** all input parameters
2. **Clones/Pulls** the Git repository using PAT authentication
3. **Verifies** Docker configuration files (Dockerfile or docker-compose.yml)
4. **Sets up** comprehensive logging

### Remote Server Operations
1. **Tests SSH connectivity** to the server
2. **Updates system packages** and installs dependencies
3. **Installs** Docker, Docker Compose, and Nginx
4. **Transfers project files** to the server via SCP
5. **Builds and runs** Docker containers
6. **Configures Nginx** as a reverse proxy
7. **Validates** the entire deployment

### Validation Checks
- ✅ Docker service status
- ✅ Container health and logs
- ✅ Nginx configuration syntax
- ✅ Application responsiveness on specified port
- ✅ End-to-end deployment testing

## 🛡️ Security Features

- 🔐 PAT used only for Git authentication (not stored permanently)
- 🔑 SSH keys for secure server access
- 🛡️ Security headers in Nginx configuration
- 🚫 Common exploit protection (blocks .env, .git access)
- 🧹 Temporary credentials cleanup
- 📝 Comprehensive activity logging

## 📊 Logging

The script creates timestamped log files: `deploy_YYYYMMDD_HHMMSS.log`

**Logs include:**
- All user interactions and input
- Command execution results and timing
- Error messages and stack traces
- Deployment validation results
- Cleanup operations

## 🔁 Idempotency

The script is designed to be safe for multiple runs:

- 🔄 Existing repositories are updated via `git pull`
- 🛑 Old containers are stopped before new deployment
- 📝 Nginx configuration is cleanly overwritten
- 🧹 Failed deployments can be safely retried
- 🔧 Partial failures don't break subsequent runs

## 🐛 Troubleshooting

### Common Issues:

1. **SSH Connection Failed**
   - Verify SSH key permissions: `chmod 600 your-key.pem`
   - Check server accessibility: `ping your-server-ip`
   - Ensure SSH service is running on the server

2. **Git Clone Failed**
   - Verify PAT has repository access
   - Check repository URL format
   - Ensure branch exists

3. **Docker Build Failed**
   - Check Dockerfile syntax
   - Verify network connectivity for Docker images
   - Review container logs: `docker logs container-name`

4. **Application Not Accessible**
   - Verify port mappings
   - Check application logs
   - Test locally: `curl http://localhost:APP_PORT`

### Debug Mode:
Add `set -x` at the top of the script for detailed debug output.

## 📝 Example Success Output

```
✓ Deployment completed successfully!

Application Information:
-----------------------
URL: http://192.168.1.100
App Port: 3000
Server: ubuntu@192.168.1.100
Project: my-awesome-app
Log File: deploy_20241021_143022.log

Next steps:
1. Test the application at: http://192.168.1.100
2. Check logs if needed: deploy_20241021_143022.log
3. To cleanup, run: ./deploy.sh --cleanup
```

## 🗂️ File Structure

```
.
├── deploy.sh                 # Main deployment script
├── deploy_20241021_143022.log  # Example log file
└── README.md                 # This file
```

## ⚠️ Important Notes

- The script requires **sudo privileges** on the remote server for package installation
- Assumes **Ubuntu/Debian** package management (apt-get)
- Docker containers must **expose the specified application port**
- Includes **15-second wait** for container health checks
- **Self-signed SSL certificates** are not included (but ready for Certbot)

## 🆘 Support

For issues and questions:

1. **Check the deployment logs** first: `cat deploy_*.log`
2. **Verify all input parameters** are correct
3. **Test SSH connectivity** manually
4. **Check server resources** (disk space, memory)

## 📄 License

This script is provided as part of the HNG Internship DevOps track.

## 🔗 Related

- [HNG Internship](https://hng.tech/internship)
- [HNG Hire](https://hng.tech/hire)
- [HNG Premium](https://hng.tech/premium)

---

**Ready to deploy? Run** `./deploy.sh` **and follow the prompts!** 🚀