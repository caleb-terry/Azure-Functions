<# 
Author: Caleb Terry
Purpose: This Azure Function is used to invite new stakeholders to the organization and add them to the specified group in Azure Active Directory.
Prerequisites:
Review the local.settings.json for a list of variables needed to run this Azure Function locally.
#>

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host 'New Stakeholder request received.'

# Expected parameters or body content
$email = $Request.Body.email
$first_name = $Request.Body.firstName
$last_name = $Request.Body.lastName

# If any of the expected parameters are not provided, return an HTTP 400 Bad Request response and exit
if (-not $first_name) {
    Write-Host 'A first name is required in order to process this request.'
    
    
    # If a first name is not provided, return an HTTP 400 Bad Request response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'A first name is required in order to process this request.'
        })

    exit 0
}

if (-not $last_name) {
    Write-Host 'A last name is required in order to process this request.'
    

    # If a last name is not provided, return an HTTP 400 Bad Request response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'A last name is required in order to process this request.'
        })

    exit 0
}

if (-not $email) {
    Write-Host 'An email is required in order to process this request.'
    

    # If an email is not provided, return an HTTP 400 Bad Request response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = 'An email is required in order to process this request.'
        })

    exit 0
}

# If all of the expected parameters are provided, return an HTTP 200 OK response and perform further processing.
Write-Host 'All expected parameters were provided. Processing request.'


# Try to connect to the Microsoft Graph API and return a failed http status code if the connection fails.
try {
    # Try to get an access token for the Microsoft Graph API using Invoke-RestMethod and return a failed http status code if the retrieval fails
    try {
        $uri = "https://login.microsoftonline.com/$env:AZURE_TENANT_ID/oauth2/v2.0/token"
        $body = @{
            client_id     = $env:APP_REGISTRATION_ID
            client_secret = $env:APP_REGISTRATION_CLIENT_SECRET
            scope         = 'https://graph.microsoft.com/.default'
            grant_type    = 'client_credentials'
        }
        $headers = @{
            'Content-Type' = 'application/x-www-form-urlencoded'
        }

        $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -Headers $headers
        $token = $response.access_token | ConvertTo-SecureString -AsPlainText
    }
    catch {
        Write-Host 'Failed to get an access token for the Microsoft Graph API.'

        # If the connection to the Microsoft Graph API fails, return an HTTP 500 Internal Server Error response.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = 'Failed to get an access token for the Microsoft Graph API.'
            })

        exit 0
    }

    Write-Host 'Connecting to the Microsoft Graph API.'

    # Connect to the Microsoft Graph API.
    Connect-MgGraph -AccessToken $token | Out-Null
}
catch {
    Write-Host 'Failed to connect to the Microsoft Graph API.'

    # If the connection to the Microsoft Graph API fails, return an HTTP 500 Internal Server Error response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = 'Failed to connect to the Microsoft Graph API:'
        })

    exit 0
}

# Check if the user's email address is already in the list of users in Azure AD and if so, don't invite the user but add them to the group.
Write-Host 'Checking if the user already exists in Azure Active Directory.'

# Try to get the user from Azure Active Directory and return a failed http status code if the retrieval fails.
try {
    # Get the user from Azure Active Directory.
    $existing_user = Get-MgUser -Filter "mail eq '$email'"
}
catch {
    Write-Host 'Failed to get the user from Azure Active Directory.'

    # If the retrieval of the user from Azure Active Directory fails, return an HTTP 500 Internal Server Error response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = 'Failed to get the user from Azure Active Directory.'
        })

    exit 0
}

# If the user was successfully retrieved from Azure Active Directory, add the user to the group in Azure Active Directory.
if ($existing_user) {
    Write-Host 'User already exists in Azure Active Directory. Checking if user is already a member of the group.'

    # Check if the user is already a member of the group in Azure Active Directory.
    $existing_user_id = $existing_user.Id
    $user_is_member = Get-MgGroupMember -GroupId $env:GROUP_ID -Filter "Id eq '$existing_user_id'"

    if (-not $user_is_member) {
        # Try adding the user to the group in Azure Active Directory and return a failed http status code if the addition fails.
        try {
            Write-Host 'Adding user to the group in Azure Active Directory.'

            # Add the user to the group in Azure Active Directory.
            $group = New-MgGroupMember -GroupId $env:GROUP_ID -DirectoryObjectId $existing_user.Id
        }
        catch {
            Write-Host 'Failed to add user to the group in Azure Active Directory.'

            # If the addition of the user to the group in Azure Active Directory fails, return an HTTP 500 Internal Server Error response.
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::InternalServerError
                    Body       = 'Failed to add user to the group in Azure Active Directory.'
                })

            exit 0
        }

        # If everything was successful, return an HTTP 200 OK response.
        Write-Host 'Successfully processed request.'
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = "Successfully processed request. $email was already a member of the organization but we went ahead and added them to the group."
            })

        exit 0
    }

    # If everything was successful, return an HTTP 200 OK response.
    Write-Host 'Successfully processed request.'
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = "Successfully processed request. $email was already a member of the organization and the group so we didn't take any action."
        })

    exit 0
}

# If the user was not successfully retrieved from Azure Active Directory, invite the user to the organization.
Write-Host 'User does not exist in Azure Active Directory. Inviting user to the organization.'

# Try creating a new mginvitation object and return a failed http status code if the creation fails.
try {
    Write-Host 'Creating a new invitation object.'

    $invitedUserEmailAddress = $email
    $invitedRedirectUrl = $env:INVITED_USER_REDIRECT_URL
    $invitedUserDisplayName = "$first_name $last_name"

    # Create a new invitation object.
    $invitation = New-MgInvitation `
        -InvitedUserDisplayName $invitedUserDisplayName `
        -InviteRedirectUrl $invitedRedirectUrl `
        -InvitedUserEmailAddress $invitedUserEmailAddress `
        -SendInvitationMessage:$true
}
catch {
    Write-Error 'Failed to create a new invitation object.'
    
    # If the creation of the new invitation object fails, return an HTTP 500 Internal Server Error response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = 'Failed to create a new invitation object.'
        })

    exit 0
}

# If the invitation was successfully created, add the new stakeholder to the group in Azure Active Directory.
Write-Host 'Invitation successfully created. Adding user to the group in Azure Active Directory.'

# Try adding the user to the group in Azure Active Directory and return a failed http status code if the addition fails.
try {
    Write-Host 'Adding user to the group in Azure Active Directory.'

    # Add the user to the group in Azure Active Directory.
    $group = New-MgGroupMember -GroupId $env:GROUP_ID -DirectoryObjectId $invitation.InvitedUser.Id
}
catch {
    Write-Host 'Failed to add user to the group in Azure Active Directory.'

    # If the addition of the user to the group in Azure Active Directory fails, return an HTTP 500 Internal Server Error response.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = 'Failed to add user to the group in Azure Active Directory.'
        })

    exit 0
}

# If everything was successful, return an HTTP 200 OK response.
Write-Host 'Successfully processed request.'
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = "Successfully processed request. $email has been invited to the organization."
    })
