# Neo4j Kubernetes Template for Coder

This template deploys Neo4j graph database on Kubernetes with a development workspace that includes access to Neo4j Browser and tools.

## Features

- **Neo4j Database**: Latest Neo4j Community Edition with configurable resources
- **Neo4j Browser**: Web-based interface accessible through Coder apps
- **APOC Plugin**: Advanced procedures and functions for Neo4j
- **Persistent Storage**: Configurable storage for Neo4j data
- **Port Forwarding**: Secure access to Neo4j services through Kubernetes port forwarding
- **Development Environment**: Ubuntu-based workspace with kubectl and development tools

## Prerequisites

- Kubernetes cluster with Helm support
- Coder deployment with Kubernetes provider configured
- Storage class available for persistent volumes
- Neo4j Helm repository access

## Configuration Parameters

| Parameter | Description | Default | Options |
|-----------|-------------|---------|----------|
| `cpu` | CPU cores for Neo4j | 2 | 2, 4, 6, 8 |
| `memory` | Memory in GB for Neo4j | 4 | 4, 8, 16, 32 |
| `storage` | Storage in GB for Neo4j data | 10 | 10, 20, 50, 100 |
| `neo4j_password` | Admin password for Neo4j | - | User-defined (sensitive) |
| `neo4j_version` | Neo4j Helm chart version | 5.22.0 | 5.22.0, 5.21.0, 5.20.0 |
| `storage_class` | Kubernetes storage class | standard | User-defined |

## Template Variables

| Variable | Description | Default |
|----------|-------------|----------|
| `use_kubeconfig` | Use host kubeconfig for authentication | false |
| `workspaces_namespace` | Kubernetes namespace for workspaces | coder-workspaces |

## Access Information

### Neo4j Browser
- **URL**: Available through Coder apps as "Neo4j Browser"
- **Direct URL**: `http://localhost:7474`
- **Username**: `neo4j`
- **Password**: As configured during workspace creation

### Neo4j Bolt Connection
- **URL**: `bolt://localhost:7687`
- **Username**: `neo4j`
- **Password**: As configured during workspace creation

## Deployment

1. **Add the template** to your Coder deployment
2. **Configure variables** according to your Kubernetes setup
3. **Create workspace** and set the required parameters
4. **Wait for deployment** - Neo4j will be automatically deployed and configured
5. **Access Neo4j Browser** through the Coder apps interface

## Security Features

- **ClusterIP Service**: Neo4j is not directly exposed outside the cluster
- **Port Forwarding**: Secure access through Kubernetes port forwarding
- **Sensitive Parameters**: Password is marked as sensitive and encrypted
- **RBAC**: Uses Kubernetes service accounts for secure access

## Included Tools

- **kubectl**: Kubernetes command-line tool
- **Neo4j Browser**: Web-based database interface
- **APOC Procedures**: Extended functionality for Neo4j
- **Development Environment**: Full Ubuntu workspace for development

## Monitoring

The workspace includes metadata displays for:
- CPU and memory usage
- Disk usage
- Neo4j pod status
- Connection information

## Troubleshooting

### Neo4j Not Starting
- Check pod logs: `kubectl logs -l app.kubernetes.io/name=neo4j -n coder-workspaces`
- Verify storage class exists and is accessible
- Ensure sufficient resources are available in the cluster

### Cannot Access Neo4j Browser
- Verify port forwarding is active in the workspace
- Check that Neo4j pod is running and ready
- Ensure firewall rules allow local port access

### Connection Issues
- Verify the password is correct
- Check that bolt port (7687) is forwarded
- Ensure Neo4j service is accessible within the cluster

## Customization

You can customize this template by:
- Adding additional Neo4j plugins
- Modifying resource limits and requests
- Adding custom Neo4j configuration
- Including additional development tools
- Configuring backup and monitoring solutions

## Support

For issues with:
- **Template**: Check Coder documentation and logs
- **Neo4j**: Refer to Neo4j documentation and community
- **Kubernetes**: Verify cluster configuration and permissions
