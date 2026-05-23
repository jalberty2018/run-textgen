#!/bin/bash

# Ensure we have /workspace in all scenarios
mkdir -p /workspace

if [[ ! -d /workspace/textgen  ]]; then
	# If we don't already have /workspace/textgen , move it there
	mv /textgen  /workspace
	# Set permissions right for directory
    chmod -R 777 /workspace/textgen /user
else
	# otherwise delete the default textgen  folder which is always re-created on pod start from the Docker
	rm -rf /textgen 
fi

# Then link /textgen  folder to /workspace so it's available in that familiar location as well
ln -s /workspace/textgen  /textgen 
