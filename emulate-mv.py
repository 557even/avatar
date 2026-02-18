#   pip install pyautogui==0.9.53
#   pip install pillow      # for image recognition (optional)
#   pip install keyboard    # for low‑level key events (optional)

import time
import pyautogui as pag

# ------------------------------------------------------------------
# Configuration – screen geometry (adjust to your monitor/resolution)
# ------------------------------------------------------------------
SCREEN_W, SCREEN_H = pag.size()
MARGIN = 10  # safety margin from edges

# ------------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------------
def move_and_click(x, y, clicks=1, interval=0.25):
    """Move cursor to (x, y) and click."""
    pag.moveTo(x, y, duration=0.2)
    pag.click(clicks=clicks, interval=interval)

def type_text(text, interval=0.05):
    """Type a string with realistic key intervals."""
    pag.write(text, interval=interval)

def press_hotkey(*keys):
    """Press a combination of keys (e.g., ctrl, shift, n)."""
    pag.hotkey(*keys)

def wait(seconds):
    """Pause execution."""
    time.sleep(seconds)

# ------------------------------------------------------------------
# 1️⃣  Open Outlook (or default email client) and process inbox
# ------------------------------------------------------------------
def process_email():
    # Assume Outlook shortcut on taskbar at position (100, SCREEN_H-10)
    move_and_click(100, SCREEN_H - 5)   # click taskbar icon
    wait(2)

    # Focus on first unread email (example coordinates)
    move_and_click(300, 200)            # click email list entry
    wait(1)

    # Reply to email
    press_hotkey('ctrl', 'r')          # open reply window
    wait(1)
    type_text("Thanks for the update. I’ll review and get back to you shortly.")
    press_hotkey('ctrl', 'enter')      # send reply
    wait(1)

# ------------------------------------------------------------------
# 2️⃣  Schedule a meeting in the calendar (Outlook or Google Calendar)
# ------------------------------------------------------------------
def schedule_meeting():
    # Open calendar tab (Ctrl+2 in Outlook)
    press_hotkey('ctrl', '2')
    wait(1)

    # Click on desired time slot (example coordinates)
    move_and_click(600, 400)            # new meeting slot
    wait(0.5)
    press_hotkey('ctrl', 'n')           # new meeting dialog
    wait(1)

    # Fill meeting details
    type_text("Project Sync – Weekly")
    press_hotkey('tab')
    type_text("Discuss progress, blockers, next steps.")
    press_hotkey('tab')
    type_text("10:00 AM – 10:30 AM")
    press_hotkey('tab')
    type_text("Conference Room A")
    wait(0.5)

    # Invite participants (example three emails)
    press_hotkey('tab')
    type_text("alice@example.com; bob@example.com; carol@example.com")
    press_hotkey('enter')               # add attendees
    wait(0.5)

    # Save & close
    press_hotkey('ctrl', 's')
    wait(0.5)

# ------------------------------------------------------------------
# 3️⃣  Open a shared document and add a status update
# ------------------------------------------------------------------
def update_document():
    # Open file explorer shortcut (Win+E) and navigate
    press_hotkey('win', 'e')
    wait(1)
    type_text(r"C:\Projects\Current\StatusReport.docx")
    press_hotkey('enter')
    wait(3)  # wait for Word to load

    # Scroll to end of document
    press_hotkey('ctrl', 'end')
    wait(0.5)

    # Insert a new bullet line with status
    press_hotkey('enter')
    type_text("- Completed data ingestion; pending model validation.")
    wait(0.5)

    # Save document
    press_hotkey('ctrl', 's')
    wait(0.5)

    # Close Word
    press_hotkey('alt', 'f4')
    wait(0.5)

# ------------------------------------------------------------------
# 4️⃣  Wrap up – Log out or lock workstation
# ------------------------------------------------------------------
def lock_workstation():
    press_hotkey('win', 'l')  # lock screen

# ------------------------------------------------------------------
# Main routine – Execute steps sequentially
# ------------------------------------------------------------------
def main():
    process_email()
    schedule_meeting()
    update_document()
    lock_workstation()
    
nks for the update. Ill review and get back to you shortly.
if __name__ == "__main__":
    main()
