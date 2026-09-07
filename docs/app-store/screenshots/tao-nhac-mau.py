"""Bộ nhạc mẫu để chụp ảnh App Store.

Mọi ảnh bìa ở đây do chính script này sinh ra bằng cùng công thức xoắn ốc
Vogel của biểu tượng app — nên chúng là tài sản của bạn, không dính bản quyền
của ai. Đó là điểm mấu chốt: Apple từ chối vì ảnh chụp có bìa album của bên
thứ ba.

Âm thanh là im lặng. Ảnh chụp màn hình không phát ra tiếng.
"""
import subprocess, math
from phyllotaxis import render

# (tựa, nghệ sĩ, album, giây, nền, chấm)
TRACKS = [
    ("Bến Chiều",        "Hạ Vàng",     "Bến Chiều",      222, (18, 24, 48),  (232, 238, 255)),
    ("Gió Qua Hiên",     "Hạ Vàng",     "Bến Chiều",      196, (18, 24, 48),  (232, 238, 255)),
    ("Sao Hôm",          "Lam Nguyệt",  "Trời Tháng Chín",258, (44, 20, 52),  (255, 236, 244)),
    ("Đường Về Muộn",    "Lam Nguyệt",  "Trời Tháng Chín",241, (44, 20, 52),  (255, 236, 244)),
    ("Northbound",       "Cedar Field", "Long Way Home",  205, (20, 44, 38),  (226, 255, 240)),
    ("Paper Boats",      "Cedar Field", "Long Way Home",  178, (20, 44, 38),  (226, 255, 240)),
    ("Tầng Mây",         "Vũ Minh",     "Tầng Mây",       263, (52, 34, 16),  (255, 244, 226)),
    ("Chiều Không Tên",  "Vũ Minh",     "Tầng Mây",       214, (52, 34, 16),  (255, 244, 226)),
]

for i, (title, artist, album, secs, bg, fg) in enumerate(TRACKS, 1):
    # Mỗi album một hình riêng: đổi số chấm để hai bài cùng album vẫn cùng
    # bộ màu mà hình không trùng khít nhau.
    cover = f"cover-{i:02d}.png"
    render(1024, n_dots=40 + (i % 4) * 14, hole=0.14,
           d_min=0.028, d_max=0.075, bg=bg, fg=fg, margin=0.10).save(cover)

    out = f"{i:02d} {title}.mp3"
    subprocess.run([
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "lavfi", "-t", str(secs), "-i", "anullsrc=r=44100:cl=stereo",
        "-i", cover,
        "-map", "0:a", "-map", "1:v",
        "-c:a", "libmp3lame", "-b:a", "128k",
        "-c:v", "copy", "-id3v2_version", "3",
        "-metadata:s:v", "title=Album cover",
        "-metadata:s:v", "comment=Cover (front)",
        "-metadata", f"title={title}",
        "-metadata", f"artist={artist}",
        "-metadata", f"album={album}",
        "-metadata", f"track={i}",
        out,
    ], check=True)
    print(f"  {out}  —  {artist} · {album} · {secs//60}:{secs%60:02d}")
print("xong")
