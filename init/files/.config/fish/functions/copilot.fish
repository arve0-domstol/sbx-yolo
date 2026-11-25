# Start alltid copilot i yolo-modus i sandkassen (som sbx run gjør).
function copilot --wraps copilot
    command copilot --yolo $argv
end
