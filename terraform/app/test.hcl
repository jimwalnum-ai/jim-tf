# test.nomad.hcl
  job "test" {
    datacenters = ["dc1"]
    type        = "batch"
    group "echo" {
      task "hello" {
        driver = "docker"
        config {
          image   = "alpine:latest"
          command = "echo"
          args    = ["Hello from Nomad!"]
        }
      }
    }
  }