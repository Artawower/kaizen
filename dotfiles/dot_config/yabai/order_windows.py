import subprocess
import json
import re

current_windows = subprocess.check_output(["yabai", "-m", "query", "--windows"])

parsed_json = json.loads(current_windows)

app_to_window = {
    "^Docker": "dev",
    "^wezterm": "trm",
    "^Ghostty": "trm",
    "^WezTerm": "trm",
    "^Spark": "soc",
    "^Emacs": "dev",
    "^Telegram": "soc",
    "^Mattermost": "soc",
    "^Brave": "web",
    "^Google": "dev",
    "^Session": "soc",
    "^Spotify": "med",
    "^OpenVPN": "net",
    "^Whalebird": "soc",
    "^Couch": "dev",
    "^Firefox": "web",
    "^Android": "12",
    "^Discord": "soc",
    "^Lightroom": "rec",
    "^Chromium": "dev",
    "^OrbStack": "12",
    "^Happ": "net",
    "^orgnote": "edu",
    "^Audacity": "rec",
    "^Helium": "web",
    "^Anki": "edu"
}

def order_windows():
   for window in parsed_json:
       for regexp in app_to_window:
           if not re.search(regexp, window["app"]):
               continue
           space = app_to_window[regexp]
           print(
               "Moving window {}:{}, app name: {}, to space {}".format(
                   window["id"], window["app"], window["title"], space
               )
           )
           subprocess.run(["yabai", "-m", "window", f'{window["id"]}', "--space", space])


if __name__ == "__main__":
    order_windows()
