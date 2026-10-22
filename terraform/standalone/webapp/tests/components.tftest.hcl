mock_provider "azurerm" {}
variables {
  subscription_id = "22222222-2222-2222-2222-222222222222"
  name            = "testwebsite"
}
run "own_plan" {
  command = plan
  assert {
    condition     = length(azurerm_service_plan.webapp) == 1
    error_message = "The independent website needs a plan when none is supplied."
  }
}
run "reuse_plan" {
  command = plan
  variables {
    existing_service_plan_id = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/shared/providers/Microsoft.Web/serverFarms/shared"
  }
  assert {
    condition     = length(azurerm_service_plan.webapp) == 0
    error_message = "A supplied plan must remain externally owned."
  }
}
