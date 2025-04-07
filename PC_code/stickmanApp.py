import tkinter as tk
import serial
import threading
import time

SERIAL_PORT = 'COM5'
BAUD_RATE = 115200

MOVE_STEP = 20

class StickmanApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Stickman Bluetooth Controller")

        self.canvas = tk.Canvas(root, width=600, height=400, bg='white')
        self.canvas.pack()
        self.x = 300
        self.y = 200
        self.stickman = self.draw_stickman(self.x, self.y)

        self.bubble_box = self.canvas.create_rectangle(0, 0, 0, 0, fill="#e0f7ff", outline="#66b2ff", width=2, state='hidden')
        self.bubble_tail = self.canvas.create_polygon(0, 0, 0, 0, 0, 0, fill="#e0f7ff", outline="#66b2ff", width=2, state='hidden')
        self.bubble_text = self.canvas.create_text(self.x + 40, self.y - 60, text="", fill="black", font=("Arial", 12),
                                                   anchor="nw", state='hidden')

        # Serial thread
        self.running = True
        self.serial_thread = threading.Thread(target=self.read_serial)
        self.serial_thread.daemon = True
        self.serial_thread.start()

    def draw_stickman(self, x, y):
        parts = {}
        parts['head'] = self.canvas.create_oval(x - 10, y - 30, x + 10, y - 10, fill='black')
        parts['body'] = self.canvas.create_line(x, y - 10, x, y + 20, width=2)
        parts['left_arm'] = self.canvas.create_line(x, y, x - 15, y + 10, width=2)
        parts['right_arm'] = self.canvas.create_line(x, y, x + 15, y + 10, width=2)
        parts['left_leg'] = self.canvas.create_line(x, y + 20, x - 10, y + 40, width=2)
        parts['right_leg'] = self.canvas.create_line(x, y + 20, x + 10, y + 40, width=2)
        return parts

    def move_stickman(self, dx, dy):
        for part in self.stickman.values():
            self.canvas.move(part, dx, dy)
        self.canvas.move(self.bubble_text, dx, dy)
        self.canvas.move(self.bubble_box, dx, dy)
        self.canvas.move(self.bubble_tail, dx, dy)
        self.x += dx
        self.y += dy

    def show_bubble(self, msg):
        self.canvas.itemconfig(self.bubble_text, text=msg, state='normal')
        bbox = self.canvas.bbox(self.bubble_text)
        if not bbox:
            return

        padding = 6
        x1, y1, x2, y2 = bbox
        x1 -= padding
        y1 -= padding
        x2 += padding
        y2 += padding

        # Update bubble rectangle and tail
        self.canvas.coords(self.bubble_box, x1, y1, x2, y2)
        self.canvas.itemconfig(self.bubble_box, state='normal')

        tail_x = self.x + 10
        self.canvas.coords(self.bubble_tail,
                           tail_x, y1 + 10,
                           tail_x + 10, y1 + 20,
                           tail_x, y1 + 20)
        self.canvas.itemconfig(self.bubble_tail, state='normal')

    def hide_bubble(self):
        self.canvas.itemconfig(self.bubble_text, state='hidden')
        self.canvas.itemconfig(self.bubble_box, state='hidden')
        self.canvas.itemconfig(self.bubble_tail, state='hidden')

    def read_serial(self):
        try:
            ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
            print(f"Connected to {SERIAL_PORT}")
            buffer = ""
            while self.running:
                if ser.in_waiting > 0:
                    char = ser.read().decode(errors='ignore')
                    if char == '\n':
                        self.process_command(buffer.strip().lower())
                        buffer = ""
                    else:
                        buffer += char
                else:
                    time.sleep(0.01)
        except serial.SerialException as e:
            print(f"Serial error: {e}")

    def process_command(self, cmd):
        print(f"Received: {cmd}")
        if cmd == "left":
            self.move_stickman(-MOVE_STEP, 0)
            self.hide_bubble()
        elif cmd == "right":
            self.move_stickman(MOVE_STEP, 0)
            self.hide_bubble()
        elif cmd == "up":
            self.move_stickman(0, -MOVE_STEP)
            self.hide_bubble()
        elif cmd == "down":
            self.move_stickman(0, MOVE_STEP)
            self.hide_bubble()
        elif cmd == "go":
            self.show_bubble("Go!")
        elif cmd == "stop":
            self.show_bubble("Stop!")
        elif cmd == "yes":
            self.show_bubble("Yes")
        elif cmd == "no":
            self.show_bubble("No")

    def on_close(self):
        self.running = False
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    app = StickmanApp(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()
