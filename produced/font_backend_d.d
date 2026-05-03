/* font_backend_d.d - Font rendering using native Windows API. */
module font_backend_d;

import core.stdc.stdlib : malloc, free;
import core.stdc.string : memset, memcpy;

version (Windows) {
    import core.sys.windows.windows;
    import core.sys.windows.wingdi;
    enum CLEARTYPE_QUALITY = 5;
}

struct GlyphBitmap {
    int width, height, xoff, yoff;
    ubyte* pixels;
}

struct NativeFont {
    version (Windows) {
        HFONT hfont;
        HDC hdc;
        float pixelHeight;
    }
}

NativeFont* fontLoad(const(char)* name, float pixelHeight) {
    version (Windows) {
        auto f = cast(NativeFont*) malloc(NativeFont.sizeof);
        if (!f) return null;
        memset(f, 0, NativeFont.sizeof);
        f.pixelHeight = pixelHeight;
        f.hfont = CreateFontA(
            cast(int)pixelHeight, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, name);
        if (!f.hfont) { free(f); return null; }
        f.hdc = CreateCompatibleDC(null);
        SelectObject(f.hdc, f.hfont);
        SetBkMode(f.hdc, TRANSPARENT);
        return f;
    } else {
        return null;
    }
}

void fontFree(NativeFont* f) {
    version (Windows) {
        if (!f) return;
        if (f.hdc) DeleteDC(f.hdc);
        if (f.hfont) DeleteObject(f.hfont);
        free(f);
    }
}

float fontHeight(NativeFont* f) {
    version (Windows) { return f.pixelHeight; }
    else { return 16; }
}

float fontLineAdvance(NativeFont* f) {
    version (Windows) {
        TEXTMETRICA tm;
        GetTextMetricsA(f.hdc, &tm);
        return cast(float)tm.tmHeight;
    } else { return 16; }
}

int fontAscent(NativeFont* f) {
    version (Windows) {
        TEXTMETRICA tm;
        GetTextMetricsA(f.hdc, &tm);
        return tm.tmAscent;
    } else { return 12; }
}

float fontCharAdvance(NativeFont* f, int codepoint) {
    version (Windows) {
        SIZE sz;
        wchar wch = cast(wchar)codepoint;
        GetTextExtentPoint32W(f.hdc, &wch, 1, &sz);
        return cast(float)sz.cx;
    } else { return 8; }
}

float fontTextAdvance(NativeFont* f, const(wchar)* text, int len) {
    version (Windows) {
        SIZE sz;
        GetTextExtentPoint32W(f.hdc, text, len, &sz);
        return cast(float)sz.cx;
    } else { return len * 8; }
}

GlyphBitmap fontGlyphBitmap(NativeFont* f, int codepoint) {
    GlyphBitmap gb;
    memset(&gb, 0, GlyphBitmap.sizeof);
    version (Windows) {
        wchar wch = cast(wchar)codepoint;
        MAT2 mat = {{0,1},{0,0},{0,0},{0,1}};
        GLYPHMETRICS gm;

        DWORD sz = GetGlyphOutlineW(f.hdc, wch, GGO_GRAY8_BITMAP, &gm, 0, null, &mat);
        if (sz == GDI_ERROR || sz == 0) return gb;

        auto buf = cast(ubyte*)malloc(sz);
        if (!buf) return gb;
        GetGlyphOutlineW(f.hdc, wch, GGO_GRAY8_BITMAP, &gm, sz, buf, &mat);

        gb.width = cast(int)gm.gmBlackBoxX;
        gb.height = cast(int)gm.gmBlackBoxY;
        gb.xoff = cast(int)gm.gmptGlyphOrigin.x;
        gb.yoff = cast(int)(gm.gmptGlyphOrigin.y - gm.gmBlackBoxY);

        int rowBytes = (gb.width + 3) & ~3;
        gb.pixels = cast(ubyte*)malloc(gb.width * gb.height);
        if (gb.pixels) {
            for (int y = 0; y < gb.height; y++) {
                for (int x = 0; x < gb.width; x++) {
                    ubyte v = buf[y * rowBytes + x];
                    gb.pixels[y * gb.width + x] = cast(ubyte)(v * 255 / 64);
                }
            }
        }
        free(buf);
    }
    return gb;
}

void fontGlyphBitmapFree(GlyphBitmap* gb) {
    if (gb && gb.pixels) { free(gb.pixels); gb.pixels = null; }
}
