/* crossui.d - Cross-platform UI library with OpenGL 1.1 fixed-function rendering.
   No shaders, no extensions, no VBOs — works on any GL implementation.
   Compile: dmd crossui.d font_backend_d.d -L/subsystem:windows -L/entry:mainCRTStartup -L/DEFAULTLIB:user32 -L/DEFAULTLIB:gdi32 -L/DEFAULTLIB:opengl32 -L/DEFAULTLIB:comdlg32 -L/DEFAULTLIB:comctl32
*/
module crossui;

import core.stdc.string : memset, memcpy, strlen, memmove;
import core.stdc.stdlib : malloc, free, realloc, calloc;
import core.stdc.stdio  : snprintf;

void intToDigits(int v, char* buf, int bufLen) nothrow {
    if (v <= 0) { buf[0] = '0'; buf[1] = 0; return; }
    char[16] tmp;
    int n = 0;
    while (v > 0 && n < 15) { tmp[n++] = cast(char)('0' + v % 10); v /= 10; }
    int i = 0;
    for (int j = n - 1; j >= 0 && i < bufLen - 1; j--) buf[i++] = tmp[j];
    buf[i] = 0;
}
import core.stdc.math   : fabs, floor, ceil, round;

version (Windows) {
    import core.sys.windows.windows;
    import core.sys.windows.wingdi;
    import core.sys.windows.winuser;
}

/* ================================================================== */
/*  GL 1.1 BINDINGS (all in opengl32.lib, no runtime loading needed)  */
/* ================================================================== */
alias GLenum  = uint;
alias GLuint  = uint;
alias GLint   = int;
alias GLsizei = int;
alias GLfloat = float;
alias GLbitfield = uint;
alias GLubyte = ubyte;
alias GLboolean = ubyte;
alias GLdouble = double;

extern(System) nothrow @nogc {
    void glEnable(GLenum);
    void glDisable(GLenum);
    void glBlendFunc(GLenum, GLenum);
    void glViewport(GLint, GLint, GLsizei, GLsizei);
    void glClearColor(GLfloat, GLfloat, GLfloat, GLfloat);
    void glClear(GLbitfield);
    void glScissor(GLint, GLint, GLsizei, GLsizei);
    void glGenTextures(GLsizei, GLuint*);
    void glDeleteTextures(GLsizei, const(GLuint)*);
    void glBindTexture(GLenum, GLuint);
    void glTexParameteri(GLenum, GLenum, GLint);
    void glTexImage2D(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const(void)*);
    void glTexSubImage2D(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const(void)*);
    void glPixelStorei(GLenum, GLint);
    void glBegin(GLenum);
    void glEnd();
    void glVertex2f(GLfloat, GLfloat);
    void glVertex2i(GLint, GLint);
    void glTexCoord2f(GLfloat, GLfloat);
    void glColor4f(GLfloat, GLfloat, GLfloat, GLfloat);
    void glColor3f(GLfloat, GLfloat, GLfloat);
    void glMatrixMode(GLenum);
    void glLoadIdentity();
    void glOrtho(GLdouble, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble);
    void glPushMatrix();
    void glPopMatrix();
    void glFinish();
    void glFlush();
    const(GLubyte*) glGetString(GLenum);
}

enum : GLenum {
    GL_FALSE = 0, GL_TRUE = 1,
    GL_TRIANGLES = 0x0004,
    GL_QUADS = 0x0007,
    GL_SRC_ALPHA = 0x0302,
    GL_ONE_MINUS_SRC_ALPHA = 0x0303,
    GL_BLEND = 0x0BE2,
    GL_TEXTURE_2D = 0x0DE1,
    GL_RGBA = 0x1908,
    GL_ALPHA = 0x1906,
    GL_UNSIGNED_BYTE = 0x1401,
    GL_LINEAR = 0x2601,
    GL_NEAREST = 0x2600,
    GL_TEXTURE_MIN_FILTER = 0x2800,
    GL_TEXTURE_MAG_FILTER = 0x2801,
    GL_TEXTURE_WRAP_S = 0x2802,
    GL_TEXTURE_WRAP_T = 0x2803,
    GL_CLAMP_TO_EDGE = 0x812F,
    GL_COLOR_BUFFER_BIT = 0x00004000,
    GL_SCISSOR_TEST = 0x0C11,
    GL_PROJECTION = 0x1701,
    GL_MODELVIEW = 0x1700,
    GL_TEXTURE_ENV = 0x2300,
    GL_TEXTURE_ENV_MODE = 0x2200,
    GL_MODULATE = 0x2100,
    GL_REPLACE = 0x1E01,
    GL_UNPACK_ALIGNMENT = 0x0CF5,
    GL_VERSION = 0x1F02,
    GL_RENDERER = 0x1F01,
}

/* ================================================================== */
/*  PLATFORM LAYER                                                    */
/* ================================================================== */
struct PlatformWindow {
    int width, height;
    bool shouldClose;
    bool[256] keyDown;
    bool[5] mouseDown;
    int mouseX, mouseY;
    int scrollDelta;
    version (Windows) {
        HWND hwnd;
        HDC hdc;
        HGLRC hglrc;
    }
}

__gshared PlatformWindow g_win;

version (Windows) {

bool platformInit(int w, int h, const(char)* title) {
    auto hInst = GetModuleHandleW(null);
    WNDCLASSEXW wc;
    wc.cbSize = WNDCLASSEXW.sizeof;
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc = &winProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursorW(null, IDC_ARROW);
    wc.lpszClassName = "CrossUIWnd"w.ptr;
    if (!RegisterClassExW(&wc)) return false;

    RECT rc = RECT(0, 0, w, h);
    AdjustWindowRectEx(&rc, WS_OVERLAPPEDWINDOW, FALSE, 0);

    wchar[512] wt;
    int ni = 0;
    auto p = title;
    while (*p && ni < 511) { wt[ni++] = cast(wchar)*p; p++; }
    wt[ni] = 0;

    g_win.hwnd = CreateWindowExW(0, "CrossUIWnd"w.ptr, wt.ptr,
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, rc.right - rc.left, rc.bottom - rc.top,
        null, null, hInst, null);
    if (!g_win.hwnd) return false;
    g_win.hdc = GetDC(g_win.hwnd);

    PIXELFORMATDESCRIPTOR pfd;
    pfd.nSize = pfd.sizeof;
    pfd.nVersion = 1;
    pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    pfd.iPixelType = PFD_TYPE_RGBA;
    pfd.cColorBits = 32;
    pfd.cDepthBits = 16;
    pfd.iLayerType = PFD_MAIN_PLANE;
    int pf = ChoosePixelFormat(g_win.hdc, &pfd);
    SetPixelFormat(g_win.hdc, pf, &pfd);

    g_win.hglrc = wglCreateContext(g_win.hdc);
    if (!g_win.hglrc) return false;
    wglMakeCurrent(g_win.hdc, g_win.hglrc);

    g_win.width = w;
    g_win.height = h;
    g_win.shouldClose = false;
    return true;
}

void platformPollEvents() {
    MSG msg;
    g_win.scrollDelta = 0;
    while (PeekMessageW(&msg, null, 0, 0, PM_REMOVE)) {
        if (msg.message == 0x0012) { g_win.shouldClose = true; return; } /* WM_QUIT */
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

void platformSwapBuffers() { SwapBuffers(g_win.hdc); }

float platformGetTime() { return cast(float)GetTickCount() / 1000.0f; }

extern(Windows) LRESULT winProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) nothrow {
    switch (msg) {
    case WM_CLOSE: g_win.shouldClose = true; return 0;
    case WM_DESTROY: PostQuitMessage(0); return 0;
    case WM_SIZE: g_win.width = LOWORD(lp); g_win.height = HIWORD(lp); return 0;
    case WM_KEYDOWN: g_win.keyDown[cast(uint)wp & 0xFF] = true; return 0;
    case WM_KEYUP:   g_win.keyDown[cast(uint)wp & 0xFF] = false; return 0;
    case WM_LBUTTONDOWN: g_win.mouseDown[0] = true; SetCapture(hwnd); return 0;
    case WM_LBUTTONUP:   g_win.mouseDown[0] = false; ReleaseCapture(); return 0;
    case WM_RBUTTONDOWN: g_win.mouseDown[1] = true; return 0;
    case WM_RBUTTONUP:   g_win.mouseDown[1] = false; return 0;
    case WM_MOUSEMOVE: g_win.mouseX = cast(short)LOWORD(lp); g_win.mouseY = cast(short)HIWORD(lp); return 0;
    case WM_MOUSEWHEEL: g_win.scrollDelta += cast(int)(cast(short)HIWORD(wp)) / 120; return 0;
    default: break;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

bool clipboardSetText(const(char)* text) {
    if (!OpenClipboard(null)) return false;
    EmptyClipboard();
    auto len = strlen(text) + 1;
    auto h = GlobalAlloc(GMEM_MOVEABLE, len);
    if (!h) { CloseClipboard(); return false; }
    auto dst = cast(char*)GlobalLock(h);
    memcpy(dst, text, len);
    GlobalUnlock(h);
    SetClipboardData(CF_TEXT, h);
    CloseClipboard();
    return true;
}

char* clipboardGetText() {
    if (!IsClipboardFormatAvailable(CF_TEXT)) return null;
    if (!OpenClipboard(null)) return null;
    auto h = GetClipboardData(CF_TEXT);
    if (!h) { CloseClipboard(); return null; }
    auto src = cast(const(char)*)GlobalLock(h);
    if (!src) { CloseClipboard(); return null; }
    auto len = strlen(src) + 1;
    auto buf = cast(char*)malloc(len);
    memcpy(buf, src, len);
    GlobalUnlock(h);
    CloseClipboard();
    return buf;
}

} else {
bool platformInit(int w, int h, const(char)* t) { return false; }
void platformPollEvents() {}
void platformSwapBuffers() {}
float platformGetTime() { return 0; }
bool clipboardSetText(const(char)* t) { return false; }
char* clipboardGetText() { return null; }
}

/* ================================================================== */
/*  FONT BACKEND (imported from font_backend_d.d)                     */
/* ================================================================== */
public import font_backend_d;

/* ================================================================== */
/*  COLOR                                                             */
/* ================================================================== */
struct Color {
    float r, g, b, a;
    static Color opCall(float r, float g, float b, float a = 1.0f) {
        Color c; c.r=r; c.g=g; c.b=b; c.a=a; return c;
    }
}

enum Color COL_WHITE = Color(1,1,1), COL_BLACK = Color(0,0,0);
enum Color COL_GRAY = Color(0.75f,0.75f,0.75f), COL_DARKGRAY = Color(0.25f,0.25f,0.25f);
enum Color COL_LIGHTGRAY = Color(0.9f,0.9f,0.9f), COL_BLUE = Color(0.2f,0.4f,0.8f);
enum Color COL_DARKBLUE = Color(0.1f,0.1f,0.3f), COL_RED = Color(0.9f,0.2f,0.2f);
enum Color COL_CYAN = Color(0.2f,0.8f,0.9f);

/* ================================================================== */
/*  GLYPH CACHE / ATLAS                                               */
/* ================================================================== */
struct GlyphKey { uint fontId; uint codepoint; }

struct CachedGlyph {
    int px, py, w, h, xoff, yoff;
    float advance;
    float u0, v0, u1, v1;
}

enum ATLAS_W = 1024, ATLAS_H = 1024;

struct GlyphAtlas {
    GLuint texture;
    ubyte[ATLAS_W * ATLAS_H] pixels;
    int curX, curY, rowH;
    CachedGlyph[GlyphKey] cache;
    uint nextFontId;
    NativeFont*[uint] fonts;
}

__gshared GlyphAtlas g_atlas;

uint atlasAddFont(const(char)* name, float size) {
    auto f = fontLoad(name, size);
    if (!f) return 0;
    uint id = g_atlas.nextFontId++;
    g_atlas.fonts[id] = f;
    return id;
}

void atlasInit() {
    memset(&g_atlas, 0, g_atlas.sizeof);
    g_atlas.nextFontId = 1;
    glGenTextures(1, &g_atlas.texture);
    glBindTexture(GL_TEXTURE_2D, g_atlas.texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    auto zeros = cast(ubyte*)calloc(ATLAS_W * ATLAS_H, 1);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, ATLAS_W, ATLAS_H, 0, GL_ALPHA, GL_UNSIGNED_BYTE, zeros);
    free(zeros);
}

void atlasUploadRegion(int x, int y, int w, int h) {
    ubyte[] tmp;
    tmp.length = w * h;
    for (int row = 0; row < h; row++)
        memcpy(tmp.ptr + row * w, g_atlas.pixels.ptr + (y + row) * ATLAS_W + x, w);
    glBindTexture(GL_TEXTURE_2D, g_atlas.texture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, x, y, w, h, GL_ALPHA, GL_UNSIGNED_BYTE, tmp.ptr);
    tmp.length = 0;
}

const(CachedGlyph)* atlasGetGlyph(uint fontId, int codepoint) {
    auto key = GlyphKey(fontId, cast(uint)codepoint);
    if (auto p = key in g_atlas.cache) return p;
    auto f = g_atlas.fonts.get(fontId, null);
    if (!f) return null;
    auto gb = fontGlyphBitmap(f, codepoint);
    int gbw = gb.width, gbh = gb.height;
    if (g_atlas.curX + gbw + 1 > ATLAS_W) { g_atlas.curX = 0; g_atlas.curY += g_atlas.rowH + 1; g_atlas.rowH = 0; }
    if (g_atlas.curY + gbh + 1 > ATLAS_H) { fontGlyphBitmapFree(&gb); return null; }
    CachedGlyph cg;
    cg.px = g_atlas.curX; cg.py = g_atlas.curY;
    cg.w = gbw; cg.h = gbh;
    cg.xoff = gb.xoff; cg.yoff = gb.yoff;
    cg.advance = fontCharAdvance(f, codepoint);
    cg.u0 = cast(float)cg.px / ATLAS_W; cg.v0 = cast(float)cg.py / ATLAS_H;
    cg.u1 = cast(float)(cg.px + cg.w) / ATLAS_W; cg.v1 = cast(float)(cg.py + cg.h) / ATLAS_H;
    if (gb.pixels && gbw > 0 && gbh > 0) {
        for (int row = 0; row < gbh; row++)
            memcpy(g_atlas.pixels.ptr + (cg.py + row) * ATLAS_W + cg.px, gb.pixels + row * gbw, gbw);
        atlasUploadRegion(cg.px, cg.py, cg.w, cg.h);
    }
    fontGlyphBitmapFree(&gb);
    g_atlas.curX += gbw + 1;
    if (gbh > g_atlas.rowH) g_atlas.rowH = gbh;
    g_atlas.cache[key] = cg;
    return key in g_atlas.cache;
}

float atlasTextAdvance(uint fontId, const(wchar)* text, int len) {
    float x = 0;
    for (int i = 0; i < len; i++) { auto g = atlasGetGlyph(fontId, text[i]); if (g) x += g.advance; }
    return x;
}

int atlasCharIndexFromX(uint fontId, const(wchar)* text, int len, float targetX) {
    float x = 0;
    for (int i = 0; i < len; i++) {
        auto g = atlasGetGlyph(fontId, text[i]);
        float adv = g ? g.advance : 8;
        if (x + adv * 0.5f > targetX) return i;
        x += adv;
    }
    return len;
}

float atlasLineHeight(uint fontId) {
    auto f = g_atlas.fonts.get(fontId, null);
    return f ? fontLineAdvance(f) : 16;
}

float atlasAscent(uint fontId) {
    auto f = g_atlas.fonts.get(fontId, null);
    return f ? cast(float)fontAscent(f) : 12;
}

/* ================================================================== */
/*  2D RENDERER (GL 1.1 immediate mode)                               */
/* ================================================================== */
struct Renderer {
    float screenW, screenH;
}

__gshared Renderer g_ren;

void renInit() {
    memset(&g_ren, 0, g_ren.sizeof);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
}

void renBegin(float w, float h) {
    g_ren.screenW = w;
    g_ren.screenH = h;
    glViewport(0, 0, cast(int)w, cast(int)h);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, w, h, 0, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glClearColor(0.15f, 0.15f, 0.18f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
}

void renEnd() { glFlush(); }

void renRect(float x, float y, float w, float h, Color c) {
    glColor4f(c.r, c.g, c.b, c.a);
    glBegin(GL_QUADS);
    glVertex2f(x, y);
    glVertex2f(x+w, y);
    glVertex2f(x+w, y+h);
    glVertex2f(x, y+h);
    glEnd();
}

void renTexturedQuad(float x, float y, float w, float h, float u0, float v0, float u1, float v1, Color c) {
    glColor4f(c.r, c.g, c.b, c.a);
    glBegin(GL_QUADS);
    glTexCoord2f(u0, v0); glVertex2f(x, y);
    glTexCoord2f(u1, v0); glVertex2f(x+w, y);
    glTexCoord2f(u1, v1); glVertex2f(x+w, y+h);
    glTexCoord2f(u0, v1); glVertex2f(x, y+h);
    glEnd();
}

void renSetScissor(int x, int y, int w, int h) {
    glEnable(GL_SCISSOR_TEST);
    glScissor(x, cast(int)(g_ren.screenH - y - h), w, h);
}

void renClearScissor() { glDisable(GL_SCISSOR_TEST); }

void renDrawGlyph(float x, float y, const(CachedGlyph)* g, Color c) {
    if (!g || g.w <= 0 || g.h <= 0) return;
    float gx = x + g.xoff;
    float gy = y + g.yoff;
    glEnable(GL_TEXTURE_2D);
    renTexturedQuad(gx, gy, g.w, g.h, g.u0, g.v0, g.u1, g.v1, c);
    glDisable(GL_TEXTURE_2D);
}

void renDrawText(uint fontId, float x, float y, const(wchar)* text, int len, Color c) {
    if (!fontId || !text || len <= 0) return;
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, g_atlas.texture);
    float cx = x;
    float asc = atlasAscent(fontId);
    for (int i = 0; i < len; i++) {
        auto g = atlasGetGlyph(fontId, text[i]);
        if (g) {
            glColor4f(c.r, c.g, c.b, c.a);
            glBegin(GL_QUADS);
            glTexCoord2f(g.u0, g.v0); glVertex2f(cx + g.xoff, y + asc + g.yoff);
            glTexCoord2f(g.u1, g.v0); glVertex2f(cx + g.xoff + g.w, y + asc + g.yoff);
            glTexCoord2f(g.u1, g.v1); glVertex2f(cx + g.xoff + g.w, y + asc + g.yoff + g.h);
            glTexCoord2f(g.u0, g.v1); glVertex2f(cx + g.xoff, y + asc + g.yoff + g.h);
            glEnd();
            cx += g.advance;
        }
    }
    glDisable(GL_TEXTURE_2D);
}

/* ================================================================== */
/*  EVENTS                                                            */
/* ================================================================== */
struct UIEvent {
    enum Type { None, MouseDown, MouseUp, MouseMove, KeyDown, KeyUp, Char, Scroll }
    Type type;
    int mx, my, button, key, scroll;
    wchar ch;
    bool consumed;
}

enum KEY_BACKSPACE=8, KEY_TAB=9, KEY_ENTER=13, KEY_ESCAPE=27, KEY_DELETE=46;
enum KEY_LEFT=37, KEY_UP=38, KEY_RIGHT=39, KEY_DOWN=40;
enum KEY_HOME=36, KEY_END=35, KEY_PAGEUP=33, KEY_PAGEDOWN=34;
enum KEY_CTRL_A=1, KEY_CTRL_C=3, KEY_CTRL_V=22, KEY_CTRL_X=24, KEY_CTRL_Z=26, KEY_CTRL_Y=25;
enum KEY_CTRL_F=6, KEY_CTRL_N=14, KEY_CTRL_O=15, KEY_CTRL_S=19;

__gshared {
    UIEvent g_event;
    bool[256] g_prevKey;
    bool[5] g_prevMouse;
}

void eventsBegin() {
    g_event.type = UIEvent.Type.None;
    g_event.consumed = false;
    g_event.mx = g_win.mouseX;
    g_event.my = g_win.mouseY;
    g_event.scroll = g_win.scrollDelta;
    foreach (i; 0..5) {
        if (g_win.mouseDown[i] && !g_prevMouse[i]) { g_event.type = UIEvent.Type.MouseDown; g_event.button = i; }
        if (!g_win.mouseDown[i] && g_prevMouse[i]) { g_event.type = UIEvent.Type.MouseUp; g_event.button = i; }
        g_prevMouse[i] = g_win.mouseDown[i];
    }
    foreach (i; 0..256) {
        if (g_win.keyDown[i] && !g_prevKey[i]) {
            g_event.type = UIEvent.Type.KeyDown;
            g_event.key = i;
            if (i >= 32 && i < 127) {
                g_event.type = UIEvent.Type.Char;
                bool shift = g_win.keyDown[16];
                if (i >= 'A' && i <= 'Z' && !shift) g_event.ch = cast(wchar)(i + 32);
                else if (shift) {
                    /* basic shift mapping */
                    static immutable char[128] shiftMap = [
                        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                        32,'!','@','#','$','%','^','&','*','(',')', 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,'{','|','}',0,0,
                        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                    ];
                    g_event.ch = (i < 128 && shiftMap[i]) ? cast(wchar)shiftMap[i] : cast(wchar)i;
                } else g_event.ch = cast(wchar)i;
            }
        }
        g_prevKey[i] = g_win.keyDown[i];
    }
    if (g_win.scrollDelta != 0) g_event.type = UIEvent.Type.Scroll;
}

void eventsConsume() { g_event.consumed = true; }

bool eventsInRect(int x, int y, int w, int h) {
    return g_event.mx >= x && g_event.mx < x+w && g_event.my >= y && g_event.my < y+h;
}

/* ================================================================== */
/*  RECT                                                              */
/* ================================================================== */
struct Rect {
    int x, y, w, h;
    bool contains(int px, int py) const { return px >= x && px < x+w && py >= y && py < y+h; }
}

/* ================================================================== */
/*  SCROLLBAR                                                         */
/* ================================================================== */
struct ScrollBar {
    Rect bounds;
    float value, pageSize, totalSize;
    bool vertical = true, dragging;
    int dragStart;
    float dragStartVal;

    void draw() {
        renRect(bounds.x, bounds.y, bounds.w, bounds.h, COL_DARKGRAY);
        float ts = pageSize / totalSize; if (ts > 1) ts = 1; if (ts < 0.02f) ts = 0.02f;
        int track = vertical ? bounds.h : bounds.w;
        int tlen = cast(int)(track * ts); if (tlen < 20) tlen = 20;
        int tpos = cast(int)((track - tlen) * value);
        if (vertical) renRect(bounds.x, bounds.y + tpos, bounds.w, tlen, COL_GRAY);
        else renRect(bounds.x + tpos, bounds.y, tlen, bounds.h, COL_GRAY);
    }

    void update() {
        if (!eventsInRect(bounds.x, bounds.y, bounds.w, bounds.h)) return;
        float ts = pageSize / totalSize; if (ts > 1) ts = 1;
        int track = vertical ? bounds.h : bounds.w;
        int tlen = cast(int)(track * ts); if (tlen < 20) tlen = 20;
        if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) {
            int click = vertical ? (g_event.my - bounds.y) : (g_event.mx - bounds.x);
            int tpos = cast(int)((track - tlen) * value);
            if (click >= tpos && click < tpos + tlen) { dragging = true; dragStart = click; dragStartVal = value; }
            else { value = cast(float)(click - tlen/2) / (track - tlen); if (value<0)value=0; if (value>1)value=1; }
            eventsConsume();
        }
        if (dragging) {
            if (g_event.type == UIEvent.Type.MouseUp && g_event.button == 0) dragging = false;
            else if (g_event.type == UIEvent.Type.MouseMove) {
                int cur = vertical ? (g_event.my - bounds.y) : (g_event.mx - bounds.x);
                value = dragStartVal + cast(float)(cur - dragStart) / (track - tlen);
                if (value<0)value=0; if (value>1)value=1;
            }
            eventsConsume();
        }
    }

    void setScroll(float pos) { value = pos; if (value<0)value=0; if (value>1)value=1; }
}

/* ================================================================== */
/*  BUTTON                                                            */
/* ================================================================== */
struct Button {
    Rect bounds;
    wstring text;
    bool hovered, pressed, justClicked;
    void function(void*) onClick;
    void* userData;
    uint fontId;

    void draw() {
        Color bg = pressed ? Color(0.2f,0.2f,0.25f) : hovered ? Color(0.4f,0.4f,0.45f) : Color(0.3f,0.3f,0.35f);
        renRect(bounds.x, bounds.y, bounds.w, bounds.h, bg);
        renRect(bounds.x, bounds.y, bounds.w, 1, COL_GRAY);
        renRect(bounds.x, bounds.y+bounds.h-1, bounds.w, 1, COL_GRAY);
        if (text.length > 0 && fontId) {
            wchar[256] buf; int len = 0;
            foreach (wchar c; text) { if (len < 255) buf[len++] = c; }
            float tw = atlasTextAdvance(fontId, buf.ptr, len);
            float th = atlasLineHeight(fontId);
            renDrawText(fontId, bounds.x + (bounds.w - tw)/2, bounds.y + (bounds.h - th)/2, buf.ptr, len, COL_WHITE);
        }
    }

    void update() {
        justClicked = false;
        hovered = bounds.contains(g_event.mx, g_event.my);
        if (!hovered) { pressed = false; return; }
        if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) { pressed = true; eventsConsume(); }
        if (g_event.type == UIEvent.Type.MouseUp && g_event.button == 0 && pressed) {
            pressed = false; justClicked = true;
            if (onClick) onClick(userData);
            eventsConsume();
        }
    }
}

/* ================================================================== */
/*  TEXT INPUT (single line)                                          */
/* ================================================================== */
struct TextInput {
    Rect bounds;
    wchar[512] text;
    int textLen, cursor, selStart = -1;
    bool focused, hovered;
    float scrollX, cursorBlink;
    uint fontId;
    void function(TextInput*) onSubmit;

    void insertChar(wchar c) {
        if (textLen >= 511) return;
        if (selStart >= 0 && selStart != cursor) deleteSelection();
        memmove(text.ptr + cursor + 1, text.ptr + cursor, (textLen - cursor) * wchar.sizeof);
        text[cursor++] = c; textLen++; selStart = -1;
    }

    void deleteSelection() {
        if (selStart < 0 || selStart == cursor) return;
        int lo = selStart < cursor ? selStart : cursor;
        int hi = selStart < cursor ? cursor : selStart;
        memmove(text.ptr + lo, text.ptr + hi, (textLen - hi) * wchar.sizeof);
        textLen -= (hi - lo); cursor = lo; selStart = -1;
    }

    void draw() {
        renRect(bounds.x, bounds.y, bounds.w, bounds.h, Color(0.12f,0.12f,0.14f));
        Color bc = focused ? COL_BLUE : COL_GRAY;
        renRect(bounds.x, bounds.y, bounds.w, 1, bc);
        renRect(bounds.x, bounds.y+bounds.h-1, bounds.w, 1, bc);
        renRect(bounds.x, bounds.y, 1, bounds.h, bc);
        renRect(bounds.x+bounds.w-1, bounds.y, 1, bounds.h, bc);
        int px = 4, py = 2;
        renSetScissor(bounds.x+1, bounds.y+1, bounds.w-2, bounds.h-2);
        if (selStart >= 0 && selStart != cursor) {
            int lo = selStart<cursor?selStart:cursor, hi = selStart<cursor?cursor:selStart;
            float x1 = atlasTextAdvance(fontId, text.ptr, lo) - scrollX;
            float x2 = atlasTextAdvance(fontId, text.ptr, hi) - scrollX;
            renRect(bounds.x+px+x1, bounds.y+py, x2-x1, bounds.h-py*2, Color(0.2f,0.4f,0.8f));
        }
        if (fontId) renDrawText(fontId, bounds.x+px-scrollX, bounds.y+py, text.ptr, textLen, COL_WHITE);
        if (focused && cast(int)(cursorBlink*2)%2 == 0) {
            float cx = atlasTextAdvance(fontId, text.ptr, cursor) - scrollX;
            renRect(bounds.x+px+cx, bounds.y+py, 1, bounds.h-py*2, COL_WHITE);
        }
        renClearScissor();
    }

    void update() {
        hovered = bounds.contains(g_event.mx, g_event.my);
        if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) {
            focused = hovered;
            if (focused) {
                cursor = atlasCharIndexFromX(fontId, text.ptr, textLen, g_event.mx - bounds.x - 4 + scrollX);
                selStart = cursor; cursorBlink = 0;
            }
        }
        if (!focused) return;
        if (g_event.type == UIEvent.Type.MouseMove && g_win.mouseDown[0] && selStart >= 0)
            cursor = atlasCharIndexFromX(fontId, text.ptr, textLen, g_event.mx - bounds.x - 4 + scrollX);
        if (g_event.type == UIEvent.Type.Char && g_event.ch >= 32) { insertChar(g_event.ch); cursorBlink = 0; eventsConsume(); }
        if (g_event.type == UIEvent.Type.KeyDown) {
            cursorBlink = 0;
            if (g_event.key == KEY_BACKSPACE) { if (selStart>=0&&selStart!=cursor) deleteSelection(); else if (cursor>0) { memmove(text.ptr+cursor-1, text.ptr+cursor, (textLen-cursor)*wchar.sizeof); cursor--; textLen--; } eventsConsume(); }
            else if (g_event.key == KEY_DELETE) { if (selStart>=0&&selStart!=cursor) deleteSelection(); else if (cursor<textLen) { memmove(text.ptr+cursor, text.ptr+cursor+1, (textLen-cursor-1)*wchar.sizeof); textLen--; } eventsConsume(); }
            else if (g_event.key == KEY_LEFT) { if (cursor>0) cursor--; if (!g_win.keyDown[16]) selStart=-1; eventsConsume(); }
            else if (g_event.key == KEY_RIGHT) { if (cursor<textLen) cursor++; if (!g_win.keyDown[16]) selStart=-1; eventsConsume(); }
            else if (g_event.key == KEY_HOME) { cursor=0; if (!g_win.keyDown[16]) selStart=-1; eventsConsume(); }
            else if (g_event.key == KEY_END) { cursor=textLen; if (!g_win.keyDown[16]) selStart=-1; eventsConsume(); }
            else if (g_event.key == KEY_ENTER) { if (onSubmit) onSubmit(&this); eventsConsume(); }
            else if (g_event.key == KEY_CTRL_A) { selStart=0; cursor=textLen; eventsConsume(); }
            else if (g_event.key == KEY_CTRL_C) { copySel(); eventsConsume(); }
            else if (g_event.key == KEY_CTRL_X) { copySel(); deleteSelection(); eventsConsume(); }
            else if (g_event.key == KEY_CTRL_V) { paste(); eventsConsume(); }
        }
        float cx = atlasTextAdvance(fontId, text.ptr, cursor);
        if (cx - scrollX > bounds.w - 10) scrollX = cx - bounds.w + 10;
        if (cx - scrollX < 0) scrollX = cx;
    }

    void copySel() {
        if (selStart<0||selStart==cursor) return;
        int lo=selStart<cursor?selStart:cursor, hi=selStart<cursor?cursor:selStart;
        char[512] buf; int n=0;
        for (int i=lo;i<hi&&n<510;i++) buf[n++]=cast(char)text[i];
        buf[n]=0; clipboardSetText(buf.ptr);
    }

    void paste() {
        auto cp = clipboardGetText(); if (!cp) return;
        auto p = cp; while (*p) { insertChar(cast(wchar)*p); p++; }
        free(cp);
    }
}

/* ================================================================== */
/*  TEXT BUFFER (multi-line)                                          */
/* ================================================================== */
struct TextLine { wchar[] data; alias data this; }

struct TextBuffer {
    TextLine[] lines;

    void init() { lines.length = 1; lines[0].data.length = 0; }
    void clear() { foreach (ref l; lines) l.data.length = 0; lines.length = 1; lines[0].data.length = 0; }
    int lineCount() { return cast(int)lines.length; }
    int lineLen(int l) { return (l>=0 && l<lines.length) ? cast(int)lines[l].data.length : 0; }
    wchar* linePtr(int l) { return (l>=0 && l<lines.length) ? lines[l].data.ptr : null; }

    void insertChar(int line, int col, wchar c) {
        if (line<0||line>=lines.length) return;
        auto ld = &lines[line].data;
        if (col<0) col=0; if (col>ld.length) col=cast(int)ld.length;
        ld.length = ld.length + 1;
        memmove(ld.ptr+col+1, ld.ptr+col, (ld.length-col-1)*wchar.sizeof);
        (*ld)[col] = c;
    }

    void deleteChar(int line, int col) {
        if (line<0||line>=lines.length) return;
        auto ld = &lines[line].data;
        if (col<0||col>=ld.length) return;
        memmove(ld.ptr+col, ld.ptr+col+1, (ld.length-col-1)*wchar.sizeof);
        ld.length = ld.length - 1;
    }

    void splitLine(int line, int col) {
        if (line<0||line>=lines.length) return;
        auto ld = &lines[line].data;
        if (col<0) col=0; if (col>ld.length) col=cast(int)ld.length;
        TextLine nl;
        nl.data.length = ld.length - col;
        if (nl.data.length > 0) memcpy(nl.data.ptr, ld.ptr+col, nl.data.length*wchar.sizeof);
        ld.length = col;
        lines.length = lines.length + 1;
        memmove(lines.ptr+line+2, lines.ptr+line+1, (lines.length-line-2)*TextLine.sizeof);
        lines[line+1] = nl;
    }

    void joinLines(int line) {
        if (line<0||line+1>=lines.length) return;
        auto a = &lines[line].data; auto b = &lines[line+1].data;
        auto old = a.length; a.length = a.length + b.length;
        if (b.length > 0) memcpy(a.ptr+old, b.ptr, b.length*wchar.sizeof);
        b.length = 0;
        memmove(lines.ptr+line+1, lines.ptr+line+2, (lines.length-line-2)*TextLine.sizeof);
        lines.length = lines.length - 1;
    }

    void loadUTF8(const(char)* data, int len) {
        clear(); lines.length = 0;
        TextLine cur;
        for (int i=0;i<len;i++) {
            char c = data[i];
            if (c == '\n') { lines ~= cur; cur.data.length = 0; }
            else if (c != '\r') cur.data ~= cast(wchar)c;
        }
        lines ~= cur;
        if (lines.length == 0) { lines.length = 1; lines[0].data.length = 0; }
    }

    char* saveUTF8() {
        int total = 0;
        foreach (i, ref l; lines) { total += cast(int)l.data.length; if (i<lines.length-1) total++; }
        auto buf = cast(char*)malloc(total+1);
        int pos = 0;
        foreach (i, ref l; lines) {
            foreach (wc; l.data) buf[pos++] = cast(char)(wc < 128 ? wc : '?');
            if (i<lines.length-1) buf[pos++] = '\n';
        }
        buf[pos] = 0; return buf;
    }
}

/* ================================================================== */
/*  TEXT EDITOR                                                       */
/* ================================================================== */
struct UndoAction {
    enum Type { InsertChar, DeleteChar, InsertNewline, DeleteNewline }
    Type type; int line, col; wchar ch;
}

struct TextEditor {
    TextBuffer buf;
    int curLine, curCol, selLine = -1, selCol = -1;
    bool hasSelection, focused;
    Rect bounds;
    uint fontId;
    float scrollX, scrollY;
    ScrollBar vscroll;
    bool showLineNumbers = true, modified;
    char[256] filePath; int filePathLen;
    UndoAction[] undoStack, redoStack;
    float cursorBlink;
    bool showFind;
    TextInput findInput;

    void init() { buf.init(); findInput.fontId = fontId; findInput.bounds = Rect(0,0,300,24); }
    void clear() {
        buf.clear(); curLine=0; curCol=0; selLine=-1; selCol=-1; hasSelection=false;
        scrollX=0; scrollY=0; undoStack.length=0; redoStack.length=0; modified=false;
    }

    float ch() { return atlasLineHeight(fontId); }

    void pushUndo(UndoAction a) { undoStack ~= a; redoStack.length = 0; }

    void doInsertChar(wchar c) {
        pushUndo(UndoAction(UndoAction.Type.InsertChar, curLine, curCol, c));
        buf.insertChar(curLine, curCol, c); curCol++; modified = true;
    }

    void doDeleteBack() {
        if (curCol > 0) {
            auto c = buf.linePtr(curLine)[curCol-1];
            pushUndo(UndoAction(UndoAction.Type.DeleteChar, curLine, curCol-1, c));
            buf.deleteChar(curLine, curCol-1); curCol--;
        } else if (curLine > 0) {
            int pl = buf.lineLen(curLine-1);
            pushUndo(UndoAction(UndoAction.Type.DeleteNewline, curLine-1, pl));
            buf.joinLines(curLine-1); curLine--; curCol = pl;
        }
        modified = true;
    }

    void doDeleteForward() {
        if (curCol < buf.lineLen(curLine)) {
            auto c = buf.linePtr(curLine)[curCol];
            pushUndo(UndoAction(UndoAction.Type.DeleteChar, curLine, curCol, c));
            buf.deleteChar(curLine, curCol);
        } else if (curLine+1 < buf.lineCount()) {
            pushUndo(UndoAction(UndoAction.Type.DeleteNewline, curLine, curCol));
            buf.joinLines(curLine);
        }
        modified = true;
    }

    void doNewline() {
        pushUndo(UndoAction(UndoAction.Type.InsertNewline, curLine, curCol));
        buf.splitLine(curLine, curCol); curLine++; curCol = 0; modified = true;
    }

    void undo() {
        if (!undoStack.length) return;
        auto a = undoStack[$-1]; undoStack.length--; redoStack ~= a;
        final switch (a.type) {
        case UndoAction.Type.InsertChar: buf.deleteChar(a.line, a.col); curLine=a.line; curCol=a.col; break;
        case UndoAction.Type.DeleteChar: buf.insertChar(a.line, a.col, a.ch); curLine=a.line; curCol=a.col+1; break;
        case UndoAction.Type.InsertNewline: buf.joinLines(a.line); curLine=a.line; curCol=a.col; break;
        case UndoAction.Type.DeleteNewline: buf.splitLine(a.line, a.col); curLine=a.line+1; curCol=0; break;
        }
        modified = true;
    }

    void redo() {
        if (!redoStack.length) return;
        auto a = redoStack[$-1]; redoStack.length--; undoStack ~= a;
        final switch (a.type) {
        case UndoAction.Type.InsertChar: buf.insertChar(a.line, a.col, a.ch); curLine=a.line; curCol=a.col+1; break;
        case UndoAction.Type.DeleteChar: buf.deleteChar(a.line, a.col); curLine=a.line; curCol=a.col; break;
        case UndoAction.Type.InsertNewline: buf.splitLine(a.line, a.col); curLine=a.line+1; curCol=0; break;
        case UndoAction.Type.DeleteNewline: buf.joinLines(a.line); curLine=a.line; curCol=a.col; break;
        }
        modified = true;
    }

    void selectAll() { selLine=0; selCol=0; curLine=buf.lineCount()-1; curCol=buf.lineLen(curLine); hasSelection=true; }

    void getSel(out int sl, out int sc, out int el, out int ec) {
        if (!hasSelection) { sl=sc=el=ec=-1; return; }
        if (selLine<curLine||(selLine==curLine&&selCol<=curCol)) { sl=selLine;sc=selCol;el=curLine;ec=curCol; }
        else { sl=curLine;sc=curCol;el=selLine;ec=selCol; }
    }

    void deleteSelection() {
        if (!hasSelection) return;
        int sl,sc,el,ec; getSel(sl,sc,el,ec);
        if (sl==el) { for (int i=0;i<ec-sc;i++) buf.deleteChar(sl,sc); }
        else {
            for (int i=0;i<buf.lineLen(sl)-sc;i++) buf.deleteChar(sl,sc);
            for (int i=0;i<ec;i++) buf.deleteChar(el,0);
            while (sl+1<=el) { buf.joinLines(sl); el--; }
        }
        curLine=sl; curCol=sc; hasSelection=false; selLine=-1; modified=true;
    }

    void copySelection() {
        if (!hasSelection) return;
        int sl,sc,el,ec; getSel(sl,sc,el,ec);
        int total = 0;
        if (sl==el) total = ec-sc;
        else { total += buf.lineLen(sl)-sc; for (int l=sl+1;l<el;l++) total += buf.lineLen(l)+1; total += ec; }
        auto tmp = cast(char*)malloc(total+1); int pos=0;
        if (sl==el) { auto lp=buf.linePtr(sl); for (int i=sc;i<ec;i++) tmp[pos++]=cast(char)lp[i]; }
        else {
            auto lp=buf.linePtr(sl); for (int i=sc;i<buf.lineLen(sl);i++) tmp[pos++]=cast(char)lp[i];
            for (int l=sl+1;l<el;l++) { tmp[pos++]='\n'; lp=buf.linePtr(l); for (int i=0;i<buf.lineLen(l);i++) tmp[pos++]=cast(char)lp[i]; }
            tmp[pos++]='\n'; lp=buf.linePtr(el); for (int i=0;i<ec;i++) tmp[pos++]=cast(char)lp[i];
        }
        tmp[pos]=0; clipboardSetText(tmp); free(tmp);
    }

    void cutSelection() { copySelection(); deleteSelection(); }

    void paste() {
        auto cp = clipboardGetText(); if (!cp) return;
        if (hasSelection) deleteSelection();
        auto p = cp;
        while (*p) { if (*p=='\n') doNewline(); else if (*p!='\r') doInsertChar(cast(wchar)*p); p++; }
        free(cp);
    }

    void moveCursor(int line, int col, bool select) {
        if (select) { if (!hasSelection) { selLine=curLine; selCol=curCol; hasSelection=true; } }
        else { hasSelection=false; selLine=-1; }
        if (line<0) line=0; if (line>=buf.lineCount()) line=buf.lineCount()-1;
        curLine=line;
        int ll=buf.lineLen(curLine); if (col<0) col=0; if (col>ll) col=ll;
        curCol=col; cursorBlink=0; ensureCursorVisible();
    }

    void ensureCursorVisible() {
        float c = ch();
        float cy = curLine*c - scrollY;
        float vh = bounds.h - 24;
        if (cy<0) scrollY = curLine*c;
        if (cy+c>vh) scrollY = curLine*c - vh + c;
        float cx = fontId ? atlasTextAdvance(fontId, buf.linePtr(curLine), curCol) : 0;
        float vw = bounds.w - (showLineNumbers ? 50 : 0) - 20;
        if (cx-scrollX>vw) scrollX = cx-vw;
        if (cx-scrollX<0) scrollX = cx;
    }

    void draw() {
        float c = ch();
        int gutterW = showLineNumbers ? 50 : 0;
        int firstLine = cast(int)(scrollY / c);
        int visLines = cast(int)((bounds.h - 24) / c) + 2;
        if (firstLine + visLines > buf.lineCount()) visLines = buf.lineCount() - firstLine;
        renRect(bounds.x, bounds.y, bounds.w, bounds.h, Color(0.12f,0.12f,0.15f));

        if (focused) {
            float ly = bounds.y + curLine*c - scrollY;
            renRect(bounds.x, ly, bounds.w, c, Color(0.16f,0.16f,0.2f));
        }

        if (hasSelection) {
            int sl,sc,el,ec; getSel(sl,sc,el,ec);
            for (int l=sl;l<=el;l++) {
                float ly = bounds.y + l*c - scrollY;
                if (ly+c<bounds.y || ly>bounds.y+bounds.h) continue;
                int s = (l==sl)?sc:0, e = (l==el)?ec:buf.lineLen(l);
                float x1 = atlasTextAdvance(fontId, buf.linePtr(l), s);
                float x2 = atlasTextAdvance(fontId, buf.linePtr(l), e);
                renRect(bounds.x+gutterW+x1-scrollX, ly, x2-x1, c, Color(0.2f,0.35f,0.6f));
            }
        }

        renSetScissor(bounds.x, bounds.y, bounds.w, bounds.h-24);

        if (showLineNumbers) {
            renRect(bounds.x, bounds.y, gutterW, bounds.h-24, Color(0.1f,0.1f,0.12f));
            for (int l=firstLine;l<firstLine+visLines && l<buf.lineCount();l++) {
                float ly = bounds.y + l*c - scrollY;
                char[8] num; intToDigits(l+1, num.ptr, 8);
                wchar[8] wn; int nl=0; for (int i=0;num[i]&&i<8;i++) wn[nl++]=cast(wchar)num[i];
                if (fontId) renDrawText(fontId, bounds.x+4, ly, wn.ptr, nl, Color(0.5f,0.5f,0.55f));
            }
        }
        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, g_atlas.texture);
        float asc = atlasAscent(fontId);
        for (int l=firstLine;l<firstLine+visLines && l<buf.lineCount();l++) {
            float ly = bounds.y + l*c - scrollY;
            float tx = bounds.x + gutterW - scrollX;
            auto lp = buf.linePtr(l); int ll = buf.lineLen(l);
            for (int i=0;i<ll;i++) {
                auto g = atlasGetGlyph(fontId, lp[i]);
                if (g) {
                    glColor4f(0.9f,0.9f,0.9f,1.0f);
                    glBegin(GL_QUADS);
                    glTexCoord2f(g.u0,g.v0); glVertex2f(tx+g.xoff, ly+asc+g.yoff);
                    glTexCoord2f(g.u1,g.v0); glVertex2f(tx+g.xoff+g.w, ly+asc+g.yoff);
                    glTexCoord2f(g.u1,g.v1); glVertex2f(tx+g.xoff+g.w, ly+asc+g.yoff+g.h);
                    glTexCoord2f(g.u0,g.v1); glVertex2f(tx+g.xoff, ly+asc+g.yoff+g.h);
                    glEnd();
                    tx += g.advance;
                }
            }
        }
        glDisable(GL_TEXTURE_2D);
        renClearScissor();
        if (focused && cast(int)(cursorBlink*2)%2 == 0) {
            float cx = bounds.x + gutterW + atlasTextAdvance(fontId, buf.linePtr(curLine), curCol) - scrollX;
            float cy = bounds.y + curLine*c - scrollY;
            renRect(cx, cy, 1.5f, c, COL_WHITE);
        }

        int contentH = cast(int)(buf.lineCount() * c);
        int viewH = bounds.h - 24;
        vscroll.bounds = Rect(bounds.x+bounds.w-12, bounds.y, 12, viewH);
        vscroll.totalSize = contentH > 0 ? contentH : 1;
        vscroll.pageSize = viewH;
        vscroll.draw();
        scrollY = vscroll.value * (contentH - viewH);
        auto sb = Rect(bounds.x, bounds.y+bounds.h-24, bounds.w, 24);
        renRect(sb.x, sb.y, sb.w, sb.h, Color(0.18f,0.18f,0.22f));
        /* build status string manually */
        char[128] status;
        int pos = 0;
        void appendStr(const(char)* s) { while (*s && pos < 126) status[pos++] = *s++; }
        void appendInt(int v) { char[16] b; intToDigits(v, b.ptr, 16); int i = 0; while (b[i] && pos < 126) status[pos++] = b[i++]; }
        appendStr("Line "); appendInt(curLine+1);
        appendStr(", Col "); appendInt(curCol+1);
        appendStr("  |  "); appendInt(buf.lineCount()); appendStr(" lines  |  ");
        appendStr(modified ? "Modified" : "Saved");
        status[pos] = 0;
        wchar[128] ws; int sl=0; for (int i=0;status[i]&&i<127;i++) ws[sl++]=cast(wchar)status[i];
        renDrawText(fontId, sb.x+8, sb.y+4, ws.ptr, sl, COL_GRAY);

        if (showFind) {
            findInput.bounds = Rect(bounds.x+80, bounds.y+bounds.h-52, 300, 24);
            renRect(bounds.x+10, bounds.y+bounds.h-52, 68, 24, Color(0.2f,0.2f,0.25f));
            renDrawText(fontId, bounds.x+14, bounds.y+bounds.h-48, "Find:"w.ptr, 5, COL_GRAY);
            findInput.draw();
        }
    }

    void update() {
        vscroll.update();
        if (showFind) { findInput.update(); if (findInput.focused) return; }
        bool shift = g_win.keyDown[16], ctrl = g_win.keyDown[17];

        if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) {
            if (bounds.contains(g_event.mx, g_event.my) && g_event.my < bounds.y+bounds.h-24) {
                focused = true;
                int gutterW = showLineNumbers ? 50 : 0;
                int cl = cast(int)((g_event.my - bounds.y + scrollY) / ch());
                if (cl<0) cl=0; if (cl>=buf.lineCount()) cl=buf.lineCount()-1;
                int cc = atlasCharIndexFromX(fontId, buf.linePtr(cl), buf.lineLen(cl), g_event.mx - bounds.x - gutterW + scrollX);
                moveCursor(cl, cc, shift); eventsConsume();
            } else if (!bounds.contains(g_event.mx, g_event.my)) focused = false;
        }
        if (!focused) return;
        if (g_event.type == UIEvent.Type.MouseMove && g_win.mouseDown[0]) {
            int gutterW = showLineNumbers ? 50 : 0;
            int dl = cast(int)((g_event.my - bounds.y + scrollY) / ch());
            if (dl<0) dl=0; if (dl>=buf.lineCount()) dl=buf.lineCount()-1;
            int dc = atlasCharIndexFromX(fontId, buf.linePtr(dl), buf.lineLen(dl), g_event.mx - bounds.x - gutterW + scrollX);
            moveCursor(dl, dc, true);
        }
        if (g_event.type == UIEvent.Type.KeyDown) {
            cursorBlink = 0;
            if (g_event.key==KEY_LEFT) { if (curCol>0) moveCursor(curLine,curCol-1,shift); else if (curLine>0) moveCursor(curLine-1,buf.lineLen(curLine-1),shift); eventsConsume(); }
            else if (g_event.key==KEY_RIGHT) { if (curCol<buf.lineLen(curLine)) moveCursor(curLine,curCol+1,shift); else if (curLine+1<buf.lineCount()) moveCursor(curLine+1,0,shift); eventsConsume(); }
            else if (g_event.key==KEY_UP) { moveCursor(curLine-1,curCol,shift); eventsConsume(); }
            else if (g_event.key==KEY_DOWN) { moveCursor(curLine+1,curCol,shift); eventsConsume(); }
            else if (g_event.key==KEY_HOME) { moveCursor(curLine,0,shift); eventsConsume(); }
            else if (g_event.key==KEY_END) { moveCursor(curLine,buf.lineLen(curLine),shift); eventsConsume(); }
            else if (g_event.key==KEY_PAGEUP) { moveCursor(curLine-20,curCol,shift); eventsConsume(); }
            else if (g_event.key==KEY_PAGEDOWN) { moveCursor(curLine+20,curCol,shift); eventsConsume(); }
            else if (g_event.key==KEY_BACKSPACE) { if (hasSelection) deleteSelection(); else doDeleteBack(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_DELETE) { if (hasSelection) deleteSelection(); else doDeleteForward(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_ENTER) { if (hasSelection) deleteSelection(); doNewline(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_TAB) { if (hasSelection) deleteSelection(); doInsertChar('\t'); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_A) { selectAll(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_C) { copySelection(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_X) { cutSelection(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_V) { paste(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_Z) { undo(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_Y) { redo(); ensureCursorVisible(); eventsConsume(); }
            else if (g_event.key==KEY_CTRL_F) { showFind=!showFind; if (showFind) findInput.focused=true; eventsConsume(); }
        }
        if (g_event.type == UIEvent.Type.Char && g_event.ch >= 32) {
            if (hasSelection) deleteSelection();
            doInsertChar(g_event.ch); ensureCursorVisible(); eventsConsume();
        }
        if (g_event.type == UIEvent.Type.Scroll && bounds.contains(g_event.mx, g_event.my)) {
            scrollY -= g_event.scroll * ch() * 3;
            if (scrollY<0) scrollY=0;
            float ms = buf.lineCount()*ch() - (bounds.h-24);
            if (scrollY>ms) scrollY = ms>0?ms:0;
            vscroll.setScroll(ms>0?scrollY/ms:0);
            eventsConsume();
        }
    }

    bool loadFile(const(char)* path) {
        version (Windows) {
            auto h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
            if (h == INVALID_HANDLE_VALUE) return false;
            DWORD sz = GetFileSize(h, null);
            auto data = cast(char*)malloc(sz+1);
            DWORD rd; ReadFile(h, data, sz, &rd, null); CloseHandle(h);
            data[rd] = 0; buf.loadUTF8(data, cast(int)rd); free(data);
            filePathLen = cast(int)strlen(path); if (filePathLen>255) filePathLen=255;
            memcpy(filePath.ptr, path, filePathLen); filePath[filePathLen]=0;
            modified = false; return true;
        } else return false;
    }

    bool saveFile(const(char)* path = null) {
        auto p = path ? path : filePath.ptr;
        if (!p || !*p) return false;
        auto data = buf.saveUTF8(); int len = cast(int)strlen(data);
        version (Windows) {
            auto h = CreateFileA(p, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
            if (h == INVALID_HANDLE_VALUE) { free(data); return false; }
            DWORD wr; WriteFile(h, data, len, &wr, null); CloseHandle(h);
        }
        free(data); modified = false;
        if (path) { filePathLen=cast(int)strlen(path); if (filePathLen>255) filePathLen=255; memcpy(filePath.ptr,path,filePathLen); filePath[filePathLen]=0; }
        return true;
    }
}

/* ================================================================== */
/*  MENU BAR                                                          */
/* ================================================================== */
struct MenuItem {
    wstring label, shortcut;
    void function(void*) onClick;
    void* userData;
    bool separator;
}

struct Menu {
    wstring title;
    MenuItem[] items;
    bool open;
    Rect titleRect;
    Rect[] itemRects;
}

struct MenuBar {
    Menu[] menus;
    int hoveredMenu = -1;
    uint fontId;

    void addMenu(wstring title, MenuItem[] items) { menus ~= Menu(title, items); }

    void draw(int barX, int barY, int barW) {
        renRect(barX, barY, barW, 24, Color(0.2f,0.2f,0.24f));
        int x = barX + 4;
        foreach (i, ref m; menus) {
            wchar[32] wl; int len=0; foreach (wchar c; m.title) { if (len<31) wl[len++]=c; }
            float tw = atlasTextAdvance(fontId, wl.ptr, len);
            m.titleRect = Rect(x-2, barY, cast(int)tw+12, 24);
            if (hoveredMenu == i) renRect(m.titleRect.x, m.titleRect.y, m.titleRect.w, m.titleRect.h, Color(0.3f,0.3f,0.35f));
            renDrawText(fontId, x+4, barY+4, wl.ptr, len, COL_WHITE);
            x += cast(int)tw + 16;
        }
        foreach (ref m; menus) {
            if (!m.open) continue;
            int my = barY+24, mw = 220;
            renRect(m.titleRect.x, my, mw, cast(int)(m.items.length*26)+8, Color(0.22f,0.22f,0.26f));
            m.itemRects.length = 0;
            foreach (j, ref item; m.items) {
                auto ir = Rect(m.titleRect.x+4, my+4+cast(int)(j*26), mw-8, 22);
                m.itemRects ~= ir;
                if (item.separator) { renRect(ir.x, ir.y+10, ir.w, 1, COL_GRAY); continue; }
                if (ir.contains(g_event.mx, g_event.my)) renRect(ir.x, ir.y, ir.w, ir.h, Color(0.3f,0.4f,0.6f));
                wchar[64] wi; int il=0; foreach (wchar c; item.label) { if (il<63) wi[il++]=c; }
                renDrawText(fontId, ir.x+8, ir.y+3, wi.ptr, il, COL_WHITE);
                if (item.shortcut.length > 0) {
                    wchar[32] sc; int scl=0; foreach (wchar c; item.shortcut) { if (scl<31) sc[scl++]=c; }
                    renDrawText(fontId, ir.x+ir.w-atlasTextAdvance(fontId,sc.ptr,scl)-8, ir.y+3, sc.ptr, scl, COL_GRAY);
                }
            }
        }
    }

    void update() {
        foreach (i, ref m; menus) {
            if (m.titleRect.contains(g_event.mx, g_event.my)) {
                hoveredMenu = cast(int)i;
                if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) {
                    m.open = !m.open;
                    foreach (ref om; menus) if (&om != &m) om.open = false;
                    eventsConsume();
                }
            }
        }
        foreach (ref m; menus) {
            if (!m.open) continue;
            foreach (j, ref item; m.items) {
                if (j >= m.itemRects.length) continue;
                if (m.itemRects[j].contains(g_event.mx, g_event.my)) {
                    if (g_event.type == UIEvent.Type.MouseDown && g_event.button == 0) {
                        if (item.onClick) item.onClick(item.userData);
                        m.open = false; eventsConsume();
                    }
                }
            }
            if (g_event.type == UIEvent.Type.MouseDown && !m.titleRect.contains(g_event.mx, g_event.my)) {
                bool inside = false;
                foreach (j, ref ir; m.itemRects) if (ir.contains(g_event.mx, g_event.my)) inside = true;
                if (!inside) m.open = false;
            }
        }
        if (hoveredMenu >= 0 && !menus[hoveredMenu].titleRect.contains(g_event.mx, g_event.my))
            if (!menus[hoveredMenu].open) hoveredMenu = -1;
    }

    bool anyOpen() { foreach (ref m; menus) if (m.open) return true; return false; }
}

/* ================================================================== */
/*  NOTEPAD APP                                                       */
/* ================================================================== */
struct Notepad {
    TextEditor editor;
    MenuBar menubar;
    uint bodyFont, menuFont;
    bool running = true, showAbout;

    void init() {
        bodyFont = atlasAddFont("Consolas", 15.0f);
        menuFont = atlasAddFont("Segoe UI", 13.0f);
        if (!bodyFont) bodyFont = atlasAddFont("Courier New", 15.0f);
        if (!menuFont) menuFont = atlasAddFont("Arial", 13.0f);
        if (!bodyFont) bodyFont = atlasAddFont("Lucida Console", 15.0f);
        if (!menuFont) menuFont = atlasAddFont("Tahoma", 13.0f);
        editor.fontId = bodyFont;
        editor.bounds = Rect(0, 24, g_win.width, g_win.height - 24);
        editor.init();
        menubar.fontId = menuFont;
        menubar.addMenu("File"w.ptr[0..4], [
            MenuItem("New"w.ptr[0..3], "Ctrl+N"w.ptr[0..6], &menuNew, cast(void*)&this),
            MenuItem("Open..."w.ptr[0..6], "Ctrl+O"w.ptr[0..6], &menuOpen, cast(void*)&this),
            MenuItem("Save"w.ptr[0..4], "Ctrl+S"w.ptr[0..6], &menuSave, cast(void*)&this),
            MenuItem("Save As..."w.ptr[0..9], ""w.ptr[0..0], &menuSaveAs, cast(void*)&this),
            MenuItem(""w.ptr[0..0], ""w.ptr[0..0], null, null, true),
            MenuItem("Exit"w.ptr[0..4], ""w.ptr[0..0], &menuExit, cast(void*)&this),
        ]);
        menubar.addMenu("Edit"w.ptr[0..4], [
            MenuItem("Undo"w.ptr[0..4], "Ctrl+Z"w.ptr[0..6], &menuUndo, cast(void*)&this),
            MenuItem("Redo"w.ptr[0..4], "Ctrl+Y"w.ptr[0..6], &menuRedo, cast(void*)&this),
            MenuItem(""w.ptr[0..0], ""w.ptr[0..0], null, null, true),
            MenuItem("Cut"w.ptr[0..3], "Ctrl+X"w.ptr[0..6], &menuCut, cast(void*)&this),
            MenuItem("Copy"w.ptr[0..4], "Ctrl+C"w.ptr[0..6], &menuCopy, cast(void*)&this),
            MenuItem("Paste"w.ptr[0..5], "Ctrl+V"w.ptr[0..6], &menuPaste, cast(void*)&this),
            MenuItem(""w.ptr[0..0], ""w.ptr[0..0], null, null, true),
            MenuItem("Select All"w.ptr[0..10], "Ctrl+A"w.ptr[0..6], &menuSelectAll, cast(void*)&this),
            MenuItem("Find"w.ptr[0..4], "Ctrl+F"w.ptr[0..6], &menuFind, cast(void*)&this),
        ]);
        menubar.addMenu("View"w.ptr[0..4], [
            MenuItem("Toggle Line Numbers"w.ptr[0..20], ""w.ptr[0..0], &menuToggleLineNum, cast(void*)&this),
        ]);
        menubar.addMenu("Help"w.ptr[0..4], [
            MenuItem("About"w.ptr[0..5], ""w.ptr[0..0], &menuAbout, cast(void*)&this),
        ]);
    }

    void resize() { editor.bounds = Rect(0, 24, g_win.width, g_win.height - 24); }

    void draw() {
        menubar.draw(0, 0, g_win.width);
        editor.draw();
        if (showAbout) {
            int aw=300,ah=150,ax=(g_win.width-aw)/2,ay=(g_win.height-ah)/2;
            renRect(ax,ay,aw,ah,Color(0.2f,0.2f,0.25f));
            renRect(ax,ay,aw,1,COL_BLUE); renRect(ax,ay+ah-1,aw,1,COL_BLUE);
            renDrawText(menuFont, ax+20, ay+20, "CrossUI Notepad"w.ptr, 16, COL_WHITE);
            renDrawText(menuFont, ax+20, ay+50, "A cross-platform text editor"w.ptr, 28, COL_GRAY);
            renDrawText(menuFont, ax+20, ay+110, "Click to close"w.ptr, 13, COL_CYAN);
        }
    }

    void update() {
        menubar.update();
        if (menubar.anyOpen()) return;
        editor.update();
        if (showAbout && g_event.type == UIEvent.Type.MouseDown) showAbout = false;
    }

    void run() {
        while (running && !g_win.shouldClose) {
            platformPollEvents();
            eventsBegin();
            resize();
            update();
            renBegin(g_win.width, g_win.height);
            draw();
            renEnd();
            platformSwapBuffers();
            if (g_event.type == UIEvent.Type.KeyDown && g_event.key == KEY_ESCAPE) {
                if (editor.showFind) editor.showFind = false;
                else if (showAbout) showAbout = false;
            }
        }
        DestroyWindow(g_win.hwnd);
    }
}

/* menu callbacks */
void menuNew(void* ud) { (cast(Notepad*)ud).editor.clear(); }
void menuOpen(void* ud) {
    version (Windows) {
        OPENFILENAMEA ofn; char[260] fn;
        memset(&ofn, 0, ofn.sizeof); ofn.lStructSize = ofn.sizeof;
        ofn.hwndOwner = g_win.hwnd; ofn.lpstrFile = fn.ptr; ofn.nMaxFile = 260;
        ofn.lpstrFilter = "Text Files\0*.txt\0All Files\0*.*\0\0";
        ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST; fn[0] = 0;
        if (GetOpenFileNameA(&ofn)) (cast(Notepad*)ud).editor.loadFile(fn.ptr);
    }
}
void menuSave(void* ud) {
    auto np = cast(Notepad*)ud;
    if (np.editor.filePathLen > 0) np.editor.saveFile(); else menuSaveAs(ud);
}
void menuSaveAs(void* ud) {
    version (Windows) {
        OPENFILENAMEA ofn; char[260] fn;
        memset(&ofn, 0, ofn.sizeof); ofn.lStructSize = ofn.sizeof;
        ofn.hwndOwner = g_win.hwnd; ofn.lpstrFile = fn.ptr; ofn.nMaxFile = 260;
        ofn.lpstrFilter = "Text Files\0*.txt\0All Files\0*.*\0\0";
        ofn.lpstrDefExt = "txt"; ofn.Flags = OFN_OVERWRITEPROMPT; fn[0] = 0;
        if (GetSaveFileNameA(&ofn)) (cast(Notepad*)ud).editor.saveFile(fn.ptr);
    }
}
void menuExit(void* ud) { (cast(Notepad*)ud).running = false; }
void menuUndo(void* ud) { (cast(Notepad*)ud).editor.undo(); }
void menuRedo(void* ud) { (cast(Notepad*)ud).editor.redo(); }
void menuCut(void* ud) { (cast(Notepad*)ud).editor.cutSelection(); }
void menuCopy(void* ud) { (cast(Notepad*)ud).editor.copySelection(); }
void menuPaste(void* ud) { (cast(Notepad*)ud).editor.paste(); }
void menuSelectAll(void* ud) { (cast(Notepad*)ud).editor.selectAll(); }
void menuFind(void* ud) { auto np = cast(Notepad*)ud; np.editor.showFind = !np.editor.showFind; }
void menuToggleLineNum(void* ud) { (cast(Notepad*)ud).editor.showLineNumbers = !(cast(Notepad*)ud).editor.showLineNumbers; }
void menuAbout(void* ud) { (cast(Notepad*)ud).showAbout = true; }

/* ================================================================== */
/*  MAIN                                                              */
/* ================================================================== */
int main() {
    if (!platformInit(960, 640, "CrossUI Notepad")) return 1;
    renInit();
    atlasInit();
    Notepad notepad;
    notepad.init();
    notepad.run();
    return 0;
}
