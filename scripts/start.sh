#!/bin/bash

echo "=== JDK CodeQL Builder ==="
echo "This container is set up to build CodeQL databases for JDK sources."
echo ""
echo "Available directories:"
echo "  - /app/bootjdk  : Place your Boot JDK here"
echo "  - /app/source   : Place your JDK source code here"
echo "  - /app/codeql   : Place your CodeQL CLI here"
echo "  - /app/database : Output directory for CodeQL databases"
echo ""

if [ "${AUTO_BUILD}" = "true" ]; then
    echo "AUTO_BUILD is enabled, starting database build automatically..."
    /app/scripts/build-db.sh

    if [ $? -eq 0 ]; then
        echo "Build completed successfully!"
    else
        echo "Build failed! Check the logs for details."
    fi
else
    echo "AUTO_BUILD is disabled. Use './scripts/build-db.sh' to build manually."
fi