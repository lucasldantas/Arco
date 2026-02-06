#!/bin/bash

# Get the currently logged-in user (macOS)
currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')

# Ensure we have a valid username
if [ -z "$currentUser" ]; then
    echo "Error: Unable to determine the current user."
    exit 1
fi

# Define the registration token <<<<---- MODIFY BY YOUR ORGANIZATION'S TOKEN
token="eyJ1cmwiOiAiaHR0cHM6Ly91c2VhMS0wMTYuc2VudGluZWxvbmUubmV0IiwgInNpdGVfa2V5IjogIjM2ZWM1YmJmNDVhOTRiZjAifQ=="

# Define the folder and file path
folderPath="/Users/$currentUser/Library/Application Support/auditApps"
filePath="$folderPath/com.sentinelone.registration-token"

# Ensure the auditApps folder exists and set proper permissions
if ! sudo mkdir -p "$folderPath"; then
    echo "Error: Failed to create directory $folderPath"
    exit 1
fi

if ! sudo chown "$currentUser" "$folderPath"; then
    echo "Error: Failed to change ownership of $folderPath"
    exit 1
fi

if ! sudo chmod 700 "$folderPath"; then
    echo "Error: Failed to set permissions on $folderPath"
    exit 1
fi

# Write the token to the file and set proper permissions
if ! echo "$token" | sudo tee "$filePath" > /dev/null; then
    echo "Error: Failed to write the token to $filePath"
    exit 1
fi

if ! sudo chown "$currentUser" "$filePath"; then
    echo "Error: Failed to change ownership of $filePath"
    exit 1
fi

if ! sudo chmod 600 "$filePath"; then
    echo "Error: Failed to set permissions on $filePath"
    exit 1
fi

# Open the token file with nano for manual editing as the regular user
if ! sudo -u "$currentUser" nano "$filePath"; then
    echo "Error: Failed to open $filePath in nano"
    exit 1
fi

# Check if sentinelctl exists before executing
if ! command -v /usr/local/bin/sentinelctl &> /dev/null; then
    echo "Error: sentinelctl command not found."
    exit 1
fi

# Register the token with SentinelOne
if ! sudo -u "$currentUser" /usr/local/bin/sentinelctl set registration-token -- "$token"; then
    echo "Error: Failed to register the token with SentinelOne."
    exit 1
fi

# Exit successfully
echo "Registration token successfully written and applied."
exit 0
