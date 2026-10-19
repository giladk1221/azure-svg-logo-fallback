variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "service_plan_id" { type = string }
variable "tags" { type = map(string) }
resource "azurerm_linux_web_app" "demo" {
  name                                           = "${var.name}-webapp"
  resource_group_name                            = var.resource_group_name
  location                                       = var.location
  service_plan_id                                = var.service_plan_id
  public_network_access_enabled                  = false
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  site_config {
    always_on               = true
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    ftps_state              = "Disabled"
    application_stack { node_version = "22-lts" }
    app_command_line = "node -e \"const http=require('node:http');const m={exports:{}};new Function('require','module','process',Buffer.from(process.env.DEMO_SERVER_B64,'base64').toString())(require,m,process);http.createServer(m.exports).listen(Number(process.env.PORT)||8080,'0.0.0.0')\""
  }
  app_settings = { DEMO_SERVER_B64 = filebase64("${path.module}/../../../webapp/server.js") }
  tags         = var.tags
}
output "id" { value = azurerm_linux_web_app.demo.id }
output "hostname" { value = azurerm_linux_web_app.demo.default_hostname }
