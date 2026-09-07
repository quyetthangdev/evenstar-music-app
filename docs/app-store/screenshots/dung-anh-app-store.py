"""Dựng ảnh App Store: nền xanh, tiêu đề trắng, khung máy chứa ảnh chụp thật.

Hoạ tiết trang trí dùng đúng hoa văn xoắn ốc của biểu tượng app thay vì mấy
hình vẽ nguệch ngoạc chung chung — cùng ngôn ngữ hình ảnh thì trang sản phẩm
đọc như một thể thống nhất.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, sys

W, H = 1290, 2796                      # 6.9 inch, cỡ Apple đang yêu cầu
BLUE      = (10, 122, 255)
PALE      = (232, 241, 255)
DOT       = (168, 205, 255)
FONT      = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
GOLDEN    = math.radians(137.5077640500378)

def fit(draw, text, size_start, max_w):
    """Chọn cỡ chữ lớn nhất mà dòng vẫn lọt trong bề ngang cho phép."""
    s = size_start
    while s > 20:
        f = ImageFont.truetype(FONT, s)
        if draw.textlength(text, font=f) <= max_w:
            return f
        s -= 2
    return ImageFont.truetype(FONT, s)

def sprinkle(img, n, cx, cy, r_max, colour, d_min, d_max, seed_offset=0):
    dr = ImageDraw.Draw(img, "RGBA")
    for i in range(n):
        t = (i + 0.5 + seed_offset) / n
        r = math.sqrt(t) * r_max
        a = (i + seed_offset) * GOLDEN
        x, y = cx + r * math.cos(a), cy + r * math.sin(a)
        d = d_min + (d_max - d_min) * math.sqrt(t)
        dr.ellipse([x-d/2, y-d/2, x+d/2, y+d/2], fill=colour)

def phone(shot_path, target_w):
    """Khung máy tối, bo góc, ôm lấy ảnh chụp thật."""
    shot = Image.open(shot_path).convert("RGB")
    sw = target_w
    sh = round(sw * shot.height / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)

    bez = round(sw * 0.028)
    fw, fh = sw + bez*2, sh + bez*2
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    dr = ImageDraw.Draw(frame)
    radius = round(fw * 0.115)
    dr.rounded_rectangle([0, 0, fw-1, fh-1], radius=radius, fill=(22, 22, 24, 255))

    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw-1, sh-1],
                                           radius=round(sw*0.095), fill=255)
    frame.paste(shot, (bez, bez), mask)
    return frame

def make(shot_path, line1, line2, out_path):
    img = Image.new("RGB", (W, H), BLUE)

    # Vòng cung lớn: một hình tròn khổng lồ tâm nằm trên khung, phần dưới của
    # nó tạo ra đường cong ngăn vùng xanh với vùng sáng.
    img = Image.new("RGB", (W, H), BLUE)
    cut = int(H * 0.30)
    img.paste(Image.new("RGB", (W, H - cut), PALE), (0, cut))
    # Vòng cung: một hình tròn khổng lồ màu xanh, tâm nằm phía trên khung, ăn
    # xuống vùng sáng và tạo ra đường cong ngăn hai vùng.
    R = W * 1.35
    ImageDraw.Draw(img).ellipse(
        [W/2 - R, cut - 2*R + W*0.62, W/2 + R, cut + W*0.62], fill=BLUE)

    # Chấm trang trí chỉ ở hai dải mép, tránh cột giữa nơi máy sẽ đứng.
    sprinkle(img, 70, W*0.06, H*0.66, W*0.22, DOT, 7, 30)
    sprinkle(img, 70, W*0.96, H*0.63, W*0.22, DOT, 7, 30, seed_offset=13)

    dr = ImageDraw.Draw(img)
    max_w = W * 0.86
    f1 = fit(dr, line1, 118, max_w)
    f2 = fit(dr, line2, 118, max_w)
    f = f1 if f1.size <= f2.size else f2          # hai dòng cùng cỡ
    y = H * 0.085
    for line in (line1, line2):
        w = dr.textlength(line, font=f)
        dr.text(((W - w) / 2, y), line, font=f, fill=(255, 255, 255))
        y += f.size * 1.22

    # Máy to và **tràn khỏi mép dưới**: cắt cụt ở đáy làm khung ảnh có chiều
    # sâu, và cho ảnh chụp chiếm nhiều diện tích hơn.
    ph = phone(shot_path, round(W * 0.70))
    px = (W - ph.width) // 2
    py = round(H * 0.275)

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([px+10, py+26, px+ph.width+10, py+ph.height+26],
                         radius=round(ph.width*0.115), fill=(6, 40, 92, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    img = Image.alpha_composite(img.convert("RGBA"), shadow)
    img.paste(ph, (px, py), ph)          # paste chứ không alpha_composite: cắt được phần tràn
    img.convert("RGB").save(out_path, quality=95)
    print("→", out_path, f"chữ {f.size}px")

if __name__ == "__main__":
    D = "/Volumes/Storage/claude-scratch/shots"
    make(f"{D}/C-list.png",  "NHẠC CỦA BẠN",        "GỌN GÀNG MỘT CHỖ", "01-thu-vien.png")
    make(f"{D}/A-player.png","NGHE TRỌN VẸN",       "KHÔNG QUẢNG CÁO",  "02-player.png")
    make(f"{D}/B-queue.png", "HÀNG ĐỢI TRONG TAY",  "SẮP LẠI TÙY Ý",    "03-hang-doi.png")
