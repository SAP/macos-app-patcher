#!/bin/bash

# SAPCorp_Privileges2_Uninstall.sh, 0.1.0
# (c) 2026, SAP SE (Marc Thielemann <marc.thielemann@sap.com>)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#  
# http://www.apache.org/licenses/LICENSE-2.0
#  
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# latest change:
# 2026/08/04


exitCode=0

# this script must be run with root privileges
if [[ "$(/usr/bin/id -u)" -eq 0 ]]; then
	
	# redirect all output to /dev/null
	exec >/dev/null 2>&1
	
	currentUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')
	
	if [[ -n "$currentUser" && "$currentUser" != "root" ]]; then
	
		
		# unload the launch agent and quit all of our applications
		/bin/launchctl bootout gui/$(/usr/bin/id -u "$currentUser") /Library/LaunchAgents/corp.sap.PatcherAgent.plist
		/bin/sleep 2 && /usr/bin/sudo -u "$currentUser" /usr/bin/killall "Patcher" "PatcherAgent"
			
		# delete user-specific files
		userHome=$(/usr/bin/dscl . -read "/Users/$currentUser" NFSHomeDirectory | /usr/bin/sed 's/^[^\/]*//g')
		
		if [[ -d "$userHome" && "$userHome" != "/var/empty" ]]; then
		
			/usr/bin/sudo -u "$currentUser" /usr/bin/defaults delete corp.sap.Patcher
			/bin/rm -rf "${userHome}/Library/Containers/Containers/corp.sap.Patcher"*
		fi
	fi
	
	# unload the launchd plist
	/bin/launchctl bootout system /Library/LaunchDaemons/corp.sap.PatcherDaemon.plist
	
	# just for sure ...
	/bin/sleep 2 && /usr/bin/killall /usr/bin/killall "PatcherDaemon"
	
	# remove the global preferences
	/usr/bin/defaults delete /Library/Preferences/corp.sap.Patcher.plist
	
	# remove the global stuff
	/bin/rm -rf "/Library/LaunchDaemons/corp.sap.Patcher"* \
				"/Library/LaunchAgents/corp.sap.Patcher"* \
				"/Library/Preferences/corp.sap.Patcher"* \
				"/Applications/Patcher.app" \
				"/Library/Application Support/JAMF/Receipts/Patcher_"*.pkg
	
	# remove the package receipt
	/usr/sbin/pkgutil --forget "corp.sap.Patcher.pkg"

else
	echo "You must be root in order to run this script!"
	exitCode=1
fi

exit $exitCode
