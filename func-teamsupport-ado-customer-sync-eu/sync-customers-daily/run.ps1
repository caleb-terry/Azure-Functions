# Input bindings are passed in via param block.
param($Timer)

function Get-NewTeamsupportCustomers () {
    <# 
# Filter with date fields
# All filters are set to equal the value that you specify, except for dates. 
Dates and times are handled differently. 
The dates that are returned are greater than the date specified in the filter. 
They also require a special format of YYYYMMDDHHMMSS. 
All 14 characters must be included, and the date must be UTC with a 24 hour format
#>
    # Set variables
    $org_id = $env:TEAMSUPPORT_ORG_ID
    $api_key = $env:TEAMSUPPORT_API_KEY

    # Format the date for the API with Get-Date but 2 days ago
    $days_ago = $config.Teamsupport.DAYS_AGO
    $creation_date_period = (Get-Date).AddDays(-$days_ago)
    $formatted_date = $creation_date_period.ToString("yyyyMMddHHmmss")

    # Set the API endpoint to retrieve new Teamsupport customers
    $teamsupport_customer_endpoint = "$TEAMSUPPORT_BASE_URL/api/json/customers?DateCreated=$formatted_date"

    # Take organization id and api key and create a base64 encoded string
    $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $org_id, $api_key)))

    # Create a header with the authorization string 
    $headers = @{
        "Authorization" = "Basic $auth"
    }

    # Lists all the customers
    Write-Host "Getting new customers from Teamsupport"
    $response = (Invoke-RestMethod -Uri $teamsupport_customer_endpoint -Method Get -Headers $headers).Customers.Name

    # Check if there are no new customers
    if ($null -eq $response) {
        Write-Host "No new customers found"
        exit
    }

    # Return the customer names
    Write-Host "New customer found: $response"
    $response.Customers.Name
}

function Update-ADOCustomers() {
    # Set variables
    # Check Teamsupport for new customers
    $new_teamsupport_customers = Get-NewTeamsupportCustomers

    $ado_pat = $env:AZURE_DEVOPS_BASE_URL
    $ado_base_url = "$env:AZURE_DEVOPS_BASE_URL/_apis/"
    $custom_field_name = $env:AZURE_DEVOPS_PICKLIST_FIELD_NAME

    # Base64 encode the pat
    $encoded_ado_pat = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$ado_pat"))

    $headers = @{
        "Authorization" = "Basic $encoded_ado_pat"
        "Content-Type"  = "application/json"
    }

    # Get the picklist ID from the custom field
    Write-Host "Retrieving picklist ID from ADO"
    $pick_list_id = (Invoke-RestMethod -Uri "$ado_base_url/wit/fields/Custom.$custom_field_name`?api-version=7.0" -Headers $headers -Method Get).picklistId

    try {
        # Get the current picklist data
        Write-Host "Getting current customer list from ADO"
        $current_customer_picklist_settings = Invoke-RestMethod -Uri "$ado_base_url/work/processes/lists/$pick_list_id`?api-version=7.0" -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to get current customer list from ADO: $_"
        exit
    }

    # Extract current items
    $current_ado_picklist_items = $current_customer_picklist_settings.items

    # Find the customers that don't already exist in the current items
    $new_teamsupport_customer_to_add = $new_teamsupport_customers | Where-Object { $_ -notin $current_ado_picklist_items }

    # If there are no new customers to add, exit
    if ($null -eq $new_teamsupport_customer_to_add -or $new_teamsupport_customer_to_add.Count -eq 0) {
        Write-Host "No new customers to add"
        exit
    }

    # Combine current items with new customers to be added
    $combined_items = $current_ado_picklist_items + $new_teamsupport_customer_to_add

    # Build the object to update the customer list
    $updated_customer_picklist_settings = @{
        "id"          = $current_customer_picklist_settings.id
        "name"        = $current_customer_picklist_settings.name
        "type"        = $current_customer_picklist_settings.type
        "items"       = $combined_items  # Directly assign the unique items
        "isSuggested" = $current_customer_picklist_settings.isSuggested
        "url"         = $current_customer_picklist_settings.url
    }

    # Convert the body to json
    $picklist_json_body = $updated_customer_picklist_settings | ConvertTo-Json

    # Update the customer list
 
    try {
        $pick_list_url = "$ado_base_url/work/processes/lists/$pick_list_id`?api-version=7.0"
        
        Write-Host "Adding new customers to customer list in ADO: $new_teamsupport_customer_to_add"
        Invoke-RestMethod -Uri $pick_list_url -Headers $headers -Body $picklist_json_body -Method Put | Out-Null
    }
    catch {
        Write-Host "Failed to update customer list in ADO: $_"
        exit
    }
}

Update-ADOCustomers