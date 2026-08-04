output "iapetus_ip" {
  description = "MinIO VM's MGMT-VLAN IP address"
  value       = "10.10.10.24"
}

output "minio_s3_endpoint" {
  description = "S3-compatible endpoint for use as an OpenTofu backend in other configs"
  value       = "http://iapetus.orbit.solsys.dev:9000"
}