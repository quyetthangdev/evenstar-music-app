"""Xoắn ốc Vogel (phyllotaxis) — dựng lại hoa văn chấm theo góc vàng.

Mỗi chấm thứ n đặt ở góc n*137.507° và bán kính tỉ lệ căn(n); đường kính chấm
lớn dần theo bán kính. Đó là công thức sinh ra đúng hình xoắn nhiều nhánh mà
mắt nhìn thấy — không nhánh nào được vẽ riêng, chúng nổi lên từ góc vàng.
"""
from PIL import Image, ImageDraw
import math

GOLDEN = math.radians(137.5077640500378)

def render(size, n_dots=150, hole=0.20, d_min=0.004, d_max=0.028,
           bg=(255, 255, 255), fg=(0, 0, 0), margin=0.10, ss=4):
    """`hole` = phần bán kính bỏ trống ở giữa. `ss` = hệ số khử răng cưa."""
    S = size * ss
    img = Image.new("RGB", (S, S), bg)
    dr = ImageDraw.Draw(img)
    cx = cy = S / 2
    r_max = (S / 2) * (1 - margin)
    for i in range(n_dots):
        t = (i + 0.5) / n_dots                 # 0..1 từ trong ra ngoài
        frac = hole + (1 - hole) * math.sqrt(t)  # căn → mật độ đều theo diện tích
        r = frac * r_max
        a = i * GOLDEN
        x = cx + r * math.cos(a)
        y = cy + r * math.sin(a)
        d = (d_min + (d_max - d_min) * frac) * S
        dr.ellipse([x - d/2, y - d/2, x + d/2, y + d/2], fill=fg)
    return img.resize((size, size), Image.LANCZOS)

if __name__ == "__main__":
    render(1024).save("faithful-1024.png")
    print("ok")
