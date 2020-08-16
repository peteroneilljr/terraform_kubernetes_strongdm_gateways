resource "kubernetes_namespace" "sdm_gateway" {
  count = var.gateway_count > 0 ? 1:0
  metadata {
    name = var.namespace
    labels = {
      app = var.sdm_app_name
    }
  }
}

resource "kubernetes_service" "sdm_gateway" {
  count = var.gateway_count

  metadata {
    name      = "${var.sdm_gateway_name}-${count.index}"
    namespace = kubernetes_namespace.sdm_gateway[0].id
    labels = {
      app = var.sdm_app_name
    }
  }
  spec {
    selector = {
      app = var.sdm_app_name
    }
    port {
      port = var.sdm_port
    }
    type = "LoadBalancer"
  }
}

resource "sdm_node" "gateway" {
  count = var.gateway_count

  gateway {
    name           = "${var.sdm_gateway_name}-${count.index}"
    listen_address = "${coalesce(kubernetes_service.sdm_gateway[count.index].load_balancer_ingress.0.hostname, kubernetes_service.sdm_gateway[count.index].load_balancer_ingress.0.ip)}:${var.sdm_port}"
  }
}
resource "kubernetes_secret" "sdm_gateway" {
  count = var.gateway_count

  metadata {
    name      = "${var.sdm_gateway_name}-${count.index}"
    namespace = kubernetes_namespace.sdm_gateway[0].id
  }
  type = "Opaque"
  data = {
    token = sdm_node.gateway[count.index].gateway.0.token
  }
}
resource "kubernetes_deployment" "sdm_gateway" {
  count = var.gateway_count

  metadata {
    name      = "${var.sdm_gateway_name}-${count.index}"
    namespace = kubernetes_namespace.sdm_gateway[0].id
    labels = {
      app = var.sdm_app_name
    }
  }
  spec {
    replicas = 1 # Required to be 1

    selector {
      match_labels = {
        app = var.sdm_app_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.sdm_app_name
        }
      }
      spec {
        container {
          image             = "quay.io/sdmrepo/relay:latest"
          image_pull_policy = "Always"
          name              = var.sdm_app_name
          resources {
            requests {
              cpu    = var.dev_mode ? "200m" : "2000m"
              memory = var.dev_mode ? "400Mi" : "4000Mi"
            }
          }
          env {
            name  = "SDM_ORCHESTRATOR_PROBES"
            value = ":9090"
          }
          env {
            name = "SDM_RELAY_TOKEN"
            value_from {
              secret_key_ref {
                key  = "token"
                name = kubernetes_secret.sdm_gateway[count.index].metadata.0.name
              }
            }
          }
          liveness_probe {
            http_get {
              path = "/liveness"
              port = 9090
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}


