terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Using default VPC
data "aws_vpc" "capstone_default" {
  default = true
}

output "default_vpc_id" {
  description = "ID of the default VPC"
  value       = data.aws_vpc.capstone_default.id
}
# Using default subnets

data "aws_subnets" "capstone_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.capstone_default.id]
  }

  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

output "default_subnets_ids" {
  description = "ID of subnets"
  value       = data.aws_subnets.capstone_subnets.ids
}
# Create EKS Cluster

resource "aws_eks_cluster" "capstone_eks" {
  name = "capstone_eks"

  access_config {
    authentication_mode = "API"
  }

  role_arn = aws_iam_role.cluster.arn
  version  = "1.35"

  vpc_config {
    subnet_ids = data.aws_subnets.capstone_subnets.ids
  }

  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
  ]
}

# Create EKS Access Entry and Policy Association
data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "me" {
  cluster_name  = aws_eks_cluster.capstone_eks.name
  principal_arn = data.aws_caller_identity.current.arn
}

resource "aws_eks_access_policy_association" "me" {
  cluster_name  = aws_eks_cluster.capstone_eks.name
  principal_arn = aws_eks_access_entry.me.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
resource "aws_eks_access_entry" "github-deploy" {
  cluster_name  = aws_eks_cluster.capstone_eks.name
  principal_arn = "arn:aws:iam::881050425297:user/github-deploy"
}

resource "aws_eks_access_policy_association" "github-deploy" {
  cluster_name  = aws_eks_cluster.capstone_eks.name
  principal_arn = aws_eks_access_entry.github-deploy.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["default"]
  }
}
# Create IAM Role for EKS Cluster

resource "aws_iam_role" "cluster" {
  name = "eks-cluster-capstone"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# IAM Role for EKS Node Group

resource "aws_iam_role" "capstone_eks_iam_role" {
  name = "eks-node-group-capstone"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "capstone_eks_iam_role-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.capstone_eks_iam_role.name
}

resource "aws_iam_role_policy_attachment" "capstone_eks_iam_role-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.capstone_eks_iam_role.name
}

resource "aws_iam_role_policy_attachment" "capstone_eks_iam_role-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.capstone_eks_iam_role.name
}


# Create EKS Node Group

resource "aws_eks_node_group" "capstone_eks_node_group" {
  cluster_name    = aws_eks_cluster.capstone_eks.name
  node_group_name = "capstone-eks-node-group"
  node_role_arn   = aws_iam_role.capstone_eks_iam_role.arn
  subnet_ids      = data.aws_subnets.capstone_subnets.ids
  instance_types  = ["m7i-flex.large"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.capstone_eks_iam_role-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.capstone_eks_iam_role-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.capstone_eks_iam_role-AmazonEC2ContainerRegistryReadOnly,
  ]
}
