property emacsclientPath : "__EMACSCLIENT__"
property maximumAttempts : 100

on clientCommand()
	set socketPath to "/tmp/emacs" & (do shell script "/usr/bin/id -u") & "/server"
	return quoted form of emacsclientPath & " --socket-name=" & quoted form of socketPath
end clientCommand

on waitForDaemon(client)
	set attempts to maximumAttempts as text
	set waitCommand to "attempt=0; until " & client & " --eval t >/dev/null 2>&1; do attempt=$((attempt + 1)); if [ \"$attempt\" -ge " & attempts & " ]; then exit 1; fi; /bin/sleep 0.1; done"
	try
		do shell script waitCommand
		return true
	on error
		display alert "Emacs daemon is unavailable" message "The Homebrew Emacs service did not become ready within 10 seconds."
		return false
	end try
end waitForDaemon

on invokeClient(clientArguments)
	set client to my clientCommand()
	if my waitForDaemon(client) then
		try
			do shell script client & " " & clientArguments
		on error errorMessage
			display alert "Emacs Client failed" message errorMessage
		end try
	end if
end invokeClient

on run
	my invokeClient("-c -n")
end run

on open droppedItems
	set clientArguments to "-c -n"
	repeat with droppedItem in droppedItems
		set clientArguments to clientArguments & " " & quoted form of POSIX path of droppedItem
	end repeat
	my invokeClient(clientArguments)
end open

on open location targetURL
	my invokeClient("-n " & quoted form of targetURL)
end open location
