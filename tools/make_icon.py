# 앱 아이콘(1024x1024, 투명 없음)을 표준 라이브러리만으로 그림: 파란 바탕 + 겹친 사진 카드 2장
import struct, sys, zlib
N = 1024
def lerp(a, b, t): return a + (b - a) * t
def rrect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1: return False
    cx = min(max(x, x0 + r), x1 - r); cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
rows = []
for y in range(N):
    row = bytearray([0])
    for x in range(N):
        t = (x + y) / (2 * N)
        c = (int(lerp(64, 20, t)), int(lerp(156, 92, t)), int(lerp(255, 214, t)))
        if rrect(x, y, 330, 250, 800, 640, 60): c = (190, 222, 255)          # 뒤 카드
        if rrect(x, y, 210, 370, 720, 790, 64):
            c = (255, 255, 255)                                             # 앞 카드
            if rrect(x, y, 246, 406, 684, 754, 36):
                c = (120, 196, 255)                                         # 하늘
                if (x - 590) ** 2 + (y - 500) ** 2 <= 46 ** 2: c = (255, 214, 84)   # 해
                if y - 754 >= -(260 - abs(x - 380) * 1.15) : c = (56, 168, 110)     # 산
                if y - 754 >= -(190 - abs(x - 560) * 1.05) : c = (40, 140, 96)
        row += bytes(c)
    rows.append(bytes(row))
raw = zlib.compress(b"".join(rows), 9)
def chunk(k, d): return struct.pack(">I", len(d)) + k + d + struct.pack(">I", zlib.crc32(k + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
