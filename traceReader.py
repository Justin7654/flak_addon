import tkinter as tk
from tkinter import filedialog

def select_file():
    root = tk.Tk()
    root.withdraw()  # Hide the root window
    file_path = filedialog.askopenfilename()
    return file_path

def prompt_save_file():
    root = tk.Tk()
    root.withdraw()  # Hide the root window
    file_path = filedialog.asksaveasfilename(defaultextension=".json")
    return file_path


file = open(select_file(), "r")
print(f"Selected file: {file}")
lines = file.readlines()
file.close()

#Join the JSOn string together.
#Each section starts with: PROF_START|

import json

print("Joining...")

json_str = ""
for line in lines:
    if "PROF_START|" in line:
        json_str += line.split("PROF_START|")[1]

# Remove all newlines and tabs from the json string so it can parse correctly
print("Cleaning")
json_str = json_str.replace("\n", "").replace("\t", "")
# Escape control characters
json_str = json_str.encode('unicode_escape').decode('utf-8')

# Parse the JSON string
try:
    print("Verifying")
    json_str = json.dumps(json.loads(json_str))
    print("Parsed successfully. Verified")
except:
    print("Warning: Could not parse json successfully")

outputPath = prompt_save_file()
outputFile = open(outputPath, "w")
outputFile.write(json_str)
outputFile.close()
print("Written successfully")
input("Press ENTER to exit")