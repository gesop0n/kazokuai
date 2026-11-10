#!/usr/bin/env python3
import json
import math
import queue
import socket
import threading
import time
import tkinter as tk
import tkinter.font

SOCK = "/run/pisim/gui.sock"
KEYS = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]
JAPANESE_FONTS = ("Noto Sans CJK JP", "BIZ UDPGothic")
DIAL_KEYS = "0123456789*#"


def pick_font(root):
    families = set(tk.font.families(root))
    for f in JAPANESE_FONTS:
        if f in families:
            return f
    return "TkDefaultFont"


class Link:
    def __init__(self):
        self.inbox = queue.Queue()
        self.sock = None
        self.lock = threading.Lock()
        threading.Thread(target=self.loop, daemon=True).start()

    def loop(self):
        while True:
            try:
                self.receive_until_closed()
            except OSError:
                pass
            with self.lock:
                self.sock = None
            self.inbox.put({"t": "disconnected"})
            time.sleep(1)

    def receive_until_closed(self):
        s = socket.socket(socket.AF_UNIX)
        s.connect(SOCK)
        with self.lock:
            self.sock = s
        self.inbox.put({"t": "connected"})

        buf = b""
        while True:
            data = s.recv(65536)
            if not data:
                return
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    self.inbox.put(json.loads(line))
                except ValueError:
                    pass

    def send(self, **msg):
        with self.lock:
            if self.sock is None:
                return
            try:
                self.sock.sendall((json.dumps(msg) + "\n").encode())
            except OSError:
                pass


def round_rect(c, x1, y1, x2, y2, r, **kw):
    pts = [x1 + r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y2 - r, x2, y2,
           x2 - r, y2, x1 + r, y2, x1, y2, x1, y2 - r, x1, y1 + r, x1, y1]
    return c.create_polygon(pts, smooth=True, splinesteps=24, **kw)


class Phone:
    W, H = 640, 640
    OX, OY = 220, 110

    def __init__(self, root, link):
        self.root = root
        self.link = link
        self.font = pick_font(root)
        self.up = False
        self.ringing = False
        self.blink = False
        self.keys_down = ""
        self.pressed_mouse = None
        self.held = {}

        root.title("かぞくAI 電話機")
        root.resizable(False, False)
        self.c = tk.Canvas(root, width=self.W, height=self.H, bg="#ece3cf", highlightthickness=0)
        self.c.pack()

        root.bind("<KeyPress>", self.on_key_press)
        root.bind("<KeyRelease>", self.on_key_release)
        root.bind("<FocusOut>", lambda e: self.release_all())
        self.c.bind("<ButtonRelease-1>", self.on_mouse_up)

        self.draw()
        self.poll()
        self.tick()

    def draw(self):
        self.c.delete("all")
        self.draw_body()
        self.draw_cradle()
        self.draw_ringer()
        self.draw_keypad()
        self.draw_function_buttons()
        self.draw_handset()

    def draw_body(self):
        c, ox, oy = self.c, self.OX, self.OY
        round_rect(c, ox - 8, oy + 18, ox + 388, oy + 438, 34, fill="#b4b7ba", outline="")
        round_rect(c, ox, oy, ox + 380, oy + 420, 30, fill="#f6f6f6", outline="#d9dadb", width=2)
        c.create_polygon(ox + 40, oy + 8, ox + 340, oy + 8, ox + 300, oy + 60, ox + 80, oy + 60,
                         fill="#ffffff", outline="", smooth=True)

    def draw_cradle(self):
        c, ox, oy = self.c, self.OX, self.OY
        round_rect(c, ox + 16, oy + 16, ox + 146, oy + 120, 34, fill="#e3e4e5", outline="#d0d1d2")
        hook_y = oy + 34 if self.up else oy + 60
        c.create_rectangle(ox + 70, hook_y, ox + 92, hook_y + 62, fill="#a3a6a9", outline="#8b8e91")
        for i in range(12):
            for j in range(12):
                x, y = ox + 38 + i * 7.5, oy + 175 + j * 7.5
                c.create_oval(x, y, x + 3.4, y + 3.4, fill="#8c8f92", outline="")
        round_rect(c, ox + 16, oy + 300, ox + 146, oy + 404, 34, fill="#e3e4e5", outline="#d0d1d2")
        c.create_rectangle(ox + 16, oy + 16, ox + 146, oy + 404, outline="", fill="", tags=("cradle",))
        c.tag_bind("cradle", "<Button-1>", lambda e: self.set_hook(False) if self.up else None)

    def draw_ringer(self):
        c, ox, oy = self.c, self.OX, self.OY
        if self.ringing and self.blink:
            round_rect(c, ox + 280, oy + 22, ox + 364, oy + 50, 12, fill="#ffd27a", outline="")
        round_rect(c, ox + 286, oy + 28, ox + 358, oy + 44, 8, fill="#babcbe", outline="#7d8083")
        for i in range(17):
            x = ox + 292 + i * 4
            c.create_line(x, oy + 31, x, oy + 41, fill="#6d7073")

    def draw_keypad(self):
        c, ox, oy = self.c, self.OX, self.OY
        kx, ky, size, gap_x, gap_y = ox + 168, oy + 74, 60, 12, 10
        for r, row in enumerate(KEYS):
            for col, k in enumerate(row):
                x, y = kx + col * (size + gap_x), ky + r * (size + gap_y)
                down = k in self.keys_down
                d = 3 if down else 0
                tag = f"key{r}{col}"
                if not down:
                    c.create_oval(x + 1, y + 5, x + size + 1, y + size + 5, fill="#b6b9bc", outline="", tags=(tag,))
                c.create_oval(x, y + d, x + size, y + size + d, fill="#c5c9cc" if down else "#d5d8db",
                              outline="#a9adb0", width=2, tags=(tag,))
                c.create_oval(x + 7, y + 7 + d, x + size - 7, y + size - 7 + d, fill="#f3f4f4", outline="", tags=(tag,))
                c.create_arc(x + 9, y + 6 + d, x + size - 9, y + size - 14 + d, start=20, extent=140,
                             style="arc", outline="#ffffff", width=3, tags=(tag,))
                self.draw_key_label(k, x + size / 2, y + size / 2 + d + 1, tag)
                c.tag_bind(tag, "<ButtonPress-1>", lambda e, k=k: self.mouse_key(k))

    def draw_key_label(self, k, cx, cy, tag):
        if k != "*":
            self.c.create_text(cx, cy, text=k, font=("DejaVu Sans", 30, "bold"), fill="#111111", tags=(tag,))
            return
        for a in range(3):
            th = math.radians(90 + a * 60)
            dx, dy = 13 * math.cos(th), 13 * math.sin(th)
            self.c.create_line(cx - dx, cy - dy, cx + dx, cy + dy, width=6, fill="#111111",
                               capstyle="round", tags=(tag,))

    def draw_function_buttons(self):
        c, ox, oy = self.c, self.OX, self.OY
        for i, label in enumerate(("保留", "キャッチ", "リダイヤル", "ハンズフリー")):
            x = ox + 172 + i * 54
            c.create_oval(x, oy + 368, x + 30, oy + 384, fill="#cfd2d5", outline="#a9adb0")
            c.create_text(x + 15, oy + 400, text=label, font=(self.font, 8, "bold"), fill="#555555")

    def draw_handset(self):
        c, ox, oy = self.c, self.OX, self.OY
        if self.up:
            hx, hy = 40, 80
            self.cord(hx + 65, hy + 470, ox + 4, oy + 400)
            round_rect(c, hx, hy, hx + 130, hy + 480, 60, fill="#8f9295", outline="#e8e9e9", width=4, tags=("handset",))
            c.create_oval(hx + 16, hy + 20, hx + 114, hy + 118, fill="#9c9fa2", outline="#7b7e81", width=2, tags=("handset",))
            for i in range(3):
                for j in range(3):
                    x, y = hx + 55 + i * 9, hy + 59 + j * 9
                    c.create_oval(x, y, x + 3, y + 3, fill="#2b2d2f", outline="", tags=("handset",))
            c.create_oval(hx + 45, hy + 395, hx + 85, hy + 435, fill="#9c9fa2", outline="#7b7e81", width=2, tags=("handset",))
            c.create_oval(hx + 62, hy + 412, hx + 68, hy + 418, fill="#2b2d2f", outline="", tags=("handset",))
        else:
            hx, hy = ox + 10, oy - 34
            self.cord(hx + 70, hy + 480, ox + 20, self.H - 10)
            round_rect(c, hx, hy, hx + 142, hy + 492, 66, fill="#fbfbfb", outline="#d4d6d7", width=2, tags=("handset",))
            round_rect(c, hx + 28, hy + 20, hx + 70, hy + 200, 20, fill="#ffffff", outline="", tags=("handset",))
        c.tag_bind("handset", "<Button-1>", lambda e: self.set_hook(not self.up))

    def cord(self, x1, y1, x2, y2):
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy) or 1
        ux, uy = dx / length, dy / length
        vx, vy = -uy, ux
        turns = max(10, int(length / 10))
        steps = turns * 10
        pts = []
        for i in range(steps + 1):
            t = i / steps
            th = t * turns * 2 * math.pi
            taper = min(1, t * 8, (1 - t) * 8)
            sag = math.sin(math.pi * t) * (50 if self.up else 6)
            x = x1 + dx * t + taper * 8 * (math.cos(th) * ux * 0.6 + math.sin(th) * vx)
            y = y1 + dy * t + sag + taper * 8 * (math.cos(th) * uy * 0.6 + math.sin(th) * vy)
            pts += [x, y]
        self.c.create_line(*pts, fill="#c9cbcd", width=5, smooth=True)
        self.c.create_line(*pts, fill="#f5f5f5", width=2, smooth=True)

    def set_hook(self, up):
        self.up = up
        self.link.send(t="hook", up=up)
        self.draw()

    def press(self, k):
        self.link.send(t="key", k=k, down=True)
        self.keys_down = "".join(sorted(set(self.keys_down + k)))
        self.draw()

    def release(self, k):
        self.link.send(t="key", k=k, down=False)
        self.keys_down = self.keys_down.replace(k, "")
        self.draw()

    def mouse_key(self, k):
        self.pressed_mouse = k
        self.press(k)

    def on_mouse_up(self, e):
        if self.pressed_mouse:
            k, self.pressed_mouse = self.pressed_mouse, None
            self.release(k)

    def key_of(self, e):
        if e.keysym in ("asterisk", "KP_Multiply"):
            return "*"
        if e.keysym == "numbersign":
            return "#"
        if e.keysym.startswith("KP_") and e.keysym[3:].isdigit():
            return e.keysym[3:]
        return e.char if e.char and e.char in DIAL_KEYS else None

    def on_key_press(self, e):
        if e.keysym == "space":
            self.set_hook(not self.up)
            return
        k = self.key_of(e)
        if not k:
            return
        if k in self.held:
            if self.held[k]:
                self.root.after_cancel(self.held[k])
                self.held[k] = None
            return
        self.held[k] = None
        self.press(k)

    def on_key_release(self, e):
        k = self.key_of(e)
        if k and k in self.held:
            self.held[k] = self.root.after(40, lambda: self.key_up(k))

    def key_up(self, k):
        self.held.pop(k, None)
        self.release(k)

    def release_all(self):
        for k in list(self.held):
            self.key_up(k)
        if self.pressed_mouse:
            self.on_mouse_up(None)

    def poll(self):
        try:
            while True:
                m = self.link.inbox.get_nowait()
                if m["t"] == "state":
                    self.apply(m)
        except queue.Empty:
            pass
        self.root.after(30, self.poll)

    def apply(self, s):
        redraw = False
        if s["hook_up"] != self.up:
            self.up = s["hook_up"]
            redraw = True
        keys = s.get("keys", "")
        if keys != self.keys_down and not self.held and not self.pressed_mouse:
            self.keys_down = keys
            redraw = True
        ringing = bool((s.get("ringer") or {}).get("active"))
        if ringing != self.ringing:
            self.ringing = ringing
            redraw = True
        if redraw:
            self.draw()

    def tick(self):
        if self.ringing:
            self.blink = not self.blink
            self.draw()
        self.root.after(180, self.tick)


def main():
    root = tk.Tk()
    Phone(root, Link())
    root.mainloop()


if __name__ == "__main__":
    main()
