terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
      version = "2.15.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.32.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.6"
    }
  }
}

provider "kubernetes" {
  config_path = "<path to your kube config file>"
}

provider "helm" {
  kubernetes {
    config_path = "<path to your kube config file>"
  }

  # fill in if necessary
  # registry {
  #   url = "https://gitlab.homelab.me:5050"
  #   username = var.registry_username
  #   password = var.registry_password
  # }
}
