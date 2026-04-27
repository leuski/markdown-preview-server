#! /bin/sh

ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$BB_DOC_PATH")

osascript <<EOF
tell application "Google Chrome"
  set targetURL to "http://127.0.0.1:8089/preview$ENC"
  set foundWin to missing value
  set foundIdx to 0
  repeat with w in windows
    set i to 0
    repeat with t in tabs of w
      set i to i + 1
      if URL of t starts with "http://127.0.0.1:8089/preview" then
        set foundWin to w
        set foundIdx to i
        exit repeat
      end if
    end repeat
    if foundWin is not missing value then exit repeat
  end repeat
  if foundWin is not missing value then
    set active tab index of foundWin to foundIdx
    set URL of active tab of foundWin to targetURL
    set index of foundWin to 1
  else
    open location targetURL
  end if
  activate
end tell
EOF
