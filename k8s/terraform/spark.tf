resource "kubernetes_namespace" "spark" {
  metadata {
    name = "spark"
  }
}

resource "kubernetes_role" "spark-role" {
  metadata {
    name = "spark-role"
    namespace = "spark"
  }

  rule {
    api_groups = [ "" ]
    resources = [ "pods", "persistentvolumeclaims", "configmaps", "services" ]
    verbs = [ "get", "deletecollection", "create", "list", "watch", "delete", "edit" ]
  }
}

resource "kubernetes_service_account" "spark-accout" {
  metadata {
    name = "spark-account"
    namespace = "spark"
  }

  automount_service_account_token = true
}

resource "kubernetes_role_binding" "spark-rolebinding" {
  metadata {
    name = "spark-rolebiding"
    namespace = "spark"
  }
  
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.spark-accout.metadata[0].name
    namespace = kubernetes_namespace.spark.metadata[0].name
  }
  
  role_ref {
    kind = "Role"
    name = kubernetes_role.spark-role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_secret" "spark-account-sa-secret" {
  metadata {
    name = "spark-sa-secret"
    namespace = "spark"

    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.spark-accout.metadata.0.name
    }

    generate_name = "spark-sa-"
  }

  type = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}

data "kubernetes_secret" "spark-accout-sa-token" {
  metadata {
    name = kubernetes_secret.spark-account-sa-secret.metadata[0].name
    namespace = "spark"
  }
}

resource "local_file" "spar-accout-sa-token" {
  content = data.kubernetes_secret.spark-accout-sa-token.data["token"]
  filename = "<path you want to place this file>"
}

resource "kubernetes_deployment" "spark-client" {
  metadata {
    name = "spark-client"
    namespace = "spark"
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "spark-client"
      }
    }
    template {
      metadata {
        labels = {
          app = "spark-client"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.spark-accout.metadata[0].name
        container {
          name = "spark-client"
          image = "davidho9717/spark:3.4.4-jupyter"

          command = [ "jupyter" ]
          args = ["lab", "--allow-root", "--ServerApp.allow_remote_access=true", "--ip=0.0.0.0"]

          port {
            name = "notebook"
            container_port = 8888
          }

          port {
            name = "driver-port"
            container_port = 8002
          }

          port {
            name = "block-manager"
            container_port = 8001
          }

          port {
            name = "web-ui"
            container_port = 4040
          }

          port {
            name = "shuffle-service"
            container_port = 7337
          }

        }
      }
    }
  }
}

resource "kubernetes_service" "spark-client-svc" {
  metadata {
    name = "spark-client-svc"
    namespace = "spark"
  }

  spec {
    cluster_ip = "None"
    
    selector = {
      app = "spark-client"
    }
  
    port {
      name = "suffle-service"
      port = 7337
      target_port = 7337
    }

    port {
      name = "web-ui"
      port = 4040
      target_port = 4040
    }

    port {
      name = "block-manager"
      port = 8001
      target_port = 8001
    }

    port {
      name = "driver-port"
      port = 8002
      target_port = 8002
    }

    port {
      name = "notebook"
      port = 8888
      target_port = 8888
    }
  }
}

resource "kubernetes_ingress_v1" "spark-jupyter-ingress" {
  metadata {
    namespace = kubernetes_namespace.spark.metadata[0].name
    name = "spark-jupyter-ingress"
  }

  spec {
    rule {
      host = "spark-jupyter.homelab.me"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.spark-client-svc.metadata[0].name
              port {
                number = 8888
              }
            }
          }
        }
      }
    }

    rule {
      host = "spark-webui.homelab.me"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.spark-client-svc.metadata[0].name
              port {
                number = 4040
              }
            }
          }
        }
      }
    }

    rule {
      host = "spark-driver.homelab.me"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.spark-client-svc.metadata[0].name
              port {
                number = 8002
              }
            }
          }
        }
      }
    }

    rule {
      host = "spark-bm.homelab.me"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.spark-client-svc.metadata[0].name
              port {
                number = 8001
              }
            }
          }
        }
      }
    }

    rule {
      host = "spark-ss.homelab.me"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.spark-client-svc.metadata[0].name
              port {
                number = 7337
              }
            }
          }
        }
      }

    }

  }

}