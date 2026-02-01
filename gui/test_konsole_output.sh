#!/bin/bash
# Test script to simulate the Konsole command execution

LOG_FILE="/tmp/test-wifi-output-$$.log"
MARKER_FILE="$LOG_FILE.done"

echo "Testing output capture with marker file..."
echo "Log file: $LOG_FILE"
echo "Marker file: $MARKER_FILE"
echo ""

# Clean up any old files
rm -f "$LOG_FILE" "$MARKER_FILE"

# Simulate what Konsole will run
echo "Running command in background..."
konsole --hold -e bash -c "cd /home/fs1/Projects/finjener-projects/wifi-management_p/wifi-management && bash ./wifi-manager.sh sync-local 2>&1 | tee '$LOG_FILE'; echo \$? > '$MARKER_FILE'" &

echo "Waiting for marker file to appear..."
while [ ! -f "$MARKER_FILE" ]; do
    echo -n "."
    sleep 0.5
done

echo ""
echo "Command completed! Marker file exists."
echo ""
echo "=== Log file contents ==="
cat "$LOG_FILE"
echo ""
echo "=== Marker file contents (exit code) ==="
cat "$MARKER_FILE"
echo ""

# Cleanup
echo "Cleaning up test files..."
rm -f "$LOG_FILE" "$MARKER_FILE"
echo "Test complete!"
