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
    }
}

resource azurerm_resource_group res_group {
  name     = "pzaz_esw1"
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

resource azurerm_mssql_server db_srv {
  name = "pzaz-sql-${random_string.db_postfix.result}" 
  resource_group_name = local.res_grp
  location = local.location
  version = "12.0"
  administrator_login = "adminlogin"
  administrator_login_password = "paad123!!!"
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

    connection_string {
        name="CatalogConnection"
        type="SQLAzure"
        value="Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_db.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${azurerm_mssql_server.db_srv.administrator_login_password}';"
    }
    connection_string {
        name="IdentityConnection"
        type="SQLAzure"
        value="Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_idnt.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${azurerm_mssql_server.db_srv.administrator_login_password}';"
    }
       
    site_config {
        always_on=false #because free tier
        
        application_stack {
            dotnet_version = "v7.0"
        } 

    }
    app_settings = {
        "ASPNETCORE_ENVIRONMENT" = "Development" 
    }
  
}

resource null_resource deploy_web_zip {
    provisioner "local-exec" {
        command = "az webapp deploy --resource-group ${local.res_grp} --name ${azurerm_windows_web_app.web_app.name} --src-path ../src/Web/obj/Release/net7.0/PubTmp/Web-20230324185459081.zip"
        interpreter = ["PowerShell", "-Command"]
    }

  depends_on = [azurerm_windows_web_app.web_app]
}



output ms_connection {
  value =  nonsensitive("Data Source=tcp:${azurerm_mssql_server.db_srv.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db_db.name};User Id=${azurerm_mssql_server.db_srv.administrator_login};Password='${azurerm_mssql_server.db_srv.administrator_login_password}';")
}