terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "=3.46.0"
    }
  }
}

provider azurerm {
  features {
    resource_group {      
      prevent_deletion_if_contains_resources = false
    }
  }
}

resource azurerm_resource_group res_group {
  name     = "pzaz_esw"
  location = "West Europe"
}

locals {
  res_grp = azurerm_resource_group.res_group.name
  location = azurerm_resource_group.res_group.location
}

resource random_string db_postfix {
  length = 3
  special = false
  upper = false
}


###################################################################################################

data azurerm_client_config current {}

resource random_string connect_pass {
  length = 8
  special = true
  upper = true
}

resource azurerm_key_vault kv_webapp {
  name = "key-vault-pzaz-${random_string.db_postfix.result}"
  resource_group_name = local.res_grp
  location = local.location
  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name = "standard"
}

resource azurerm_key_vault_access_policy kv_to_user {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "Delete",
    "Purge",
    "Recover",
    "List"
  ]

  secret_permissions = [
    "Set",
    "Get",
    "Delete",
    "Purge",
    "Recover",
    "List"
  ]
} 

/* resource azurerm_key_vault_access_policy kv {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
  ] 

  secret_permissions = [
    "Get",
  ]
} */
/* 
resource azurerm_key_vault_access_policy kv_web_app {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.web_app.identity[0].principal_id

  secret_permissions = [
    "Get",
  ]
} */



resource azurerm_key_vault_secret kv_pass_catalog {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  name = "SQLPasswordCatalog"
  value = random_string.connect_pass.result
  depends_on = [
    azurerm_key_vault_access_policy.kv_to_user
  ]
}

resource azurerm_key_vault_secret kv_catalog_connection_string {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  name = "SQLCatalogConnectionString"
  value = "Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_db.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${random_string.connect_pass.result}';"
  depends_on = [
    azurerm_key_vault_access_policy.kv_to_user
  ]
}
resource azurerm_key_vault_secret kv_identity_connection_string {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  name = "SQLIdentityConnectionString"
  value = "Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_idnt.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${random_string.connect_pass.result}';"
  depends_on = [
    azurerm_key_vault_access_policy.kv_to_user
  ]
}

###################################################################################################
resource azurerm_mssql_server db_srv {
  name = "pzaz-sql-${random_string.db_postfix.result}" 
  resource_group_name = local.res_grp
  location = local.location
  version = "12.0"
  administrator_login = "adminlogin"
  administrator_login_password = random_string.connect_pass.result
}

resource azurerm_mssql_firewall_rule db_srv_firewall {
    name = "${azurerm_mssql_server.db_srv.name}-access-rule"
    server_id = azurerm_mssql_server.db_srv.id
    start_ip_address = "0.0.0.0" #any
    end_ip_address   = "0.0.0.0" #any
}

resource azurerm_mssql_database db_db {
  name      = "pzaz-db-esd-${random_string.db_postfix.result}"
  server_id = azurerm_mssql_server.db_srv.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
}

resource azurerm_mssql_database db_idnt {
  name      = "pzaz-db-esd-idnt-${random_string.db_postfix.result}"
  server_id = azurerm_mssql_server.db_srv.id
  collation = "SQL_Latin1_General_CP1_CI_AS"
}

resource azurerm_service_plan web_service_plan {
    name = "web_part_plan"
    resource_group_name = local.res_grp
    location = local.location
    sku_name = "F1"
    os_type = "Windows"
}

resource azurerm_windows_web_app web_app {
    name = "eShopWeb-${random_string.db_postfix.result}"
    resource_group_name = local.res_grp
    location = local.location
    service_plan_id = azurerm_service_plan.web_service_plan.id

  #  key_vault_reference_identity_id = azurerm_key_vault.kv_webapp.id

    
    identity {
      type = "SystemAssigned"
    }
    #https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references?tabs=azure-cli
    connection_string {
        name="CatalogConnection"
        type="SQLAzure"
        value="@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv_webapp.name};SecretName=${azurerm_key_vault_secret.kv_catalog_connection_string.name})"
    }
    connection_string {
        name="IdentityConnection"
        type="SQLAzure"
        value="@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv_webapp.name};SecretName=${azurerm_key_vault_secret.kv_identity_connection_string.name})"
    }
       
    site_config {
        always_on=false #because free tier
        
        application_stack {
            dotnet_version = "v7.0"
        } 

    }

    logs {
      application_logs {
        file_system_level = "Information"
      }
      http_logs {
        file_system {
            retention_in_days = 30
            retention_in_mb   = 25
        }
      }
    }

    app_settings = {
        "ASPNETCORE_ENVIRONMENT" = "Development"
        "APPINSIGHTS_INSTRUMENTATIONKEY" =  azurerm_application_insights.esw_insight.instrumentation_key
        "APPLICATIONINSIGHTS_CONNECTION_STRING" =  azurerm_application_insights.esw_insight.connection_string
        "KEY_VAULT" =  azurerm_key_vault.kv_webapp.id
        "TestKeyValut"="@Microsoft.KeyVault(VaultName=${azurerm_key_vault.kv_webapp.name};SecretName=${azurerm_key_vault_secret.kv_pass_catalog.name})"
    }
  
  depends_on = [
    azurerm_application_insights.esw_insight
  ]

}

###################################################################################################

resource azurerm_key_vault_access_policy kv_to_webapp {
  key_vault_id = azurerm_key_vault.kv_webapp.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.web_app.identity[0].principal_id

  key_permissions = [
    "Get",
  ] 

  secret_permissions = [
    "Get",
  ]
} 


resource null_resource deploy_web_zip {
    provisioner "local-exec" {
        command = "az webapp deploy --resource-group ${local.res_grp} --name ${azurerm_windows_web_app.web_app.name} --src-path ../src/Web/obj/Release/net7.0/PubTmp/Web-20230325180426612.zip"
        interpreter = ["PowerShell", "-Command"]
    }

  depends_on = [azurerm_windows_web_app.web_app]
}


resource azurerm_application_insights esw_insight {
  name                = "insights-${random_string.db_postfix.result}"
  resource_group_name = local.res_grp
  location            = local.location
  application_type    = "web"
}



output ms_connection {
  value =  nonsensitive("Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_db.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${azurerm_mssql_server.db_srv.administrator_login_password}';")
}